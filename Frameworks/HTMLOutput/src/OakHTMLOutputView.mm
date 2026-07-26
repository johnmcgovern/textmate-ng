#import "OakHTMLOutputView.h"
#import "HOFileHandleScheme.h"
#import "browser/HOStatusBar.h"
#import "helpers/HOJSBridge.h"
#import <OakFoundation/OakFoundation.h>
#import <OakFoundation/NSString Additions.h>
#import <OakAppKit/NSAlert Additions.h>
#import <oak/debug.h>

@interface HOStatusBar (BusyAndProgressProperties) <HOJSBridgeDelegate>
@end

static NSString* const kHOScriptMessageHandlerName = @"textmate";

// The bundle-facing TextMate object (resources/HTMLOutput.js). Copied into every
// bundle that links HTMLOutput by the seed's require-closure resource pass.
static WKUserScript* BridgeUserScript ()
{
	NSURL* url = [[NSBundle bundleForClass:[OakHTMLOutputView class]] URLForResource:@"HTMLOutput" withExtension:@"js"];
	if(!url)
	{
		os_log_error(OS_LOG_DEFAULT, "HTMLOutput: HTMLOutput.js missing from the bundle — the TextMate JavaScript API will be unavailable");
		return nil;
	}

	NSError* error;
	NSString* source = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];
	if(!source)
	{
		os_log_error(OS_LOG_DEFAULT, "HTMLOutput: cannot read HTMLOutput.js: %{public}@", error.localizedDescription);
		return nil;
	}

	return [[WKUserScript alloc] initWithSource:source injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
}

