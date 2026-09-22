#include <CommitWindow/CommitWindow.h>
#include <CommitWindow/CWWire.h>
#include <oak/oak.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static double const AppVersion = 1.2;

// Send the request, wait for the reply, exit with the code it carries.
//
// **This used to vend an object of its own.** The tool registered
// `com.j23software.commit-window-client.<pid>` with Distributed Objects so the
// application had somewhere to send the answer, then spun a run loop until that
// answer arrived. Two vended objects, two names any local process could look up
// and message, for what is one request and one reply.
//
// Now the reply comes back on the connection the request went out on, so there
// is nothing to vend, no name to guess, no run loop, and no window in which
// something else can connect. See CWWire.h.
int main (int argc, char* argv[])
{
	if(argc == 2 && (strcmp(argv[1], "-v") == 0 || strcmp(argv[1], "--version") == 0))
	{
		fprintf(stderr, "%1$s %2$.1f (" __DATE__ ")\n", getprogname(), AppVersion);
		return EX_OK;
	}

	@autoreleasepool {
		// TM_PID is the application's, put into every command's environment by the
		// application itself — the same value the Distributed Objects name was
		// built from.
		NSString* pidString = NSProcessInfo.processInfo.environment[@"TM_PID"];
		if(!pidString.length)
		{
			fprintf(stderr, "%s: TM_PID is not set — this is meant to be run from a TextMate command\n", getprogname());
			return EX_USAGE;
		}

		NSString* path = CWSocketPathForApplicationPID((pid_t)pidString.intValue);
		char const* cPath = path.fileSystemRepresentation;

		int fd = socket(AF_UNIX, SOCK_STREAM, 0);
		if(fd == -1)
		{
			fprintf(stderr, "%s: socket(): %s\n", getprogname(), strerror(errno));
			return EX_UNAVAILABLE;
		}

		struct sockaddr_un addr = { 0, AF_UNIX };
		if(strlen(cPath) >= sizeof(addr.sun_path))
		{
			fprintf(stderr, "%s: socket path too long: %s\n", getprogname(), cPath);
			close(fd);
			return EX_UNAVAILABLE;
		}
		strcpy(addr.sun_path, cPath);
		addr.sun_len = SUN_LEN(&addr);

		if(connect(fd, (struct sockaddr*)&addr, sizeof(addr)) == -1)
		{
			fprintf(stderr, "%s: failed connecting to ‘%s’: %s\n", getprogname(), cPath, strerror(errno));
			close(fd);
			return EX_UNAVAILABLE;
		}

		NSMutableArray* arguments = [NSMutableArray array];
		for(int i = 0; i < argc; ++i)
			[arguments addObject:@(argv[i])];

		if(!CWWritePlist(fd, @{
			kOakCommitWindowArguments:   arguments,
			kOakCommitWindowEnvironment: NSProcessInfo.processInfo.environment,
		}))
		{
			fprintf(stderr, "%s: failed sending request\n", getprogname());
			close(fd);
			return EX_UNAVAILABLE;
		}

		// Blocks until the window is done with. A nil reply means the application
		// closed the connection without answering — it quit, or the window could
		// not be presented — and the old code hung forever in that case rather
		// than saying so.
		NSDictionary* reply = CWReadPlist(fd);
		close(fd);

		if(!reply)
		{
			fprintf(stderr, "%s: no reply from TextMate\n", getprogname());
			return EX_UNAVAILABLE;
		}

		if(NSString* err = reply[kOakCommitWindowStandardError])
			fprintf(stderr, "%s", err.UTF8String);

		if(NSString* out = reply[kOakCommitWindowStandardOutput])
		{
			fprintf(stdout, "%s", out.UTF8String);
			if([reply[kOakCommitWindowContinue] boolValue])
				fprintf(stdout, "TM_SCM_COMMIT_CONTINUE=1\n");
		}

		return [reply[kOakCommitWindowReturnCode] intValue];
	}
}
