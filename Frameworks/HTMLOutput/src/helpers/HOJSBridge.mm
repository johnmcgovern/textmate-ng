#import "HOJSBridge.h"
#import "../HOEnvironment.h"
#import "add_to_buffer.h"
#import <OakFoundation/NSString Additions.h>
#import <OakAppKit/NSAlert Additions.h>
#import <oak/debug.h>
#import <document/OakDocument.h>
#import <document/OakDocumentController.h>
#import <text/utf8.h>
#import <ns/ns.h>
#import <io/exec.h>

/*
	This class backs the ‘TextMate’ object exposed to the JavaScript interpreter
	(defined in resources/HTMLOutput.js). The object has the following methods:

		system()                 See HOJSShellCommand below for information.
		log(msg)                 Adds a message to the system console.
		open(path, options)      Opens a file on disk as a document in the current application.
		                         options may be either a selection range string or a (line) number.

	in addition, these properties are exposed:

		busy       (boolean)     The busy spinner in the output window will be displayed when this is true.
		progress   (double, 0-1) Controls the value displayed in the determinate progress indicator.

	# Asynchronous Operation

	Example: obj = TextMate.system("/usr/bin/id -un", handler);

	Handler is called when the command is finished and given an object with the
	following properties:

		outputString:  The last output of the command, as placed on stdout.
		errorString:   The last output of the command, as placed on stderr.
		status:        The exit status of the command.

	Result is an object with following properties/methods:

		outputString:  The current string written to stdout by the command.
		errorString:   The current string written to stderr by the command.
		status:        The command’s exit status, as defined by the command.
		onreadoutput:  A function called whenever the command writes to stdout.
		onreaderror:   A function called whenever the command writes to stderr.
		cancel():      Cancels the execution of the command.
		write(string): Writes a string to stdin.
		close():       Closes stdin (EOF).

	The synchronous form — TextMate.system(cmd, null), which blocks the calling
	statement and returns {outputString, errorString, status} — is not served here.
	WKWebView has no synchronous JS↔native call in either direction; it needs the
	sync-XHR-against-a-scheme-handler shim described in
	ide/STREAM5_HOJSBRIDGE_PLAN.md. HTMLOutput.js throws a clear error meanwhile.
*/

@class HOJSBridge;

@interface HOJSShellCommand : NSObject
- (instancetype)initWithCommand:(NSString*)aCommand token:(NSNumber*)aToken environment:(std::map<std::string, std::string> const&)someEnvironment bridge:(HOJSBridge*)aBridge;
- (void)writeToInput:(NSString*)someData;
- (void)closeInput;
- (void)cancelCommand;
@end

@interface HOJSBridge ()
- (void)dispatchToken:(NSNumber*)aToken kind:(NSString*)aKind payload:(id)aPayload;
- (void)forgetToken:(NSNumber*)aToken;
@end

@implementation HOJSBridge
{
	std::map<std::string, std::string> environment;
	NSMutableDictionary<NSNumber*, HOJSShellCommand*>* _commands;
}

- (instancetype)init
{
	if(self = [super init])
		_commands = [NSMutableDictionary dictionary];
	return self;
}

- (std::map<std::string, std::string> const&)environment
{
	return environment;
}

- (void)setEnvironment:(const std::map<std::string, std::string>&)variables
{
	environment = variables;
}

- (void)setEnvironmentBox:(HOEnvironment*)environmentBox
{
	environment = environmentBox.cxxMap;
}

- (void)invalidate
{
	for(HOJSShellCommand* command in _commands.allValues)
		[command cancelCommand];
	[_commands removeAllObjects];
}

- (void)dealloc
{
	[self invalidate];
}

// ==========================
// = WKScriptMessageHandler =
// ==========================

