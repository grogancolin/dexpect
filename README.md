D Implementation of the Expect framework (http://expect.sourceforge.net/)

Will run on both linux and windows - though hasnt been vigorously tested on either yet.
Can be used as a standalone appliction or as a library as part of your app.

Note: This is very early days and this lib will probably change quite a lot!

To build the standalone app, clone this repo and run:

```dub build --config=expect-app```

You should see a "dexpect" executable in the project root. (dexpect.exe on windows).

To use it directly in D code, simply add it to your dub.json and away you go.

Sample use cases:

From D code

```
Linux
Expect e = new Expect("/bin/sh");
e.expect("$");
e.sendLine("whoami");
e.expect("$");
e.sendLine("exit");
e.readAllAvailable; // reads until the subprocess stops writing
writefln("Before: %s", e.before); // will print everything before the last expect ('$' in this case)
writefln("After: %s", e.after); // will print the last expect + everything after it
```

```
Windows
Expect e = new Expect(`C:\Windows\System32\cmd.exe`);
e.expect(">");
e.sendLine("echo %USERNAME%");
e.expect(">");
e.sendLine("exit");
e.readAllAvailable; // reads until the subprocess stops writing
writefln("Before: %s", e.before); // will print everything before the last expect ('$' in this case)
writefln("After: %s", e.after); // will print the last expect + everything after it
```

From a script file - 
```
win{
   set shell=C:\Windows\System32\cmd.exe
   set testData=Windoze
   set prompt=>
}
linux{
   set shell=/bin/sh
   set testData=Nix
   set prompt=$
}
set cmd="echo 'Hello'" ~ $(testData)

spawn $(shell)
expect $(prompt)
send $(cmd)
win expect "Hello" ~ $(testData)
linux expect "Hello Nix"
expect $(prompt)

```
Running the above:
```
 ./dexpect testFile.txt -v
Command line args:
["--help":false, "--verbose":true, "<file>":["testFile.txt"]]

Executing script: testFile.txt
Spawn  : /bin/sh 
Expect : ["$"]
Sending: echo 'Hello' Nix\n
Expect : ["Hello Nix"]
Expect : ["$"]

```

The scripting language is built on blocks of statemnts. A block is all statements between a '{' '}' pair.

- Each block can have any number of Attributes before it (currently on "win" and "linux" are attributes).
- Each block can contain any number of sub blocks (with their own attributes if required).
- Each block can contain any number of statements (Spawn, expect, send and set).

Set sets a variable. Syntax is<br/>
```set varname=varvalue```<br/>
varname cannot contain an '=', '~' char.<br/>
varvalue can be anything, including a previously defined variable.<br/>
The '~' char means concatenate, so<br/>
```set var=value ~ $(othervar)```<br/>
will prepent "value" onto $(othervar)<br/>

Special variables include "timeout" which sets the timeout on any subsequent 'expect' calls, and "$?" which contains the index of the last succesful "expect" statement. This will be useful for 'if' statements, planned in a future build.

Spawn \<string> spawns a new process. The process executed is \<string>
 - All following expect and send statements will operate on the last spawned process.

Expect \<string> waits for \<string> in the output of previous Spawn. 
 - If after Timeout seconds (default=5) <string> is not found, script will stop executing and be marked as "failed".
 - Can expect any previously set variable with $(varname).

Send \<string> sends \<string> to the spawned process.
 - Can send any previously set variable with $(varname).
I used blocks because I plan on supporting functions in the future. A function will simply be a block 

TODOs:

-> ~~Implement an expect(string[] toExpect) method, that returns an int representing the index of the array which was matched.
   This will allow int idx = expect(["password:", "username:"]); constructs to handle multiple cases in one expect call.~~ DONE
    
-> Properly test, and write unittests 

-> Probably lots of other things...
