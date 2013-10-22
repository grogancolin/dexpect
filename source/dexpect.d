module dexpect;

/+
Module contains a D implementation of the expect tool.
A small how to:
auto s = spawn("/bin/bash");
s.expect("$");
s.sendLine("ls -l");
s.expect("$");
writefln("Before: %s\nAfter: %s", s.before, s.after);
+/
version(Posix){
    import std.string;
    import std.stdio;

    import std.process : environment;

    // link to external C function in util lib to fork a pseudo terminal
    //pragma(lib, "util"); // pragma does not work for me at moment. TODO: FIND OUT WHY!
    extern(C) static int forkpty(int* master, char* name, void* termp, void* winp);
    

    /++
     + Class to handle IO from a spawned pseudo terminal.
     + Use expect(string) and sendLine(string) to communicate with spawned process.
     + The properties before and after contain the data before and after the latest expect() call.
     +/
    public class Spawn{
        private string[string] _spawnedEnvironment;
        private string[string] _parentEnvironment;
        private int _timeout = 30; //30 second timeout by default
        private int _master;
        private string before, after;

        private this(){
            _parentEnvironment = environment.toAA();
        } // private constructor as not allowed create object. Use modules spawn() function.

        /**
          * starts the spawn process. Returns the file descriptor to the pseudo terminal.
          */
        private int startChild(string program, string[] args, string[string] environ=null){
            int master;
            // convert args array into space seperated string
            import std.array : join;
            string _args= args.join(" ");

            int pid = forkpty(&master, null, null, null); // two threads run the rest of this function. parent and child.

            if(pid == -1){ //something went wrong
                throw new Exception("openpty error");
            }

            if(pid == 0){ //child executes this
                if(environ is null){
                    foreach(key, val; _parentEnvironment)
                        environment[key] = val;
                }
                else 
                    foreach(key, val; environ)
                        environment[key] = val;
                _spawnedEnvironment = environment.toAA;

                import core.sys.posix.unistd;
                execl(program.toStringz, _args.toStringz, null); // child will execute the program and do nothing else until program ends.
            }
            else{ // parent runs this block.
                // Make and file io on master non blocking
                import core.sys.posix.unistd;
                import core.sys.posix.fcntl;
                int currFlags = fcntl(master, F_GETFL, 0);
                currFlags |= O_NONBLOCK;
                fcntl(master, F_SETFL, currFlags);
                _master = master;
                return master;
            }
            return -1; // should never get here.
        }

        public void expect(string toExpect, int timeout){
            import std.regex;
            import std.datetime;
            before ~= after;
            //timeout in seconds. 1 second  = 10000000 hnses
            // 1 nano second  = 1 000 000 000 seconds
            // 1 hn second = 1 000 000 000/100 = 10000000
            auto startTime = Clock.currTime();
            auto endTime = startTime + dur!("seconds")(timeout);
            writefln("Starttime: %s\nEndtime: %s", startTime, endTime);
            do{
                DataPacket data = readData(_master);
                if(data.exitCode == -1) 
                    continue;
                string strData = cast(string)data.data;
                writefln("strData is: %s", strData);
                auto befLength = this.before.length;
                this.before ~= strData;
                
                if(match(before, toExpect)){
                    // we found a match!
                    writefln("Found a match!");
                    import std.array : split, join;
                    before = before[0..befLength];
                    before ~= strData.split(toExpect)[0] ~= toExpect;
                    after = strData.split(toExpect)[1..$].join(toExpect);
                    writefln("Array: %s", strData.split(toExpect));
                    return;
                }
            } while(endTime > Clock.currTime());
            // if it gets to here, throw an exception
            throw new Exception(format("Error finding: \"%s\" in %s", toExpect, this.before));
        }
        public void expect(string toExpect){
            expect(toExpect, this._timeout);
        }

        /**
          * Sends a line to the spawned process with \n concatenated on the end.
          */
        public void sendLine(string line){
            line ~= "\n";
            sendData(_master, cast(const(void)[])line);
        }

        public @property string[string] parentEnvironment(){
            return _parentEnvironment;
        }
        public @property string[string] spawnedEnvironment(){
            return _spawnedEnvironment;
        }

        public @property int timeout(){
            return _timeout;
        }
        public @property void timeout(int time){
            this._timeout = time;
        }
        public @property string Before(){
            return this.before;
        }
        public @property string After(){
            return this.after;
        }
    } // end spawn

    /**
      * Sends data in the data[] over to spawned process.
      * :q

      */
    private void sendData(int fp, const(void)[] data){
        import core.sys.posix.unistd;
        while(data.length){
            long sent = write(fp, data.ptr, data.length);
            if(sent < 0)
                throw new Exception(format("Error writing to %s (name: %s)", fp, ttyname(fp)));
            data = data[sent .. $];
        }
    }

    /**
      * Data structure to hold each packet of returned data.
      */
    private struct DataPacket{
        public int exitCode;
        public ubyte[] data;
    }
    /**
      * Read data from file descriptor fd and send it back in DataPacket. Data is in ubyte[] format.
      */
    private DataPacket readData(int fd){
        const int toRead = 2048;
        DataPacket packet;
        ubyte[toRead] buf;
        import core.sys.posix.unistd;
        long len = read(fd, buf.ptr, toRead);
        if(len < 0){
            packet.exitCode = -1;
            return packet;
        }
        packet.data ~= buf[0..len];
        buf.clear;
        packet.exitCode = 0;
        return packet;
    }

    /**
      * Creates and starts a new Spawn object.
      * Handles correct calling syntax to underlying Spawn object.
      */
    public Spawn spawn(string progName, string[] args, string[string] environ){
         // first item in args should be = to prog name.
        if(args !is null){
            string[] tmp;
            tmp ~= progName;
            tmp ~= args;
            args = tmp;
        } else{
            args ~= progName;
        }
        Spawn _spawn = new Spawn();
        _spawn.startChild(progName, args, environ);
        return _spawn;
    }
    public Spawn spawn(string progName, string[] args){
        return spawn(progName, args, null);
    }
    public Spawn spawn(string progName){
        return spawn(progName, null, null);
    }
}