- (void)userContentController:(WKUserContentController*)userContentController didReceiveScriptMessage:(WKScriptMessage*)message
{
	NSDictionary* body = [message.body isKindOfClass:[NSDictionary class]] ? message.body : nil;
	NSString* command  = body[@"command"];
	NSDictionary* payload = [body[@"payload"] isKindOfClass:[NSDictionary class]] ? body[@"payload"] : @{ };
	if(!command)
		return;

	if([command isEqualToString:@"log"])
	{
		if([payload[@"level"] isEqualToString:@"error"])
				os_log_error(OS_LOG_DEFAULT, "JavaScript: %{public}@ (%{public}@:%{public}@)", payload[@"message"], payload[@"filename"], payload[@"lineno"]);
		else	os_log(OS_LOG_DEFAULT, "JavaScript Log: %{public}@", payload[@"message"]);
	}
	else if([command isEqualToString:@"open"])
	{
		[self openFile:payload[@"path"] withOptions:payload[@"options"]];
	}
	else if([command isEqualToString:@"status"])
	{
		[_delegate setStatusText:payload[@"text"] ?: @""];
	}
	else if([command isEqualToString:@"busy"])
	{
		[_delegate setBusy:[payload[@"flag"] boolValue]];
	}
	else if([command isEqualToString:@"progress"])
	{
		[_delegate setProgress:[payload[@"value"] doubleValue]];
	}
	else if([command isEqualToString:@"system"])
	{
		NSNumber* token = payload[@"token"];
		NSString* cmd   = payload[@"cmd"];
		if(token && cmd)
			_commands[token] = [[HOJSShellCommand alloc] initWithCommand:cmd token:token environment:environment bridge:self];
	}
	else if([command isEqualToString:@"systemCtl"])
	{
		HOJSShellCommand* cmd = _commands[payload[@"token"]];
		NSString* op = payload[@"op"];
		if([op isEqualToString:@"cancel"])
				[cmd cancelCommand];
		else if([op isEqualToString:@"write"])
				[cmd writeToInput:payload[@"data"]];
		else if([op isEqualToString:@"close"])
				[cmd closeInput];
	}
}

- (void)openFile:(NSString*)path withOptions:(id)options
{
	if(!path)
		return;

	text::range_t range = text::range_t::undefined;
	if([options isKindOfClass:[NSNumber class]])
		range = text::pos_t([options intValue]-1, 0);
	else if([options isKindOfClass:[NSString class]])
		range = to_s(options);

	if(OakDocument* doc = [OakDocumentController.sharedInstance documentWithPath:path])
		[OakDocumentController.sharedInstance showDocument:doc andSelect:range inProject:nil bringToFront:YES];
}

// =====================
// = Pushing back to JS =
// =====================

- (void)dispatchToken:(NSNumber*)aToken kind:(NSString*)aKind payload:(id)aPayload
{
	// JSON rather than hand-rolled escaping: command output is arbitrary bytes and
	// lands straight inside a JavaScript expression.
	NSData* json = [NSJSONSerialization dataWithJSONObject:@[ aToken, aKind, aPayload ?: NSNull.null ] options:0 error:nullptr];
	if(!json)
		return;

	NSString* args = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
	NSString* js   = [NSString stringWithFormat:@"if(window.TextMate) TextMate._dispatch.apply(null, %@);", args];
	[self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)forgetToken:(NSNumber*)aToken
{
	if(aToken)
		[_commands removeObjectForKey:aToken];
}

// =======================
// = Synchronous variant =
// =======================

/*
	Runs a command to completion and hands back its full output. The caller is a
	synchronous XMLHttpRequest from the page, so the *web content process* is
	blocked while this runs — but the main thread is not, which is what lets the
	15-second warning appear at all.

	The legacy implementation had to spin a nested cf::run_loop_t on the main
	thread and put up the alert from inside it. Here the alert is an ordinary
	sheet-less modal on an idle main thread, so "Stop Command" reliably interrupts.
*/
- (void)runSyncCommand:(NSString*)aCommand completionHandler:(void(^)(NSString*, NSString*, int))aCompletionHandler
{
	__block BOOL done = NO;
	__block NSTimer* watchdog = nil;

	io::process_t process = io::spawn(std::vector<std::string>{ "/bin/sh", "-c", to_s(aCommand) }, environment);
	if(!process)
		return aCompletionHandler(@"", @"", -1);

	close(process.in); // no stdin for the synchronous form, matching the old behaviour

	auto finish = ^(NSString* out, NSString* err, int status){
		if(done)
			return;
		done = YES;
		[watchdog invalidate];
		watchdog = nil;
		aCompletionHandler(out, err, status);
	};

	pid_t const pid = process.pid;
	int const outFD = process.out, errFD = process.err;

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		auto slurp = [](int fd){
			std::string res;
			char buf[1024];
			while(ssize_t len = read(fd, buf, sizeof(buf)))
			{
				if(len < 0)
					break;
				res.insert(res.end(), buf, buf + len);
			}
			close(fd);
			return res;
		};

		// stderr on its own queue so a command that fills one pipe while we drain
		// the other cannot deadlock.
		__block std::string errStr;
		dispatch_semaphore_t errDone = dispatch_semaphore_create(0);
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			errStr = slurp(errFD);
			dispatch_semaphore_signal(errDone);
		});

		std::string outStr = slurp(outFD);
		dispatch_semaphore_wait(errDone, DISPATCH_TIME_FOREVER);

		int result = 0;
		if(waitpid(pid, &result, 0) != pid)
			perror("HOJSBridge: waitpid");
		int const status = WIFEXITED(result) ? WEXITSTATUS(result) : -1;

		dispatch_async(dispatch_get_main_queue(), ^{
			finish([NSString stringWithCxxString:outStr], [NSString stringWithCxxString:errStr], status);
		});
	});

	watchdog = [NSTimer scheduledTimerWithTimeInterval:15 repeats:NO block:^(NSTimer*){
		if(done)
			return;

		NSAlert* alert        = [[NSAlert alloc] init];
		alert.messageText     = @"JavaScript Warning";
		alert.informativeText = [NSString stringWithFormat:@"The command ‘%@’ has been running for 15 seconds. Would you like to stop it?\n\nTo avoid this warning, the bundle command should use the asynchronous version of TextMate.system().", aCommand];
		[alert addButtons:@"Stop Command", @"Cancel", nil];

		if([alert runModal] == NSAlertFirstButtonReturn && !done)
		{
			kill(pid, SIGINT);
			// Answer the page immediately: leaving the XHR outstanding would hang
			// it forever even though the process is gone.
			finish(@"", @"", -1);
		}
	}];
}
@end

