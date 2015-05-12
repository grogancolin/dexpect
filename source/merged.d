﻿module merged;

import std.conv : to;
import std.string;
import core.thread : Thread, Sleep, Duration, msecs;
import std.datetime : Clock;
import std.algorithm : canFind;
import std.path : isAbsolute;
public class Expect2{
	/// All data read from pty
	private string allData;
	/// Amount of time to wait before ending expect call.
	private Duration _timeout=5000.msecs;
	/// The index in allData where the last succesful expect was found
	private size_t indexLastExpect;
	version(Posix){
		private Pty pty;
	}
	version(Windows){
		HANDLE inWritePipe;
		HANDLE outReadPipe;
		OVERLAPPED overlapped;
		ubyte[4096] overlappedBuffer;
	}
	/// Constructs an Expect that runs cmd
	this(string cmd){
		this(cmd, []);
	}
	/// Constructs an Expect that runs cmd with args
	/// On linux, this passes the args with cmd on front if required
	/// On windows, it passes the args as a single string seperated by spaces
	this(string cmd, string[] args){
		version(Posix){
			import std.path;
			string firstArg = constructPathToExe(cmd);
			if(args.length == 0 || args[0] != firstArg)
				args = [firstArg] ~ args;
			this.pty = spawnProcessInPty(cmd, args);
		}
		version(Windows){
			string fqp = cmd;
			if(!cmd.isAbsolute)
				fqp = cmd.constructPathToExe;
			auto pipes = startChild(fqp, ([fqp] ~ args).join(" "));
			this.inWritePipe = pipes.inwritepipe;
			this.outReadPipe = pipes.outreadpipe;
			overlapped.hEvent = overlappedBuffer.ptr;
			Thread.sleep(100.msecs); // need to give the pipes a moment to connect
		}
	}
	version(Windows){
		~this(){
			CloseHandle(this.inWritePipe);
			CloseHandle(this.outReadPipe);
		}
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
		version(Posix){
			this.pty.sendToPty(command);
		}
		version(Windows){
			import std.stdio;
			writefln("Sending %s", command);
			this.inWritePipe.writeData(command);
		}
	}
	/// Reads the next toRead of data
	public void readNextChunk(){
		version(Posix){
			auto data = this.pty.readFromPty();
			if(data.length > 0)
				this.allData ~= data.idup;
		}
		version(Windows){
			OVERLAPPED ov;
			ov.Offset = allData.length;
			if(ReadFileEx(this.outReadPipe, overlappedBuffer.ptr, overlappedBuffer.length, &ov, cast(void*)&readData) == 0){
				if(GetLastError == 997) throw new ExpectException("Pending io");
				else {}
			}
			allData ~= (cast(char*)overlappedBuffer).fromStringz;
			overlappedBuffer.destroy;
			Thread.sleep(100.msecs);
		}
	}
	/// Reads all available data. Ends when subsequent reads dont increase length of allData
	public void readAllAvailable(){
		auto len = allData.length;
		while(true){
			readNextChunk;
			if(len == allData.length) break;
			len = allData.length;
		}
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
	@property auto data(){ return allData; }
}

version(Posix){
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

}
version(Windows){

	import core.sys.windows.windows;

	/+  The below was stolen (and slightly modified) from Adam Ruppe's terminal emulator. 
		https://github.com/adamdruppe/terminal-emulator/blob/master/terminalemulator.d
		Thanks Adam!
	+/
	extern(Windows){
		/// may not be needed
		//BOOL PeekNamedPipe(HANDLE, LPVOID, DWORD, LPDWORD, LPDWORD, LPDWORD);
		//BOOL GetOverlappedResult(HANDLE,OVERLAPPED*,LPDWORD,BOOL);
		//BOOL PostMessageA(HWND hWnd,UINT Msg,WPARAM wParam,LPARAM lParam);
		
		/// Reads from an IO device (https://msdn.microsoft.com/en-us/library/windows/desktop/aa365468%28v=vs.85%29.aspx)
		BOOL ReadFileEx(HANDLE, LPVOID, DWORD, OVERLAPPED*, void*);
		
		BOOL PostThreadMessageA(DWORD, UINT, WPARAM, LPARAM);
		
		BOOL RegisterWaitForSingleObject( PHANDLE phNewWaitObject, HANDLE hObject, void* Callback, 
			PVOID Context, ULONG dwMilliseconds, ULONG dwFlags);
		
		BOOL SetHandleInformation(HANDLE, DWORD, DWORD);
		
		HANDLE CreateNamedPipeA( LPCTSTR lpName, DWORD dwOpenMode, DWORD dwPipeMode, DWORD nMaxInstances, 
			DWORD nOutBufferSize, DWORD nInBufferSize, DWORD nDefaultTimeOut, LPSECURITY_ATTRIBUTES lpSecurityAttributes);
		
		BOOL UnregisterWait(HANDLE);
		void SetLastError(DWORD);
		private void readData(DWORD errorCode, DWORD numberOfBytes, OVERLAPPED* overlapped){
			auto data = (cast(ubyte*) overlapped.hEvent)[0 .. numberOfBytes];
		}
		private void writeData(HANDLE h, string data){
			uint written;
			// convert data into a c string 
			auto cstr = cast(void*)data.toStringz;
			if(WriteFile(h, cstr, data.length, &written, null) == 0)
				throw new ExpectException("WriteFile " ~ to!string(GetLastError()));
		}
	}

	__gshared HANDLE waitHandle;
	__gshared bool childDead;
	
	void childCallback(void* tidp, bool) {
		auto tid = cast(DWORD) tidp;
		UnregisterWait(waitHandle);
		
		PostThreadMessageA(tid, WM_QUIT, 0, 0);
		childDead = true;
	}
	
	/// this is good. best to call it with plink.exe so it can talk to unix
	/// note that plink asks for the password out of band, so it won't actually work like that.
	/// thus specify the password on the command line or better yet, use a private key file
	/// e.g.
	/// startChild!something("plink.exe", "plink.exe user@server -i key.ppk \"/home/user/terminal-emulator/serverside\"");
	auto startChild(string program, string commandLine) {
		// thanks for a random person on stack overflow for this function
		static BOOL MyCreatePipeEx(PHANDLE lpReadPipe, PHANDLE lpWritePipe, LPSECURITY_ATTRIBUTES lpPipeAttributes,	
			DWORD nSize, DWORD dwReadMode, DWORD dwWriteMode)
		{
			HANDLE ReadPipeHandle, WritePipeHandle;
			DWORD dwError;
			CHAR[MAX_PATH] PipeNameBuffer;
			
			if (nSize == 0) {
				nSize = 4096;
			}
			
			static int PipeSerialNumber = 0;
			
			import core.stdc.string;
			import core.stdc.stdio;
			
			// could use format here, but C function will add \0 like windows wants
			// so may as well use it
			sprintf(PipeNameBuffer.ptr,
				"\\\\.\\Pipe\\DExpectPipe.%08x.%08x".ptr,
				GetCurrentProcessId(),
				PipeSerialNumber++
				);
			
			ReadPipeHandle = CreateNamedPipeA(
				PipeNameBuffer.ptr,
				1/*PIPE_ACCESS_INBOUND*/ | dwReadMode,
				0/*PIPE_TYPE_BYTE*/ | 0/*PIPE_WAIT*/,
				1,             // Number of pipes
				nSize,         // Out buffer size
				nSize,         // In buffer size
				120 * 1000,    // Timeout in ms
				lpPipeAttributes
				);
			
			if (! ReadPipeHandle) {
				return FALSE;
			}
			
			WritePipeHandle = CreateFileA(
				PipeNameBuffer.ptr,
				GENERIC_WRITE,
				0,                         // No sharing
				lpPipeAttributes,
				OPEN_EXISTING,
				FILE_ATTRIBUTE_NORMAL | dwWriteMode,
				null                       // Template file
				);
			
			if (INVALID_HANDLE_VALUE == WritePipeHandle) {
				dwError = GetLastError();
				CloseHandle( ReadPipeHandle );
				SetLastError(dwError);
				return FALSE;
			}
			
			*lpReadPipe = ReadPipeHandle;
			*lpWritePipe = WritePipeHandle;
			
			return( TRUE );
		}
			
		SECURITY_ATTRIBUTES saAttr;
		saAttr.nLength = SECURITY_ATTRIBUTES.sizeof;
		saAttr.bInheritHandle = true;
		saAttr.lpSecurityDescriptor = null;
		
		HANDLE inreadPipe;
		HANDLE inwritePipe;
		if(CreatePipe(&inreadPipe, &inwritePipe, &saAttr, 0) == 0)
			throw new Exception("CreatePipe");
		if(!SetHandleInformation(inwritePipe, 1/*HANDLE_FLAG_INHERIT*/, 0))
			throw new Exception("SetHandleInformation");
		HANDLE outreadPipe;
		HANDLE outwritePipe;
		if(MyCreatePipeEx(&outreadPipe, &outwritePipe, &saAttr, 0, FILE_FLAG_OVERLAPPED, 0) == 0)
			throw new Exception("CreatePipe");
		if(!SetHandleInformation(outreadPipe, 1/*HANDLE_FLAG_INHERIT*/, 0))
			throw new Exception("SetHandleInformation");
		
		STARTUPINFO startupInfo;
		startupInfo.cb = startupInfo.sizeof;
		
		startupInfo.dwFlags = STARTF_USESTDHANDLES;
		startupInfo.hStdInput = inreadPipe;
		startupInfo.hStdOutput = outwritePipe;
		startupInfo.hStdError = GetStdHandle(STD_ERROR_HANDLE);//outwritePipe;
		
		PROCESS_INFORMATION pi;
		
		if(commandLine.length > 255)
			throw new Exception("command line too long");
		char[256] cmdLine;
		cmdLine[0 .. commandLine.length] = commandLine[];
		cmdLine[commandLine.length] = 0;
			
		if(CreateProcessA(program is null ? null : toStringz(program), cmdLine.ptr, null, null, true, 0/*0x08000000 /* CREATE_NO_WINDOW */, null /* environment */, null, &startupInfo, &pi) == 0)
			throw new Exception("CreateProcess " ~ to!string(GetLastError()));
		
		if(RegisterWaitForSingleObject(&waitHandle, pi.hProcess, &childCallback, cast(void*) GetCurrentThreadId(), INFINITE, 4 /* WT_EXECUTEINWAITTHREAD */ | 8 /* WT_EXECUTEONLYONCE */) == 0)
			throw new Exception("RegisterWaitForSingleObject");
		
		struct Pipes { HANDLE inwritepipe, outreadpipe; }
		return Pipes(inwritePipe, outreadPipe);
		
	}
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
	import std.process : environment;

	// if it already has a / or . at the start, assume the exe is correct
	if(exe[0..1]==dirSeparator || exe[0..1]==".") return exe;
	auto matches = environment["PATH"].split(pathSeparator)
		.map!(path => path~dirSeparator~exe)
		.filter!(path => path.exists);
	return matches.empty ? exe : matches.front;
}
version(Posix){
	unittest{
		assert("sh".constructPathToExe == "/bin/sh");
		assert("./myexe".constructPathToExe == "./myexe");
		assert("/myexe".constructPathToExe == "/myexe");
	}
}
