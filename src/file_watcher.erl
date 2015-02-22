-module(file_watcher).
-export([start_link/0]).
-export([add_watcher/2, add_watcher/1]).
-behaviour(gen_server).
-export([init/1, terminate/2, handle_call/3, handle_cast/2, handle_info/2, code_change/3]).

-record(state, {inotify_pid, fd, file_parts=dict:new(), watchers=dict:new()}).

-export([example/0]).
example() ->
	{ok,_Pid}=file_watcher:start_link(),
	{ok,Ref}=file_watcher:add_watcher("a/b/c"),
	% mkdir a/b/c/y; touch a/b/c/y/z; rm a/b/c/y/z; rmdir a/b/c/y; touch a/b/x; rm a/b/x; touch a/b/c/x; rm a/b/c/x; rm a/b/c/asdf; touch asdf; mv asdf a/b/c/; mkdir a/b/c/f; mv a/b/c/f a/b/c/g; rmdir a/b/c/g; echo asdf >a/b/c/x; echo xyz>>a/b/c/x; mv a/b/c/x a/b/c/y; rm a/b/c/y
	Ref.

%dbg_print(Msg) ->
%	io:format(Msg).
%dbg_print(Msg, Args) ->
%	io:format(Msg, Args).
dbg_print(_Msg, _Args) ->
	ok.

start_link() ->
    gen_server:start_link(?MODULE, [], []).

