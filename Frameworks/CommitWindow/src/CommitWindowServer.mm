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
#import <oak/oak.h>

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

	// Pre-existing, confirmed 2026-07-27 during the Phase 4 port: when the app has
	// no main window (not frontmost, or every window closed), projectWindow is nil
	// and the sheet is never presented — leaving CommitWindowTool blocked on a
	// reply that never comes, so the bundle's commit command hangs. The ObjC++
	// original behaved identically (`[nil beginSheet:…]` is a silent no-op); the
	// port preserves it rather than changing behavior mid-migration. Logged so the
	// failure is diagnosable instead of silent. Real fix (separate change): fall
	// back to a standalone window, or reply with a failure so the tool exits.
	if(!projectWindow)
		os_log_error(OS_LOG_DEFAULT, "CommitWindow: no main window to attach the commit sheet to; the client will not receive a reply");

	OakCommitWindow* commitWindow = [[OakCommitWindow alloc] initWithOptions:someOptions];
	[commitWindow beginSheetModalForWindow:projectWindow completionHandler:^(NSModalResponse returnCode){ }];
}
@end
