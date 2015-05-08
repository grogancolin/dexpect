import dexpect;
import std.stdio;
import std.algorithm;
import core.sys.posix.unistd;
import std.string;
import std.process;
import core.thread;
void main(string[] args){

        auto expect = new Expect("/usr/bin/python", ["/usr/bin/python"]);
        expect.expect(">");
        expect.sendLine("1+1");
        expect.expect("2");
        writefln("Woop!");
}