@interface HOJSShellCommand ()
{
	io::process_t process;
	std::string output, error;
}
@property (nonatomic, weak) HOJSBridge* bridge;
@property (nonatomic) NSNumber* token;
@property (nonatomic) BOOL cancelled;
@property (nonatomic) int status;
@end

@implementation HOJSShellCommand
- (instancetype)initWithCommand:(NSString*)aCommand token:(NSNumber*)aToken environment:(std::map<std::string, std::string> const&)someEnvironment bridge:(HOJSBridge*)aBridge
{
	if(self = [super init])
	{
		_bridge = aBridge;
		_token  = aToken;

		if(process = io::spawn(std::vector<std::string>{ "/bin/sh", "-c", to_s(aCommand) }, someEnvironment))
		{
			auto group = dispatch_group_create();
			auto queue = dispatch_get_main_queue();

			[self exhaustFileDescriptor:process.out inQueue:queue group:group buffer:output isError:NO];
			[self exhaustFileDescriptor:process.err inQueue:queue group:group buffer:error isError:YES];

			dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				int result = 0;
				if(waitpid(self->process.pid, &result, 0) != self->process.pid)
					perror("HOJSShellCommand: waitpid");
				self->process.pid = -1;

				int const status = WIFEXITED(result) ? WEXITSTATUS(result) : -1;
				dispatch_sync(queue, ^{
					self->_status = status;
				});
			});

			dispatch_group_notify(group, dispatch_get_main_queue(), ^{
				close(self->process.out);
				close(self->process.err);

				// No nested cf::run_loop_t here — that existed only to block the
				// synchronous form, which WKWebView cannot support this way.
				if(!self.cancelled)
					[self.bridge dispatchToken:self.token kind:@"exit" payload:@(self.status)];
				[self.bridge forgetToken:self.token];
			});
		}
		else
		{
			// Report the failure to launch as an immediate non-zero exit so the
			// page's handler still runs.
			dispatch_async(dispatch_get_main_queue(), ^{
				[self.bridge dispatchToken:self.token kind:@"exit" payload:@(-1)];
				[self.bridge forgetToken:self.token];
			});
		}
	}
	return self;
}

@synthesize status = _status;

- (void)exhaustFileDescriptor:(int)fd inQueue:(dispatch_queue_t)queue group:(dispatch_group_t)group buffer:(std::string&)buf isError:(BOOL)isError
{
	std::string* buffer = &buf;
	dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		char tmp[1024];
		while(ssize_t len = read(fd, &tmp[0], sizeof(tmp)))
		{
			if(len < 0)
				break;

			char const* bytes = &tmp[0];
			dispatch_sync(queue, ^{
				// add_bytes_to_utf8_buffer only hands back whole UTF-8 sequences, so
				// a multi-byte character split across reads is never sent as a
				// half-formed string.
				auto range = add_bytes_to_utf8_buffer(*buffer, bytes, bytes + len, true);
				if(range.first != range.second && !self.cancelled)
					[self.bridge dispatchToken:self.token kind:(isError ? @"err" : @"out") payload:[NSString stringWithCxxString:std::string(range.first, range.second)]];
			});
		}
	});
}

- (void)cancelCommand
{
	self.cancelled = YES;
	[self closeInput];

	if(process)
		kill(process.pid, SIGINT);
}

- (void)writeToInput:(NSString*)someData
{
	if(process.in != -1 && someData)
	{
		char const* bytes = [someData UTF8String];
		write(process.in, bytes, strlen(bytes));
	}
}

- (void)closeInput
{
	if(process.in != -1)
	{
		close(process.in);
		process.in = -1;
	}
}

- (void)dealloc
{
	[self cancelCommand];
}
@end