/*
	HOAutoScroll watched the WebFrameView’s document view for frame changes. There
	is no equivalent view to observe under WKWebView (the content lives in another
	process), so the behaviour moves into the page: stick to the bottom only while
	the reader is already at the bottom, re-evaluated on every content resize.

	This is a plain scrolling helper, not the TextMate JavaScript API — that stays
	absent until slice 2.
*/
static WKUserScript* AutoScrollUserScript ()
{
	static NSString* const source = @""
		"(function() {"
		"  var stick = true;"
		"  var atBottom = function() { return (window.innerHeight + window.scrollY) >= (document.body.scrollHeight - 4); };"
		"  window.addEventListener('scroll', function() { stick = atBottom(); }, { passive: true });"
		"  var start = function() {"
		"    if(!document.body) return;"
		"    new ResizeObserver(function() { if(stick) window.scrollTo(0, document.body.scrollHeight); }).observe(document.body);"
		"  };"
		"  if(document.body) start(); else document.addEventListener('DOMContentLoaded', start);"
		"})();";
	return [[WKUserScript alloc] initWithSource:source injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
}

@interface OakHTMLOutputView ()
@property (nonatomic, getter = isRunningCommand, readwrite) BOOL runningCommand;
@property (nonatomic) std::map<std::string, std::string> environment;
@property (nonatomic, getter = isVisible) BOOL visible;
// The request object OakCommand handed us. WKWebView copies requests, and
// NSURLProtocol properties do not survive the copy, so the original is kept here
// for the processName/command lookups that used to read them back off the frame.
@property (nonatomic) NSURLRequest* initialRequest;
@property (nonatomic) NSURL* jobURL;
@property (nonatomic) CGFloat pendingScrollY;
@property (nonatomic) HOJSBridge* jsBridge;
@end

@implementation OakHTMLOutputView
+ (NSSet*)keyPathsForValuesAffectingMainFrameTitle
{
	return [NSSet setWithObjects:@"webView.title", nil];
}

- (instancetype)initWithFrame:(NSRect)aRect
{
	if(self = [super initWithFrame:aRect])
	{
		_reusable = YES;
	}
	return self;
}

- (void)dealloc
{
	if(_jobURL)
		[HOFileHandleRegistry.sharedInstance discardJobForURL:_jobURL];
	[self teardownJavaScriptAPI];
}

// The legacy bridge was re-attached per navigation in didClearWindowObject:. A WK
// user script and message handler are per-content-controller instead, so they are
// installed for the life of a load and torn down before the next one.
- (void)teardownJavaScriptAPI
{
	[(HOFileHandleSchemeHandler*)[self.webView.configuration urlSchemeHandlerForURLScheme:kHOFileHandleURLScheme] setSyncRunner:nil];

	[_jsBridge invalidate];
	_jsBridge = nil;

	WKUserContentController* contentController = self.webView.configuration.userContentController;
	// -removeScriptMessageHandlerForName: is a no-op when nothing is registered,
	// but -addScriptMessageHandler:name: *raises* on a duplicate name, so the
	// remove has to happen before every add.
	[contentController removeScriptMessageHandlerForName:kHOScriptMessageHandlerName];
}

- (void)installJavaScriptAPI
{
	WKUserContentController* contentController = self.webView.configuration.userContentController;

	WKUserScript* script = BridgeUserScript();
	if(!script)
		return;

	_jsBridge          = [HOJSBridge new];
	_jsBridge.delegate = self.statusBar;
	_jsBridge.webView  = self.webView;
	[_jsBridge setEnvironment:_environment];

	[contentController addScriptMessageHandler:_jsBridge name:kHOScriptMessageHandlerName];
	[contentController addUserScript:script];

	// The synchronous form is answered by the scheme handler rather than the
	// message handler, so it needs its own route back to the bridge.
	[(HOFileHandleSchemeHandler*)[self.webView.configuration urlSchemeHandlerForURLScheme:kHOFileHandleURLScheme] setSyncRunner:_jsBridge];
}

- (void)loadRequest:(NSURLRequest*)aRequest environment:(std::map<std::string, std::string> const&)anEnvironment autoScrolls:(BOOL)flag
{
	[self teardownJavaScriptAPI];

	WKUserContentController* contentController = self.webView.configuration.userContentController;
	[contentController removeAllUserScripts];
	if(flag)
		[contentController addUserScript:AutoScrollUserScript()];

	self.environment = anEnvironment; // the bridge copies this, so set it first
	if(!self.disableJavaScriptAPI)
		[self installJavaScriptAPI];

	// Hand the streaming file handle to the scheme handler. We can still read the
	// NSURLProtocol properties here because this is the original request object.
	if(_jobURL)
		[HOFileHandleRegistry.sharedInstance discardJobForURL:_jobURL];
	_jobURL = nil;

	if(NSFileHandle* fileHandle = [NSURLProtocol propertyForKey:@"fileHandle" inRequest:aRequest])
	{
		_jobURL = aRequest.URL;
		[HOFileHandleRegistry.sharedInstance registerJobForURL:_jobURL fileHandle:fileHandle processIdentifier:[[NSURLProtocol propertyForKey:@"processIdentifier" inRequest:aRequest] intValue]];
	}

	self.initialRequest    = aRequest;
	self.commandIdentifier = [NSURLProtocol propertyForKey:@"commandIdentifier" inRequest:aRequest];
	self.runningCommand    = self.commandIdentifier != nil;

	[self.webView loadRequest:aRequest];
}

- (void)stopLoadingWithUserInteraction:(BOOL)askUserFlag completionHandler:(void(^)(BOOL didStop))handler
{
	NSURLRequest* request = self.initialRequest;
	if(id command = request ? [NSURLProtocol propertyForKey:@"command" inRequest:request] : nil)
	{
		NSAlert* alert = askUserFlag ? [NSAlert tmAlertWithMessageText:[NSString stringWithFormat:@"Stop “%@”?", [NSURLProtocol propertyForKey:@"processName" inRequest:request]] informativeText:@"The job that the task is performing will not be completed." buttons:@"Stop", @"Cancel", nil] : nil;

		__weak __block id token = [NSNotificationCenter.defaultCenter addObserverForName:@"OakCommandDidTerminateNotification" object:command queue:nil usingBlock:^(NSNotification* notification){
			if(alert)
				[self.window endSheet:alert.window returnCode:NSAlertFirstButtonReturn];
			handler(YES);
			[NSNotificationCenter.defaultCenter removeObserver:token];
		}];

		if(alert)
		{
			[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode){
				if(returnCode == NSAlertFirstButtonReturn) /* "Stop" */
				{
					[self.webView stopLoading];
				}
				else
				{
					handler(NO);
					[NSNotificationCenter.defaultCenter removeObserver:token];
				}
			}];
		}
		else
		{
			[self.webView stopLoading];
		}
	}
	else
	{
		handler(YES);
	}
}

- (void)setContent:(NSString*)someHTML
{
	// The scroll offset used to be read straight off the document view. Reading it
	// out of the page is asynchronous, so the load moves into the completion
	// handler to keep save-then-replace ordering intact.
	[self.webView evaluateJavaScript:@"window.scrollY" completionHandler:^(id result, NSError* error){
		self.pendingScrollY = [result respondsToSelector:@selector(doubleValue)] ? [result doubleValue] : 0;
		[self.webView loadHTMLString:someHTML baseURL:[NSURL fileURLWithPath:NSHomeDirectory()]];
	}];
}

