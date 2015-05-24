D Implementation of the Expect framework (http://expect.sourceforge.net/)

Will run on both linux and windows - though hasnt been vigorously tested on either yet.
Can be used as a standalone appliction or as a library as part of your app.

Note: This is very early days and this lib will probably change quite a lot!

To build the standalone app, clone this repo and run:

```dub build --config=expect-app```


Add it to your dub.json to use it from D code.

Sample use cases:

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

Sample script file:
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

TODOs:

-> ~~Implement an expect(string[] toExpect) method, that returns an int representing the index of the array which was matched.
   This will allow int idx = expect(["password:", "username:"]); constructs to handle multiple cases in one expect call.~~ DONE
    
-> Properly test, and write unittests 

-> Probably lots of other things...
