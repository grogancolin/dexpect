module expectapp;

version(Windows){
	enum isWindows=true;
	enum isLinux=false;
}
version(Posix){
	enum isWindows=false;
	enum isLinux=true;
}
version(DExpectMain){
	import docopt;
	import std.stdio;
	import dexpect;
	import pegged.grammar;
	import std.string;
	import std.file;
	import std.algorithm;
	const string doc =
"dexpect
Usage:
    dexpect [-h] <file>
Options:
    -h --help    Show this message
";
	string[string] customVariables;
	int main(string[] args){
		File tmp = File("ScriptParser.d", "w");
		tmp.writefln("%s", grammar(scriptGrammar));
		auto arguments = docopt.docopt(doc, args[1..$], true, "dexpect 0.0.1");
		writeln(arguments);
		File expectScript = File(arguments["<file>"].toString, "r");
		auto parsedScript = ExpectScript(arguments["<file>"].toString.readText);
		writefln("%s", parsedScript);

		assert(parsedScript.name=="ExpectScript");
		// ensure there is a "Script" element
		assert(parsedScript.children.length == 1);
		assert(parsedScript.children[0].name == "ExpectScript.Script");

		auto script = parsedScript.children[0];
		Expect expect;
		string[string] variables;
		void handleSet(ParseTree p){
			if(p.children.length != 2) return;
			string name = p.children[0].children[0].matches[0]; //Set.SetName.VerName
			string value="";
			foreach(child; p.children[1].children){//p.children[1] == Set.SetVal
				switch(child.name){
					case "ExpectScript.Variable":
						if(!variables.keys.canFind(child.matches[0])) throw new ExpectException("Undefined variable");
						value ~= variables[child.matches[0]];
						break;
					case "ExpectScript.String":
						value ~= child.matches[0];
						break;
					default: break;
				}
			}
			variables[name] = value;
		}

		void handleSpawn(ParseTree p){
			if(p.children.length != 1) throw new ExpectException("Error parsing file. ");
			string toSpawn="";
			foreach(child; p.children[0].children){
				switch(child.name){
					case "ExpectScript.Variable":
						if(!variables.keys.canFind(child.matches[0])) throw new ExpectException("Undefined variable");
						toSpawn ~= variables[child.matches[0]];
						break;
					case "ExpectScript.String":
						toSpawn ~= child.matches[0];
						break;
					default: writefln("Error - %s", p); break;
				}
			}
			expect = new Expect(toSpawn);

		}
		void handleExpect(ParseTree p){
			if(expect is null)
				throw new ExpectException("Cannot expect before spawning");
			if(p.children.length != 1) throw new ExpectException("Error");
			string toExpect="";
			foreach(child; p.children[0].children){
				switch(child.name){
					case "ExpectScript.Variable":
						if(!variables.keys.canFind(child.matches[0])) throw new ExpectException("Undefined variable");
						toExpect ~= variables[child.matches[0]];
						break;
					case "ExpectScript.String":
						toExpect ~= child.matches[0];
						break;
					default: break;
				}
			}
			expect.expect(toExpect);
		}
		void handleSend(ParseTree p){
			if(expect is null)
				throw new ExpectException("Cannot send data before spawning");
			if(p.children.length != 1) throw new ExpectException("Error sending");
			string toSend="";
			foreach(child; p.children[0].children){
				switch(child.name){
					case "ExpectScript.Variable":
						if(!variables.keys.canFind(child.matches[0])) throw new ExpectException("Undefined variable");
						toSend ~= variables[child.matches[0]];
						break;
					case "ExpectScript.String":
						toSend ~= child.matches[0];
						break;
					default: break;
				}
			}
			expect.sendLine(toSend);
		}
		script.children
			.map!(a => a.children[0])
			.each!((a){
					switch(a.name){
						case "ExpectScript.Set": handleSet(a); break;
						case "ExpectScript.Spawn" : handleSpawn(a); break;
						case "ExpectScript.Expect" : handleExpect(a); break;
						case "ExpectScript.Send" : handleSend(a); break;
						default: break;
					}
					});
		writefln("%s", variables);
		return 0;

		foreach(ref line; expectScript.byLine){
			line.strip;
			if(line.length==0) continue;
			if(line[0]=='#') continue;
			// TODO: This switch statement is brittle, write a better command handler
			switch(line.startsWith("set", "spawn", "expect", "send", "print")){
				case 1:
					if(!line.canFind("=")) throw new ExpectException("Parsing error");
					auto equalsIdx = line.indexOf("=");
					string name = line[4..equalsIdx].idup;
					string value = line[equalsIdx+1..$].idup;
					customVariables[name] = value;
					if(expect !is null && name=="timeout"){
						expect.timeout = value.to!long;
						writefln("Timeout is: %s", expect.timeout);
					}
					break;
				case 2:
					string cmd = line[6..$].idup;
					string[] cmdArgs;
					if(cmd.canFind(" ")){
						cmdArgs = cmd[cmd.indexOf(" ")..$].idup.split(" ");
						cmd = cmd[0..cmd.indexOf(" ")];
					}
					expect = new Expect(cmd, cmdArgs);
					if(customVariables.keys.canFind("timeout")){
						expect.timeout = customVariables["timeout"].to!long;
						writefln("Timeout is: %s", expect.timeout);
					}
					break;
				case 3:
					assert(expect !is null, "Error, must spawn before expect");
					string toExpect = line[7..$].idup;
					expect.expect(toExpect);
					break;
				case 4:
					assert(expect !is null, "Error, must spawn before sending data");
					expect.sendLine(line[5..$].idup);
					break;
				case 5:
					if(line == "print all")
						expect.readAllAvailable;
					else expect.read;
					writefln("All data:\n%s", expect.data);
					break;
				default: writefln("Parsing error"); return 1;
			}
		}
		return 0;
	}

mixin(grammar(scriptGrammar));
enum scriptGrammar = `
ExpectScript:

	# This handles reading in expect script files.
	# Lots to add to this, but will work for simple files

	Script      <- (EmptyLine / Command)+ :eoi
	Command     <- :Spacing (
					Comment
					/ Set
					/ Expect
					/ Spawn
					/ Send
			       ) :endOfLine

	Comment		<: :"#" Text

	Set			<- :"set" :Spacing (!eoi !endOfLine !Equals) SetName :Equals SetVal
	SetName		<- ~VarName
	SetVal		<- ( ~Variable / ~String ) (:Spacing* :'~' :Spacing? (~Variable / ~String))*

	Expect		<- :"expect" :Spacing ToExpect
	ToExpect	<- (~Variable / ~String) (:Spacing* :'~' :Spacing? (~Variable / ~String))*

	Spawn		<- :"spawn" :Spacing ToSpawn
	ToSpawn		<- (~Variable / ~String) (:Spacing* :'~' :Spacing? (~Variable / ~String))*

	Send		<- :"send" :Spacing ToSend
	ToSend		<- (~Variable / ~String) (:Spacing* :'~' :Spacing? (~Variable / ~String))*

	Variable    <- :"$(" VarName :")"
	VarName     <- (!eoi !endOfLine !')' !'(' !'$' !Equals .)+

	Text        <- (!eoi !endOfLine !'~' .)+
	DoubleQuoteText <- :doublequote (!eoi !endOfLine !doublequote .)+ :doublequote
	SingleQuoteText <- :"'" (!eoi !endOfLine !"'" .)+ :"'"
	String		<- (
					~DoubleQuoteText /
					~SingleQuoteText /
					~Text
				   )
	Concat		<- (:Spacing* :'~' :Spacing? (~Variable / ~String))
	EmptyLine   <: ('\n\r' / '\n')+
	Equals		<- '='
`;
}
else{}

