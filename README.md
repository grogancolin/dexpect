D Implementation of the Expect framework (http://expect.sourceforge.net/)

Will run on both linux and windows - though hasnt been vigorously tested on either yet.
Can be used as a standalone appliction or as a library as part of your app.

To build the standalone app, clone this repo and run:<br>
```dub build --config=expect-app```
<br>


Add it to your dub.json to use it from D code.<br>
Sample use cases:<br>
Linux
```
Expect e = new Expect("/bin/sh");
e.expect("$");
e.sendLine("whoami");
e.expect("$");
e.sendLine("exit");
e.readAllAvailable; // reads until the subprocess stops writing
writefln("Before: %s", e.before); // will print everything before the last expect ('$' in this case)
writefln("After: %s", e.after); // will print the last expect + everything after it
```
Windows
```
Expect e = new Expect(`C:\Windows\System32\cmd.exe`);
e.expect(">");
e.sendLine("echo %USERNAME%");
e.expect(">");
e.sendLine("exit");
e.readAllAvailable; // reads until the subprocess stops writing
writefln("Before: %s", e.before); // will print everything before the last expect ('$' in this case)
writefln("After: %s", e.after); // will print the last expect + everything after it
```

TODOs:

-> Implement an expect(string[] toExpect) method, that returns an int representing the index of the array which was matched.
   This will allow int idx = expect(["password:", "username:"]); constructs to handle multiple cases in one expect call.
    
-> Properly test, and write unittests 

-> Probably lots of other things...
