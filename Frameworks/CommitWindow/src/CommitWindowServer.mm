// What remains ObjC++ after the Phase 4 Swift port (see CWSupport.h for why
// each piece is here). The window itself — controller, table, model, value
// transformer — lives in the Swift files alongside this one.
#import "CommitWindow.h"
#import "CWSupport.h"
#import "CommitWindow-Swift.h"
#import <OakFoundation/NSString Additions.h>
#import <OakTextView/OakDocumentView.h>
#import <bundles/bundles.h>
#import <io/io.h>
#import <regexp/format_string.h>
#import <ns/ns.h>
#import <oak/log.h>
#import <oak/oak.h>
#import "CWWire.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <signal.h>

// Read with:
//   /usr/bin/log stream --predicate 'subsystem == "com.j23software.TextMate-NG"'
// (`/usr/bin/log`, not `log` — zsh has a builtin of that name.)
static os_log_t const kLogCommitWindow = os_log_create(OAK_LOG_SUBSYSTEM, "commit-window");

// ======================
// = Boundary functions =
// ======================

NSString* CWEscapedShellPath (NSString* path)
{
	return [NSString stringWithCxxString:path::escape(to_s(path))];
}

NSString* CWDisplayNameForPath (NSString* path)
{
	return [NSString stringWithCxxString:path::display_name(to_s(path))];
}

NSString* CWExpandFormatString (NSString* format, NSDictionary<NSString*, NSString*>* variables)
{
	std::map<std::string, std::string> map;
	for(NSString* key in variables)
		map[to_s(key)] = to_s(variables[key]);
	return [NSString stringWithCxxString:format_string::expand(to_s(format), map)];
}

NSString* CWRunShellCommand (NSDictionary<NSString*, NSString*>* environment, NSString* command)
{
	std::map<std::string, std::string> env;
	for(NSString* key in environment)
		env[to_s(key)] = to_s(environment[key]);

	std::string const res = io::exec(env, "/bin/sh", "-c", [command UTF8String], NULL);
	return res == NULL_STR ? nil : [NSString stringWithCxxString:res];
}

NSString* CWCommitMessageGrammarForSCMName (NSString* scmName)
{
	std::string fileType = "text.plain";
	if(scmName)
	{
		std::string const fileGrammar = "text." + to_s(scmName) + "-commit";
		for(auto item : bundles::query(bundles::kFieldGrammarScope, fileGrammar, scope::wildcard, bundles::kItemTypeGrammar))
			fileType = item->value_for_field(bundles::kFieldGrammarScope);
	}
	return [NSString stringWithCxxString:fileType];
}

// ===================
// = CWInteropAdapter =
// ===================

@implementation CWInteropAdapter
- (std::map<std::string, std::string>)variables
{
	std::map<std::string, std::string> res;
	if(NSString* projectDirectory = self.projectDirectory)
		res["TM_PROJECT_DIRECTORY"] = to_s(projectDirectory);
	return res;
}

- (void)performBundleItem:(bundles::item_ptr)anItem
{
	if(anItem->kind() == bundles::kItemTypeTheme)
	{
		self.documentView.textView.themeUUID = [NSString stringWithCxxString:anItem->uuid()];
	}
	else
	{
		[self.windowController showWindow:self];
		[self.windowController.window makeFirstResponder:self.documentView.textView];
		[self.documentView.textView performBundleItem:anItem];
	}
}
@end

// ===================
// = CWClientChannel =
// ===================

@implementation CWClientChannel
// Waiting clients, by the token handed out when their request arrived.
//
// The token replaces the Distributed Objects port name the client used to vend,
// and it keeps the same key in the options dictionary — so the Swift window
// controller, which carries the value around and hands it back at the end, did
// not have to change at all.
//
// Main thread only: entries are added from the accept handler, which hops to
// main, and removed here, which the window controller calls on main.
static NSMutableDictionary<NSString*, NSNumber*>* CWWaitingClients ()
{
	static NSMutableDictionary* res = [NSMutableDictionary dictionary];
	return res;
}

void CWRegisterWaitingClient (NSString* token, int fd)
{
	CWWaitingClients()[token] = @(fd);
}

+ (BOOL)replyToClientPortName:(NSString*)portName stdoutString:(NSString*)stdoutString returnCode:(int)returnCode continueFlag:(BOOL)continueFlag
{
	NSNumber* boxed = portName ? CWWaitingClients()[portName] : nil;
	if(!boxed)
		return NO;   // the tool gave up, or was answered already
	[CWWaitingClients() removeObjectForKey:portName];

	int fd = boxed.intValue;
	NSMutableDictionary* reply = [NSMutableDictionary dictionary];
	if(stdoutString)
	{
		reply[kOakCommitWindowStandardOutput] = stdoutString;
		reply[kOakCommitWindowContinue]       = @(continueFlag);
	}
	reply[kOakCommitWindowReturnCode] = @(returnCode);

	BOOL const ok = CWWritePlist(fd, reply);
	close(fd);   // closing is what lets the tool stop reading and exit
	return ok;
}
@end

// ==========================
// = OakCommitWindowServer  =
// ==========================

@protocol OakProjectIdentifier
- (NSString*)identifier;
@end

@interface OakCommitWindowServer ()
@property (nonatomic) dispatch_source_t listener;
@end

@implementation OakCommitWindowServer
+ (instancetype)sharedInstance
{
	static OakCommitWindowServer* sharedInstance = [self new];
	return sharedInstance;
}

- (id)init
{
	if(self = [super init])
		[self startListening];
	return self;
}