init([]) ->
	register(?MODULE, self()),
	InotifyPid = inotify:start_link(self()),
	{ok,Fd} = inotify:open(),

	{ ok, #state{inotify_pid=InotifyPid, fd=Fd} }.

terminate(normal, State) ->
	inotify:close(State#state.fd),
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

handle_call({add_watcher, FilePattern, Target}, _From, State) ->
	Ref = make_ref(),
	do_add_watcher(FilePattern, Target, Ref, State);

handle_call(_, _From, State) ->
	{noreply, State}.

handle_cast(_, State) ->
	{noreply, State}.

handle_info({event, Wd, Mask, Cookie, Name}, State) ->
	dbg_print("We got an event: ~p~n", [{event, Wd, Mask, Cookie, Name}]),
	{noreply, handle_file_event(Wd, Mask, Cookie, Name, State)};

handle_info(Msg, State) ->
	dbg_print("We got a message: ~p~n", [Msg]),
	{noreply, State}.

add_watcher(FilePattern) ->
	add_watcher(FilePattern, self()).

add_watcher(FilePattern, Target) ->
	gen_server:call(?MODULE, {add_watcher, FilePattern, Target}).

do_add_watcher(FilePattern, Target, Ref,
		State=#state{fd=Fd, file_parts=FilePartsDict, watchers=Watchers}) ->
	FileParts = filename:split(FilePattern),
	FileParts2 = case filename:pathtype(FilePattern) of
		relative -> [ "." | FileParts ];
		_        -> FileParts
	end,
	[ FirstFilePart | OtherFileParts ] = FileParts2,

	NewState = State#state{file_parts=dict:store(Ref, {FileParts2, Target}, FilePartsDict),
		watchers=add_directory_watcher(Fd, FirstFilePart, OtherFileParts, Ref, Target, Watchers)},
	{reply, {ok, Ref}, NewState}.

add_directory_watcher(Fd, Directory, [NextPart | OtherFileParts], Ref, Target, Watchers) ->
	{ok, Wd} = inotify:add(Fd, Directory,
		[create, delete, delete_self, modify, move_self, moved_from, moved_to, close_write]),
	Watchers2 = dict:store(Wd, {Directory, [NextPart | OtherFileParts], Ref, Target}, Watchers),

	Existing = filelib:wildcard(NextPart, Directory),

	Watchers3 = lists:foldl(fun (File, OldWatchers) ->
		add_file_watcher(Fd, filename:join(Directory, File), OtherFileParts, Ref, Target, OldWatchers)
	end, Watchers2, Existing),

	Watchers3.

add_file_watcher(Fd, File, OtherFileParts, Ref, Target, Watchers) ->
	case filelib:is_dir(File) of
		true ->
			case OtherFileParts of
				%TODO If the pattern matches a directory, we watch all files inside it (including
				%     those in subdirectories). This may be quite handy, but it may come as a surprise
				%     to the user. We should support "**" anywhere in the pattern and do away with
				%     this special case.
				[] -> add_directory_watcher(Fd, File, ["*"], Ref, Target, Watchers);
				_  -> add_directory_watcher(Fd, File, OtherFileParts, Ref, Target, Watchers)
			end;
		false ->
			case OtherFileParts of
				[] -> Target ! { add, Ref, File };
				_  -> dbg_print(
						"Ignoring file ~p because a directory was expected. Rest of path is ~p.~n",
						[File, OtherFileParts])
			end,

			Watchers
	end.

handle_file_event(Wd, _Mask = [create | _], _Cookie, Name, State) ->
	{Directory, [NextPart | OtherFileParts], Ref, Target} = dict:fetch(Wd, State#state.watchers),

	case fnmatch(Name, NextPart) of
		true ->
			dbg_print("Watching new file/dir ~p in ~p~n", [Name, Directory]),
			Watchers2 = add_file_watcher(State#state.fd, filename:join(Directory, Name), OtherFileParts,
				Ref, Target, State#state.watchers),
			State#state{watchers=Watchers2};
		false ->
			dbg_print("New file/dir ~p in ~p doesn't match the pattern ~p.~n",
				[Name, Directory, NextPart]),
			State
	end;

handle_file_event(_Wd, _Mask = [delete, isdir | _], _Cookie, _Name, State) ->
	State;

handle_file_event(Wd, _Mask = [delete | _], _Cookie, Name, State) ->
	{Directory, [NextPart | OtherFileParts], Ref, Target} = dict:fetch(Wd, State#state.watchers),

	case {fnmatch(Name, NextPart), OtherFileParts} of
		{true, []} ->
			dbg_print("Watched file ~p in ~p has been deleted~n", [Name, Directory]),
			Target ! { delete, Ref, filename:join(Directory, Name) },
			State;
		{true, _} ->
			dbg_print("Deleted file ~p in ~p only matches the first part of the pattern ~p.~n",
				[Name, Directory, [NextPart|OtherFileParts]]),
			State;
		{false, _} ->
			dbg_print("Deleted file ~p in ~p doesn't match the pattern ~p.~n",
				[Name, Directory, NextPart]),
			State
	end;

handle_file_event(Wd, _Mask = [delete_self | _], _Cookie, _Name, State) ->
	Watchers2 = dict:erase(Wd, State#state.watchers),
	State#state{watchers=Watchers2};

handle_file_event(Wd, _Mask = [modify | _], _Cookie, Name, State) ->
	{Directory, [NextPart | OtherFileParts], Ref, Target} = dict:fetch(Wd, State#state.watchers),

	case {fnmatch(Name, NextPart), OtherFileParts} of
		{true, []} ->
			dbg_print("Watched file ~p in ~p has been modified~n", [Name, Directory]),
			Target ! { modify, Ref, filename:join(Directory, Name) },
			State;
		{true, _} ->
			dbg_print("Modified file ~p in ~p only matches the first part of the pattern ~p.~n",
				[Name, Directory, [NextPart|OtherFileParts]]),
			State;
		{false, _} ->
			dbg_print("Modified file ~p in ~p doesn't match the pattern ~p.~n",
				[Name, Directory, NextPart]),
			State
	end;

handle_file_event(Wd, _Mask = [close_write | _], _Cookie, Name, State) ->
	{Directory, [NextPart | OtherFileParts], Ref, Target} = dict:fetch(Wd, State#state.watchers),

	case {fnmatch(Name, NextPart), OtherFileParts} of
		{true, []} ->
			dbg_print("Watched file ~p in ~p has been modified~n", [Name, Directory]),
			Target ! { close_write, Ref, filename:join(Directory, Name) },
			State;
		{true, _} ->
			dbg_print("Modified file ~p in ~p only matches the first part of the pattern ~p.~n",
				[Name, Directory, [NextPart|OtherFileParts]]),
			State;
		{false, _} ->
			dbg_print("Modified file ~p in ~p doesn't match the pattern ~p.~n",
				[Name, Directory, NextPart]),
			State
	end;

handle_file_event(Wd, _Mask = [move_from | Mask2], Cookie, Name, State) ->
	handle_file_event(Wd, [delete | Mask2], Cookie, Name, State);

handle_file_event(Wd, _Mask = [move_to | Mask2], Cookie, Name, State) ->
	handle_file_event(Wd, [create | Mask2], Cookie, Name, State);

handle_file_event(Wd, _Mask = [move_self | Mask2], Cookie, Name, State) ->
	handle_file_event(Wd, [delete_self | Mask2], Cookie, Name, State);

handle_file_event(_Wd, _Mask, _Cookie, _Name, State) ->
	State.

fnmatch_compile(Pattern) ->
	% escape anything that we won't replace later (i.e. not '*' or '?') and that doesn't have
	% a special meaning after a backslash (i.e. anything that is not a number or letter)
	Pattern1 = re:replace(Pattern, "[^a-zA-Z0-9*?]", "\\\\&", [global]),
	% replace wildcards
	Pattern2 = re:replace(Pattern1, "\\*", ".*"),
	Pattern3 = re:replace(Pattern2, "\\?", "."),
	% add anchors
	Pattern4 = ["^", Pattern3, "$"],
	% compile the resulting regex
	re:compile(Pattern4, [dotall, ungreedy]).

fnmatch(Filename, Pattern) ->
	{ok, Re} = fnmatch_compile(Pattern),
	case re:run(Filename, Re, [{capture,none}]) of
		match   -> true;
		nomatch -> false
	end.
