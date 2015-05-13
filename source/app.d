import dexpect;
import std.stdio;
import core.thread;
import std.process : environment;

version(ExpectMain){}
else
void main(string[] args){

	if(args.length == 2)
		installAll;
	if(args.length == 1){
		auto e = new Expect("/usr/bin/python");
		e.expect(">>>");
		e.sendLine("1+1");
		e.expect("2");
		e.expect(">>>");
		e.sendLine("quit()");
		writefln("Before: %s", e.before);
		writefln("After: %s", e.after);
	}
}

void installAll(){
	auto e = new Expect("/bin/sh");
	e.expect("#");
	e.timeout = 15.minutes;
	e.sendLine("java -jar prereqinstaller.jar iim toolkit httpserver httpserverplugin");
	e.expect("media/iap-prereqs/IIM");
	e.sendLine("");
	e.expect("iap-repository");
	e.sendLine("/media/iap-prereqs/tk242");
	e.expect("iap-3.0.11.0)");
	e.sendLine("/opt/IBM/IAP");
	e.expect("y|n]?");
	e.sendLine("n");
	e.expect("liberty/supplements");
	e.sendLine("/media/iap-prereqs/Liberty");
	e.expect("HTTPServer");
	e.sendLine("");
	e.expect("80");
	e.sendLine("");
	e.expect("y|n]?");
	e.sendLine("n");
	e.expect("liberty/supplements");
	e.sendLine("/media/iap-prereqs/Liberty");
	e.expect("Plugins)");
	e.sendLine("");
	e.expect("y|n]?");
	e.sendLine("n");
	e.expect("#");
	File allOutput = File("allOutput.txt", "w");
	allOutput.writefln("%s", e.data);
}