- (NSString*)mainFrameTitle
{
	if(OakIsEmptyString(self.webView.title))
	{
		if(NSString* processName = [NSURLProtocol propertyForKey:@"processName" inRequest:self.initialRequest])
			return processName;
		return @"";
	}
	return self.webView.title;
}

- (void)viewDidMoveToWindow
{
	[NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowWillCloseNotification object:nil];
	if(self.window)
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowWillClose:) name:NSWindowWillCloseNotification object:self.window];
	self.visible = self.window ? YES : NO;
}

- (void)windowWillClose:(NSNotification*)aNotification
{
	self.visible = NO;
}

// ========================
// = Navigation  Delegate =
// ========================

- (void)webView:(WKWebView*)webView didStartProvisionalNavigation:(WKNavigation*)navigation
{
	self.statusBar.busy = YES;
	[self setUpdatesProgress:!self.isRunningCommand];
}

- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation*)navigation
{
	self.runningCommand = NO;

	// This happens when we redirect to a PDF file
	if(self.window.firstResponder == self.window)
	{
		NSRect rect = webView.frame;
		for(NSView* view = [webView hitTest:NSMakePoint(NSMidX(rect), NSMidY(rect))]; view; view = [view superview])
		{
			if([view acceptsFirstResponder])
			{
				[self.window makeFirstResponder:view];
				break;
			}
		}
	}

	if(self.pendingScrollY > 0)
	{
		[webView evaluateJavaScript:[NSString stringWithFormat:@"window.scrollTo(0, %.0f);", self.pendingScrollY] completionHandler:nil];
		self.pendingScrollY = 0;
	}

	[super webView:webView didFinishNavigation:navigation];
}

- (void)webView:(WKWebView*)webView didFailProvisionalNavigation:(WKNavigation*)navigation withError:(NSError*)error
{
	self.runningCommand = NO;
	[super webView:webView didFailProvisionalNavigation:navigation withError:error];
}

- (void)webView:(WKWebView*)webView didFailNavigation:(WKNavigation*)navigation withError:(NSError*)error
{
	self.runningCommand = NO;
	[super webView:webView didFailNavigation:navigation withError:error];
}

// ==========================================
// = Navigation policy : Intercept txmt:// =
// ==========================================

- (void)webView:(WKWebView*)webView decidePolicyForNavigationAction:(WKNavigationAction*)navigationAction decisionHandler:(void(^)(WKNavigationActionPolicy))decisionHandler
{
	NSURL* url = navigationAction.request.URL;
	if([url.scheme isEqualToString:@"txmt"])
	{
		decisionHandler(WKNavigationActionPolicyCancel);

		auto projectUUID = _environment.find("TM_PROJECT_UUID");
		if(projectUUID != _environment.end())
			url = [NSURL URLWithString:[[url absoluteString] stringByAppendingFormat:@"&project=%@", [NSString stringWithCxxString:projectUUID->second]]];
		[NSApp sendAction:@selector(handleTxMtURL:) to:nil from:url];
		return;
	}

	[super webView:webView decidePolicyForNavigationAction:navigationAction decisionHandler:decisionHandler];
}

// ====================
// = Printing Support =
// ====================

- (IBAction)printDocument:(id)sender
{
	// -[WKWebView printOperationWithPrintInfo:] takes the print info up front,
	// where the legacy path mutated it on an already-created operation.
	NSPrintInfo* info = [NSPrintInfo.sharedPrintInfo copy];

	NSRect display = NSIntersectionRect(info.imageablePageBounds, (NSRect){ NSZeroPoint, info.paperSize });
	info.leftMargin   = NSMinX(display);
	info.rightMargin  = info.paperSize.width - NSMaxX(display);
	info.topMargin    = info.paperSize.height - NSMaxY(display);
	info.bottomMargin = NSMinY(display);

	NSPrintOperation* printer = [self.webView printOperationWithPrintInfo:info];
	[[printer printPanel] setOptions:[[printer printPanel] options] | NSPrintPanelShowsPaperSize | NSPrintPanelShowsOrientation];
	[printer runOperationModalForWindow:self.window delegate:nil didRunSelector:NULL contextInfo:nil];
}
@end
