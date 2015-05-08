import dexpect;
import std.stdio;
import std.algorithm;
import core.sys.posix.unistd;
import std.string;
import std.process;
import core.thread;
void main(string[] args){

/+        auto pty = spawnProcessInPty("/bin/sh", ["sh", "-c ls"]);

        string allData;
        auto tmp = pty.readFromPty;

        allData ~= tmp;
        pty.sendToPty("whoami\n");

        Thread.sleep(100.msecs);
        tmp = pty.readFromPty;

        allData ~= tmp;
        tmp = pty.readFromPty;

        allData ~= tmp;
        writefln("done\n\nData:\n@%s@", allData);
        +/
        auto expect = new Expect("/usr/bin/python", ["/usr/bin/python"]);
        expect.expect(">");
        expect.sendLine("1+1");
        expect.expect("2");
        writefln("Woop!");
}
