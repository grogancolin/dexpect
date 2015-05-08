module dexpect;

version(Posix):
import std.string;
import std.stdio;
import std.datetime;
import std.algorithm;
import std.process : environment;
import std.exception;

// link to external C function in util lib to fork a pseudo terminal
// pragma(lib, "util"); // pragma does not work for me at moment. TODO: FIND OUT WHY!
extern(C) static int forkpty(int* master, char* name, void* termp, void* winp);
extern(C) static char* ttyname(int fd);

/// The buffer size for reads from pty.
const int toRead = 1024;

/**
  * Class that encapsulates functionality to expect data on a pty session.
  * It's constructor sets up a pty and spawns the program on it.
  * Expect an output with expect() function
  *
  */
class Expect{
        /// The spawned pty this session interacts with
        private Pty pty;
        /// All data read from pty
        private string allData;
        /// The index in allData where the last succesfull expect was found
        private long indexLastExpect;
        /// Amount of time to wait before ending expect call.
        private Duration _timeout=5000.msecs;

        /// Constructs an Expect that runs cmd
        this(string cmd){
                this(cmd, []);
        }
        /// Constructs an Expect that runs cmd with args
        this(string cmd, string[] args){
                import std.path;

                string firstArg = constructPathToExe(cmd);
                if(args.length == 0 || args[0] != firstArg)
                        args = [firstArg] ~ args;

                this.pty = spawnProcessInPty(cmd, args);
        }

        /// Expects toExpect in output of spawn within default timeout
        public void expect(string toExpect){
                return expect(toExpect, this.timeout);
        }

        /// Expects toExpect in output of spawn within custom timeout
        public void expect(string toExpect, Duration timeout){
                auto startTime = Clock.currTime;
                while(Clock.currTime < startTime + timeout){
                        this.readNextChunk;
                        if(allData[indexLastExpect..$].canFind(toExpect)){
                                indexLastExpect = allData.lastIndexOf(toExpect);       
                                return;
                        }
                }
                throw new ExpectException(format("Timed out expecting %s",toExpect));
        }

        /// Sends a line to the pty. Ensures it ends with newline
        public void sendLine(string command){
                if(command[$-1]!='\n')
                        send(command ~ '\n');
                else
                        send(command);
        }

        /// Sends command to the pty
        public void send(string command){
                this.pty.sendToPty(command);
        }
        /// Reads the next toRead of data
        private void readNextChunk(){
                auto data = this.pty.readFromPty();
                if(data.length > 0)
                        this.allData ~= data.idup;
        }
        /// Reads all available data. Ends when subsequent reads dont increase length of allData
        public void readAllAvailable(){
                auto len = allData.length;
                auto tmp = len;
                while(true){ 
                        readNextChunk;
                        if(tmp == allData.length) break;
                        tmp = allData.length;
                }

        }

        /// Prints all the output to stdout
        public void printAllOutput(){
                readAllAvailable;
                writefln("%s", allData);
        }

        /// Sets the default timeout
        @property timeout(Duration t) { this._timeout = t; }
        /// Sets the timeout to t milliseconds
        @property timeout(long t) { this._timeout = t.msecs; }
        /// Returns the timeout
        @property auto timeout(){ return this._timeout; }
        /// Returns all data before the last succesfull expect
        @property string before(){ return this.allData[0..indexLastExpect]; }
        /// Reads and then returns all data after the last succesfull expect. WARNING: May block if spawn is constantly writing data
        @property string after(){ readAllAvailable; return this.allData[indexLastExpect..$]; }
}

/**
  * A data structure to hold information on a Pty session
  * Holds its fd and a utility property to get its name
  */
public struct Pty{
        int fd;
        @property string name(){ return ttyname(fd).fromStringz.idup; };
}

/**
  * Sets the Pty session to non-blocking mode
  */
void setNonBlocking(Pty pty){
                import core.sys.posix.unistd;
                import core.sys.posix.fcntl;
                int currFlags = fcntl(pty.fd, F_GETFL, 0) | O_NONBLOCK;
                fcntl(pty.fd, F_SETFL, currFlags);
}

/**
  * Spawns a process in a pty session
  * By convention the first arg in args should be == program
  */
public Pty spawnProcessInPty(string program, string[] args)
{
        import core.sys.posix.unistd;
        import core.sys.posix.fcntl;
        import core.thread;
        Pty master;
        int pid = forkpty(&(master).fd, null, null, null);
        assert(pid != -1, "Error forking pty");
        if(pid==0){ //child
                execl(program.toStringz, 
                                args.length > 0 ? args.join(" ").toStringz : null , null);

        }
        else{ // master
                int currFlags = fcntl(master.fd, F_GETFL, 0);
                currFlags |= O_NONBLOCK;
                fcntl(master.fd, F_SETFL, currFlags);
                Thread.sleep(100.msecs);
                return master;
        }
        return Pty(-1);
}

/**
  * Sends a string to a pty.
  */
void sendToPty(Pty pty, string data){
        import core.sys.posix.unistd;
        const(void)[] rawData = cast(const(void)[]) data;
        while(rawData.length){
                long sent = write(pty.fd, rawData.ptr, rawData.length);
                if(sent < 0)
                        throw new Exception(format("Error writing to %s", pty.name));
                rawData = rawData[sent..$];
        }
}

/**
  * Reads from a pty session
  * Returns the string that was read
  */
string readFromPty(Pty pty){
        import core.sys.posix.unistd;
        import std.conv : to;
        ubyte[toRead] buf;
        immutable long len = read(pty.fd, buf.ptr, toRead);
        if(len >= 0){
                return cast(string)(buf[0..len]);
        }
        return "";
}
/+ --------------- Utils --------------- +/
/**
  * Exceptions thrown during expecting data.
  */
class ExpectException : Exception {
        this(string message, string file = __FILE__, size_t line = __LINE__, Throwable next = null){
                super(message, file, line, next);
        }
}

/**
  * Searches all dirs on path for exe if required,
  * or simply calls it if it's a relative or absolute path
  */
string constructPathToExe(string exe){
        import std.path;
        import std.algorithm;
        import std.file : exists;
        // if it already has a / or . at the start, assume the exe is correct
        if(exe[0]=='/' || exe[0]=='.') return exe;
        auto matches = environment["PATH"].split(pathSeparator)
                .map!(path => path~"/"~exe)
                .filter!(path => path.exists);
        return matches.empty ? exe : matches.front;
}
