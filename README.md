Introduction
------------
Inotify is on erlang port for the Linux inotify API allowing one to monitor
changes to files and directory in the filesystem.

Installation
------------
If building from git:
 `aclocal ; autoconf ; automake --add-missing ; ./configure ; make`

If building from the tar ball:
 `./configure ; make`

This will build in-tree (i.e. the binaries/beams will be in the `src`
directory).

If you want to install, do:
 `./configure --prefix=/usr ; make ; sudo make install`

Prefix /usr will install in the OTP installation directory on a
debian/ubuntu. Adjust to something fitting.

To test, execute:
 `make test`

This will run `inotify:test()` and you should see output similar to:

```
 $ make test
 erl -noshell -eval "inotify:test(), erlang:halt()."
 Simplistic test/example
 Start... Open the port and receive a file descriptor... F = 3
 list..L = [3]
 Watch for any changes in a Directory... W = 1
 launch listener....
 start playing with the file...
 attempt to create file "../test/file"
 listener got: {event,1,[create],0,[102,105,108,101,0,0,0,0,0,0,0,0,0,0,0,0]}
 listener got: {event,1,[create],0,[102,105,108,101,0,0,0,0,0,0,0,0,0,0,0,0]}
 write a message to file
 listener got: {event,1,[modify],0,[102,105,108,101,0,0,0,0,0,0,0,0,0,0,0,0]}
 close the file
 listener got: {event,1,
                     [close_write],
                     0,
                     [102,105,108,101,0,0,0,0,0,0,0,0,0,0,0,0]}
 delete file "../test/file"
 listener got: {event,1,[delete],0,[102,105,108,101,0,0,0,0,0,0,0,0,0,0,0,0]}
 end playing with file
 stop the listener...
 stop inotify controller...
 test is now concluded
```

The test creates a file in the test directory, writes to it and then deletes it.


Using inoteefy
--------------

inoteefy associates a callback fun with a file.

- `inoteefy:watch(File,Fun) -> ok`
- `inoteefy:unwatch(File) -> ok`

If `File` is watched, `Fun/1` will be called everytime File is
touched. The argument to `Fun` will look like `{File,[Mask],Cookie,Name}`:

- `Mask - atom()` - see inotify docs (man inotify).
- `Cookie - integer()` - see inotify docs (man inotify). Only used for dirs.
- `Name - string()` - see inotify docs (man inotify). Only used for dirs.

Example:

```
(doozy@dixie)19> inoteefy:watch("/home/masse/.emacs",fun(X)->io:fwrite("~p~n",[X])end).
ok                                                                              
<changing the .emacs file>
{"/home/masse/.emacs",[modify],0,[]}                                            
{"/home/masse/.emacs",[open],0,[]}                                              
{"/home/masse/.emacs",[modify],0,[]}
{"/home/masse/.emacs",[modify],0,[]}
{"/home/masse/.emacs",[close_write],0,[]}
{"/home/masse/.emacs",[modify],0,[]}
{"/home/masse/.emacs",[open],0,[]}
{"/home/masse/.emacs",[modify],0,[]}
{"/home/masse/.emacs",[close_write],0,[]}
(doozy@dixie)20> inoteefy:unwatch("/home/masse/.emacs").
ok
```


Using inotify
-------------

This is the erlang program `inotify.erl`, not the underlying linux syscall.

For an example on how to use inotify take a look at the function
`test/0` in `inotify.erl`.

The listener process gets a message of the form
   `{event, WatchDescriptor, EventList, Cookie, Name}`
where
   - `WatchDescriptor` is the watch descriptor which caused the event
   - `EventList` is one or more event which is/are the reason for the message. These 
     include:
       `access`, `attrib`, `close_write`, `close_nowrite`, `create`, `delete`, `delete_self`,
       `modify`, `move_self`, `moved_from`, `moved_to`, `open`
   - `Cookie`
   - `Name` is the filesystem name relative to the base which caused the event. It
     the example test above the list [102,105,108,101,0,0,0,0,0,0,0,0,0,0,0,0]
     is the string "file" zero padded which is the file referred to by the
     event relative to the test directory with the attached inotify watch.


License
-------
In short, you can do anything you want with the code including using it as part
of you plan for world domination (if your successful can I have one of the nicer
countries please). No responsiblity it taken for the fitness of the any purpose,
etc, etc. The only thing I ask is that if you find a bug and fix send me the
patch. Likewise, feature suggestions and patches are welcome.

TODO
----
* add support for multiple controller functions
* Write some documentation!



Release History
---------------
20100206 version 0.3 on github  
20090221 release 0.2 bug fix  
20080929 initial release version 0.1
