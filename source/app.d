import dexpect;
import merged;
import std.stdio;
import std.algorithm;
import core.sys.posix.unistd;
import std.string;
import std.process;
import core.thread;
void main(string[] args){

	auto e = new Expect2("cmd.exe");
	e.readNextChunk;
	writefln("Data: %s", e.data);
	e.expect("reserved.");
	e.sendLine("ipconfig");

	Thread.sleep(50.msecs);
	e.readNextChunk;
	writefln("New Data: %s", e.data);
}