// A UNIX socket where a vended Distributed Objects root object used to be.
//
// The old arrangement registered `<bundleid>.CommitWindow.<pid>` and handed
// `self` to anything that looked it up, which meant any process running as this
// user could send this object any selector. The name was the only barrier and it
// was a bundle identifier and a pid.
//
// A socket can say who may connect, which is the point: mode 0600, set with
// fchmod **before** bind, because the mode a bind leaves behind otherwise comes
// from the ambient umask — and a user running with a lax umask would get a
// socket their whole group could talk to without ever being told.
// Sockets from instances that are no longer running.
//
// The listener's own path carries this process's pid, so it never collides with
// a live one — but nothing removes the file when a process goes away. -dealloc
// does not help: the server is a shared instance that outlives everything and is
// never deallocated, and a crash or a SIGKILL would skip it regardless.
//
// So sweep on the way in, and decide by asking the kernel rather than by
// trusting the file: kill(pid, 0) succeeds only for a process this user can
// signal, which for a socket named after our own uid is the right question.
+ (void)removeSocketsOfDepartedInstances
{
	NSString* directory = @"/tmp";
	NSString* prefix = [NSString stringWithFormat:@"textmate-commit-%d-", getuid()];
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

- (void)startListening
{
	[OakCommitWindowServer removeSocketsOfDepartedInstances];

	NSString* path = CWSocketPathForApplicationPID(getpid());
	char const* cPath = path.fileSystemRepresentation;

	if(unlink(cPath) == -1 && errno != ENOENT)
	{
		os_log_error(kLogCommitWindow, "commit window: cannot remove stale socket %{public}s: %{public}s", cPath, strerror(errno));
		return;
	}

	int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if(fd == -1)
	{
		os_log_error(kLogCommitWindow, "commit window: socket(): %{public}s", strerror(errno));
		return;
	}
	fcntl(fd, F_SETFD, FD_CLOEXEC);

	struct sockaddr_un addr = { 0, AF_UNIX };
	if(strlen(cPath) >= sizeof(addr.sun_path))
	{
		os_log_error(kLogCommitWindow, "commit window: socket path too long: %{public}s", cPath);
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
		os_log_error(kLogCommitWindow, "commit window: cannot listen on %{public}s: %{public}s", cPath, strerror(errno));
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

	os_log(kLogCommitWindow, "commit window listening on %{public}s", cPath);
}

- (void)acceptOne:(int)listenFD
{
	int fd = accept(listenFD, nullptr, nullptr);
	if(fd == -1)
		return;
	fcntl(fd, F_SETFD, FD_CLOEXEC);

	// Read on a background queue: the request is small, but a peer that connects
	// and sends nothing must not hold the main thread — which, with Distributed
	// Objects, was exactly what any local process could do.
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		NSDictionary* request = CWReadPlist(fd);
		dispatch_async(dispatch_get_main_queue(), ^{
			if(!request)
			{
				close(fd);
				return;
			}

			// The token stands where the client's vended port name used to, so the
			// options dictionary keeps its shape and the Swift side is unchanged.
			NSString* token = NSUUID.UUID.UUIDString;
			CWRegisterWaitingClient(token, fd);

			NSMutableDictionary* options = [request mutableCopy];
			options[kOakCommitWindowClientPortName] = token;
			[self connectFromClientWithOptions:options];
		});
	});
}

- (void)dealloc
{
	if(_listener)
		dispatch_source_cancel(_listener);
	unlink(CWSocketPathForApplicationPID(getpid()).fileSystemRepresentation);
}

- (void)connectFromClientWithOptions:(NSDictionary*)someOptions
{
	NSWindow* projectWindow = [NSApp mainWindow];
	if(NSString* identifier = [someOptions valueForKeyPath:@"environment.TM_PROJECT_UUID"])
	{
		for(NSWindow* window in [NSApp orderedWindows])
		{
			if([window.delegate respondsToSelector:@selector(identifier)])
			{
				if([identifier isEqualToString:[id <OakProjectIdentifier>(window.delegate) identifier]])
				{
					projectWindow = window;
					break;
				}
			}
		}
	}

	// -[NSApplication mainWindow] is nil whenever the app is merely *inactive*,
	// not only when every window is closed — and inactive is the normal state
	// when a commit is started from a terminal. That nil then reached
	// `[nil beginSheet:…]`, a silent no-op, so nothing was presented and
	// CommitWindowTool blocked forever on a reply that could never come.
	// Reproduced 2026-07-29: TextMate inactive with two documents open, the tool
	// hung indefinitely and the window reported 0 sheets; the identical call with
	// TextMate active presented normally.
	//
	// So: prefer the key window, then any ordinary visible window, before giving
	// up. Giving up is no longer fatal either — the window presents standalone
	// (see -presentAttachedToWindow:) and the client is answered when it closes.
	if(!projectWindow)
		projectWindow = NSApp.keyWindow;

	if(!projectWindow)
	{
		for(NSWindow* window in NSApp.orderedWindows)
		{
			if(window.isVisible && window.canBecomeMainWindow)
			{
				projectWindow = window;
				break;
			}
		}
	}

	// One line per commit invocation, at default level so it persists: which
	// window the sheet attached to, and why. This is the state that decided
	// whether the client got a reply at all, so it is worth having in a log a
	// user can send you.
	os_log(kLogCommitWindow, "presenting commit window: mainWindow=%{public}s keyWindow=%{public}s orderedWindows=%lu chosen=%{public}s",
	       NSApp.mainWindow ? "yes" : "nil",
	       NSApp.keyWindow  ? "yes" : "nil",
	       (unsigned long)NSApp.orderedWindows.count,
	       projectWindow ? "sheet" : "standalone");

	OakCommitWindow* commitWindow = [[OakCommitWindow alloc] initWithOptions:someOptions];
	[commitWindow presentAttachedToWindow:projectWindow];
}
@end
