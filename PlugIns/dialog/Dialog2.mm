//
//  Dialog2.mm
//  Dialog2
//
//  Created by Ciaran Walsh on 19/11/2007.
//

#import "Dialog2.h"
#import "TMDCommand.h"
#import "CLIProxy.h"
#import "DialogWire.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/stat.h>   // umask

@protocol TMPlugInController
- (CGFloat)version;
@end

@interface Dialog2 ()
@property (nonatomic) dispatch_source_t listener;
@end

@implementation Dialog2

- (id)initWithPlugInController:(id <TMPlugInController>)aController
{
	NSApp = NSApplication.sharedApplication;
	if(self = [self init])
	{
		[self startListening];

		if(NSString* path = [[NSBundle bundleForClass:[self class]] pathForResource:@"tm_dialog2" ofType:nil])
		{
			char* oldDialog = getenv("DIALOG");
			if(oldDialog == NULL || ![@(oldDialog) isEqualToString:path])
			{
				if(oldDialog)
					setenv("DIALOG_1", oldDialog, 1);
				setenv("DIALOG", [path UTF8String], 1);
			}

			// tm_dialog2 reads DIALOG_PORT_NAME to know where to connect. It used to
			// be a Distributed Objects registered name; it is the socket path now.
			setenv("DIALOG_PORT_NAME", DialogSocketPathForServerPID(getpid()).fileSystemRepresentation, 1);
		}
	}

	return self;
}

// A UNIX socket where a vended Distributed Objects root object used to be — the
// same move CommitWindow made, for the same reason. mode 0600, set by narrowing
// the umask across bind() rather than chmod afterwards, because the window
// between a permissive bind and a later chmod is a window in which another user
// can connect. Only this user can reach the socket, which is the whole point: a
// request names the files the command reads and writes, so who may send one is
// exactly the question the Distributed Objects name could not answer.
- (void)startListening
{
	[Dialog2 removeSocketsOfDepartedInstances];

	NSString* path = DialogSocketPathForServerPID(getpid());
	char const* cPath = path.fileSystemRepresentation;

	if(unlink(cPath) == -1 && errno != ENOENT)
	{
		NSLog(@"dialog: cannot remove stale socket %s: %s", cPath, strerror(errno)), NSBeep();
		return;
	}

	int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if(fd == -1)
	{
		NSLog(@"dialog: socket(): %s", strerror(errno)), NSBeep();
		return;
	}
	fcntl(fd, F_SETFD, FD_CLOEXEC);

	struct sockaddr_un addr = { 0, AF_UNIX };
	if(strlen(cPath) >= sizeof(addr.sun_path))
	{
		NSLog(@"dialog: socket path too long: %s", cPath);
		close(fd);
		return;
	}
	strcpy(addr.sun_path, cPath);
	addr.sun_len = SUN_LEN(&addr);

	mode_t const previous = umask(0177);   // 0600 whatever the user's umask is
	int const bound = bind(fd, (struct sockaddr*)&addr, sizeof(addr));
	umask(previous);

	if(bound == -1 || listen(fd, 16) == -1)
	{
		NSLog(@"dialog: cannot listen on %s: %s", cPath, strerror(errno)), NSBeep();
		close(fd);
		return;
	}

	_listener = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, dispatch_get_main_queue());
	dispatch_source_set_event_handler(_listener, ^{
		[self acceptOne:fd];
	});
	dispatch_source_set_cancel_handler(_listener, ^{
		close(fd);
	});
	dispatch_resume(_listener);
}

// Sockets from plug-in instances that are no longer running. The listener's path
// carries this process's pid, so it never collides with a live one — but nothing
// removes the file when a process is killed or crashes. Decide by asking the
// kernel, not by trusting the file: kill(pid, 0) fails with ESRCH only when no
// such process exists, which for a socket named after our own uid is the right
// question. Same sweep as CommitWindowServer.
+ (void)removeSocketsOfDepartedInstances
{
	NSString* directory = @"/tmp";
	NSString* prefix = [NSString stringWithFormat:@"textmate-dialog-%d-", getuid()];
	for(NSString* name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nullptr])
	{
		if(![name hasPrefix:prefix] || ![name hasSuffix:@".sock"])
			continue;

		NSString* pidPart = [[name substringFromIndex:prefix.length] stringByDeletingPathExtension];
		pid_t pid = (pid_t)pidPart.intValue;
		if(pid <= 0 || pid == getpid())
			continue;

		if(kill(pid, 0) == -1 && errno == ESRCH)
			unlink([directory stringByAppendingPathComponent:name].fileSystemRepresentation);
	}
}

- (void)acceptOne:(int)listenFD
{
	int fd = accept(listenFD, nullptr, nullptr);
	if(fd == -1)
		return;
	fcntl(fd, F_SETFD, FD_CLOEXEC);

	// Read on a background queue: a peer that connects and sends nothing must not
	// hold the main thread — which, with Distributed Objects, was exactly what any
	// local process could do. The reply is not on this socket; the command's
	// output goes back over the fifos the request names, so the fd is closed once
	// the request is read.
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		NSDictionary* request = DialogReadRequest(fd);
		close(fd);
		if(!request)
			return;
		dispatch_async(dispatch_get_main_queue(), ^{
			[self dispatchOptions:request];
		});
	});
}

- (void)dealloc
{
	if(_listener)
		dispatch_source_cancel(_listener);
	unlink(DialogSocketPathForServerPID(getpid()).fileSystemRepresentation);
}

// Deferred a turn, as the Distributed Objects path did with
// performSelector:afterDelay:0 — some commands (the tooltip) create a WKWebView,
// which must not run from inside the accept handler's stack.
- (void)dispatchOptions:(NSDictionary*)options
{
	[self performSelector:@selector(dispatch:) withObject:options afterDelay:0.0];
}

- (void)dispatch:(id)options
{
	CLIProxy* interface = [CLIProxy proxyWithOptions:options];

	NSString* command = [interface numberOfArguments] <= 1 ? @"help" : [interface argumentAtIndex:1];

	if(id target = [TMDCommand objectForCommand:command])
			[target performSelector:@selector(handleCommand:) withObject:interface];
	else	[interface writeStringToError:@"unknown command, try help.\n"];
}

@end
/*
echo '{ menuItems = ({title = 'foo';});}' | "$DIALOG" menu
*/
