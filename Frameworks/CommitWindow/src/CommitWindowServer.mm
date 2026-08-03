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
+ (BOOL)replyToClientPortName:(NSString*)portName stdoutString:(NSString*)stdoutString returnCode:(int)returnCode continueFlag:(BOOL)continueFlag
{
	id proxy = [NSConnection rootProxyForConnectionWithRegisteredName:portName host:nil];
	if(!proxy)
		return NO;

	[proxy setProtocolForProxy:@protocol(OakCommitWindowClientProtocol)];
	if(stdoutString)
	{
		[proxy connectFromServerWithOptions:@{
			kOakCommitWindowStandardOutput: stdoutString,
			kOakCommitWindowReturnCode:     @(returnCode),
			kOakCommitWindowContinue:       @(continueFlag),
		}];
	}
	else
	{
		[proxy connectFromServerWithOptions:@{
			kOakCommitWindowReturnCode:     @(returnCode),
		}];
	}
	return YES;
}
@end

// ==========================
// = OakCommitWindowServer  =
// ==========================

@protocol OakProjectIdentifier
- (NSString*)identifier;
@end

@interface OakCommitWindowServer ()
@property (nonatomic) NSConnection* connection;
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
	{
		_connection = [NSConnection new];
		[_connection setRootObject:self];

		NSString* serviceName = [NSString stringWithFormat:@"%@.CommitWindow.%d", NSBundle.mainBundle.bundleIdentifier, getpid()];
		if([_connection registerName:serviceName] == NO)
			os_log_error(OS_LOG_DEFAULT, "Failed to setup connection ‘%@’", serviceName);
	}
	return self;
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
