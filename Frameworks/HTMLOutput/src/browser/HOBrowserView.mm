#import "HOBrowserView.h"
#import "HOWebViewDelegateHelper.h"
#import "HOStatusBar.h"
#import "../HOFileHandleScheme.h"
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <io/path.h>

static void* kHOBrowserViewProgressContext = &kHOBrowserViewProgressContext;

static NSString* const kUserDefaultsDefaultURLProtocolKey = @"defaultURLProtocol";

static BOOL IsProtocolRelativeURL (NSURL* url)
{
	if([url.scheme hasPrefix:@"x-txmt"] && ![url.host isEqualToString:@"job"])
		return YES;

	if([url.scheme isEqualToString:@"file"] && url.host)
	{
		// If host has a dot and does not exist on disk then treat as protocol-relative URL
		if([url.host containsString:@"."] && ![NSFileManager.defaultManager fileExistsAtPath:[@"/" stringByAppendingPathComponent:url.host]])
			return YES;
	}

	return NO;
}

/*
	Ported from the WebResourceLoadDelegate’s willSendRequest:, which WKWebView has
	no equivalent for. Returns a replacement URL, or nil to load as-is.

	Caveat carried over from the port: the legacy delegate saw *every* resource
	load, so these rewrites also applied to images and stylesheets. A navigation
	policy only sees navigations, so sub-resources are no longer rewritten.
*/
static NSURL* RewrittenURL (NSURL* url)
{
	if([url.scheme isEqualToString:@"tm-file"])
	{
		NSString* fragment = url.fragment;
		url = [NSURL URLWithString:[NSString stringWithFormat:@"file://localhost%@%s%@", [url.path stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet], fragment ? "#" : "", fragment ?: @""]];
	}

	if(IsProtocolRelativeURL(url))
	{
		NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:YES];
		components.scheme = [NSUserDefaults.standardUserDefaults stringForKey:kUserDefaultsDefaultURLProtocolKey];
		url = components.URL;
	}

	if(url.isFileURL)
	{
		NSURL* redirectURL = [NSURL URLWithString:[NSString stringWithFormat:@"file://localhost%@?path=%@&error=1", [[[NSBundle bundleForClass:[HOBrowserView class]] pathForResource:@"error_not_found" ofType:@"html"] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet], [url.path stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]]];
		char const* path = url.fileSystemRepresentation;

		struct stat buf;
		if(path && stat(path, &buf) == 0)
		{
			if(S_ISREG(buf.st_mode) || S_ISLNK(buf.st_mode))
			{
				redirectURL = nil;
			}
			else if(S_ISDIR(buf.st_mode))
			{
				if(path::exists(path::join(path, "index.html")))
				{
					NSString* urlString = [[NSURL URLWithString:@"index.html" relativeToURL:url] absoluteString];
					if(NSString* query = url.query)
						urlString = [urlString stringByAppendingFormat:@"?%@", query];
					if(NSString* fragment = url.fragment)
						urlString = [urlString stringByAppendingFormat:@"#%@", fragment];
					redirectURL = [NSURL URLWithString:urlString];
				}
			}
		}

		if(redirectURL)
			url = redirectURL;
	}

	return url;
}

// Schemes the web view can load itself. Spelled out rather than asking
// +[NSURLConnection canHandleRequest:] as the legacy path did: the streaming job
// scheme is served by a WKURLSchemeHandler now, not a registered NSURLProtocol,
// so NSURLConnection no longer knows about it.
static BOOL IsLoadableScheme (NSURL* url)
{
	static NSSet* const schemes = [NSSet setWithArray:@[ @"http", @"https", @"file", @"data", @"about", @"blob", kHOFileHandleURLScheme ]];
	return [schemes containsObject:url.scheme.lowercaseString];
}

static NSString* EscapeHTML (NSString* str)
{
	return [[[str stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"] stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"] stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
}

/*
	The load-error page used to offer the failing URL as a link that shelled out
	through TextMate.system(). That API is not wired up under WKWebView yet (it
	returns with the JavaScript bridge, Stream 5 slice 3), so the URL is shown as
	plain text for now rather than as a link that would silently do nothing.
*/
static void ShowLoadErrorForURL (WKWebView* webView, NSURL* url, NSError* error)
{
	NSString* errorMsg = [NSString stringWithFormat:@"<title>Load Error</title><h1>Load Error</h1><p>WebKit reported <em>%@</em> while loading <tt>%@</tt>.</p>", EscapeHTML(error.localizedDescription), EscapeHTML(url.absoluteString)];
	[webView loadHTMLString:errorMsg baseURL:[NSURL fileURLWithPath:NSTemporaryDirectory()]];
}

@interface HOBrowserView ()
@property (nonatomic, readwrite) WKWebView* webView;
@property (nonatomic, readwrite) HOStatusBar* statusBar;
@property (nonatomic, readwrite) BOOL needsNewWebView;
@property (nonatomic) HOWebViewDelegateHelper* webViewDelegateHelper;
@property (nonatomic) BOOL observingProgress;
@end

@implementation HOBrowserView
+ (WKWebViewConfiguration*)defaultConfiguration
{
	WKWebViewConfiguration* config = [[WKWebViewConfiguration alloc] init];
	// One handler, two schemes: the job stream plus tm-file sub-resources.
	HOFileHandleSchemeHandler* handler = [HOFileHandleSchemeHandler new];
	[config setURLSchemeHandler:handler forURLScheme:kHOFileHandleURLScheme];
	[config setURLSchemeHandler:handler forURLScheme:kHOTMFileURLScheme];
	return config;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	return [self initWithFrame:frame configuration:[HOBrowserView defaultConfiguration]];
}

- (instancetype)initWithFrame:(NSRect)frame configuration:(WKWebViewConfiguration*)configuration
{
	if(self = [super initWithFrame:frame])
	{
		_webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];

		// WKWebView draws its own two-finger back/forward swipe, including the
		// page-peek animation the old trackSwipeEventWithOptions: handler left as
		// a TODO, so the manual scrollWheel: tracking is gone.
		_webView.allowsBackForwardNavigationGestures = YES;

		_statusBar = [[HOStatusBar alloc] initWithFrame:NSZeroRect];
		_statusBar.delegate = _webView; // WKWebView has goBack:/goForward: actions

		_webViewDelegateHelper          = [HOWebViewDelegateHelper new];
		_webViewDelegateHelper.delegate = _statusBar;
		_webView.UIDelegate             = _webViewDelegateHelper;
		_webView.navigationDelegate     = self;

		NSDictionary* views = @{
			@"webView":   _webView,
			@"statusBar": _statusBar
		};

		OakAddAutoLayoutViewsToSuperview([views allValues], self);

		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[webView(>=10)]|"            options:0                                                      metrics:nil views:views]];
		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[webView(>=10)][statusBar]|" options:NSLayoutFormatAlignAllLeft|NSLayoutFormatAlignAllRight metrics:nil views:views]];
	}
	return self;
}

- (void)dealloc
{
	[self setUpdatesProgress:NO];
	_webView.navigationDelegate = nil;
	_webView.UIDelegate         = nil;
	[_webView stopLoading];
}

// WebViewProgress* notifications do not exist for WKWebView; estimatedProgress is
// KVO-compliant instead. Keeping the same on/off entry point the callers already use.
- (void)setUpdatesProgress:(BOOL)flag
{
	if(flag == _observingProgress)
		return;

	if(flag)
			[_webView addObserver:self forKeyPath:@"estimatedProgress" options:0 context:kHOBrowserViewProgressContext];
	else	[_webView removeObserver:self forKeyPath:@"estimatedProgress" context:kHOBrowserViewProgressContext];

	_observingProgress = flag;
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
	if(context == kHOBrowserViewProgressContext)
			_statusBar.progress = _webView.estimatedProgress;
	else	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

// ==============
// = Key Events =
// ==============

/*
Since the webView is typically the first responder, the path for key events is as follows:

For keyDown:
	webView
	HOBrowserView
	OakHTMLOutputView
	NSWindow

For performKeyEquivalent:
	NSWindow
	OakHTMLOutputView
	HOBrowserView
	webView

A webView default implementation passes all key events, including potential key equivalents (except ESC),
to the webpage so that it may have a chance to respond. Unfortunately, we cannot know if these events are
handled so the events are still forwarded down their respective chains as shown above. So to avoid the
NSBeep when hitting the end of the responder chain, we let HOBrowserView swallow all key events. This is
safe since performKeyEquivalent: is called first, which leads to another problem: we can pass
the key event back to the webView (minus the modifier). Therefore, we also terminate the above chain for
performKeyEquivalent: by overriding the method here and returning just NO. Note: that if none of the views
in the hierachy returns YES, the key (equivalent) event is then passed to the menus.
*/

- (BOOL)performKeyEquivalent
{
	return NO;
}

- (void)keyDown:(NSEvent*)anEvent
{

}

// ========================
// = Navigation  Delegate =
// ========================

- (void)webView:(WKWebView*)webView didStartProvisionalNavigation:(WKNavigation*)navigation
{
	_statusBar.busy = YES;
	[self setUpdatesProgress:YES];
}

- (void)webView:(WKWebView*)webView decidePolicyForNavigationAction:(WKNavigationAction*)navigationAction decisionHandler:(void(^)(WKNavigationActionPolicy))decisionHandler
{
	NSURL* const requested = navigationAction.request.URL;
	NSURL* url = requested;

	// Undo the sub-resource rewrite for navigations: the stream turned file:// into
	// the job scheme so stylesheets and images would load same-origin, but a
	// *clicked* file:// link should still go through the normal resolution below
	// (directory -> index.html, error_not_found, and so on).
	if([url.scheme isEqualToString:kHOFileHandleURLScheme] && [url.path hasPrefix:kHOLocalFilePathPrefix])
	{
		NSString* path = [url.path substringFromIndex:kHOLocalFilePathPrefix.length];
		if(NSURL* fileURL = path.length ? [NSURL fileURLWithPath:path] : nil)
			url = fileURL;
	}

	if(NSURL* rewritten = RewrittenURL(url))
		url = rewritten;

	// WKWebView cannot rewrite a navigation in flight, so any change to the URL —
	// whether from the un-rewrite above or from RewrittenURL — is a cancel plus a
	// fresh load. Compared against what was *requested*, not the working copy.
	if(![url isEqual:requested])
	{
		decisionHandler(WKNavigationActionPolicyCancel);
		[webView loadRequest:[NSURLRequest requestWithURL:url]];
		return;
	}

	if(IsLoadableScheme(url))
	{
		decisionHandler(WKNavigationActionPolicyAllow);
	}
	else
	{
		decisionHandler(WKNavigationActionPolicyCancel);
		[NSWorkspace.sharedWorkspace openURL:url];
	}
}

- (void)webView:(WKWebView*)webView didFailProvisionalNavigation:(WKNavigation*)navigation withError:(NSError*)error
{
	ShowLoadErrorForURL(webView, webView.URL, error);
	[self webView:webView didFinishNavigation:navigation];
}

- (void)webView:(WKWebView*)webView didFailNavigation:(WKNavigation*)navigation withError:(NSError*)error
{
	ShowLoadErrorForURL(webView, webView.URL, error);
	[self webView:webView didFinishNavigation:navigation];
}

- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation*)navigation
{
	_statusBar.canGoBack    = _webView.canGoBack;
	_statusBar.canGoForward = _webView.canGoForward;
	_statusBar.busy         = NO;
	_statusBar.progress     = 0;
}

/*
	Replaces the WebKit-bug-121232 workaround the legacy path carried (a WebView
	could not be reused after window.close()). WKWebView has no such bug, but it
	does have a failure mode the old one did not: the web content process can die
	on its own, leaving a blank view. Either way the view must not be handed back
	out for reuse.
*/
- (void)webViewWebContentProcessDidTerminate:(WKWebView*)webView
{
	os_log_error(OS_LOG_DEFAULT, "HTMLOutput: web content process terminated for ‘%{public}@’", webView.URL);
	self.needsNewWebView = YES;
}
@end

// ==========================================================================
// = The four URL/string helpers above, reachable from tests                =
// ==========================================================================
//
// They are the whole of this file's logic and every one of them is subtle, so
// they are pinned (rule 18) — but a `static` function cannot be called from a
// test, and making them extern would not survive the port either: Swift can call
// a free function but never export one (rule 19).
//
// Class methods do survive. After the port these are `@objc static func` on the
// Swift class and t_browser_view.mm keeps compiling unchanged, which is the
// property that makes this seam worth having in the shipping binary.
@implementation HOBrowserView (Testing)
+ (BOOL)isProtocolRelativeURL:(NSURL*)url { return IsProtocolRelativeURL(url); }
+ (NSURL*)rewrittenURL:(NSURL*)url        { return RewrittenURL(url);          }
+ (BOOL)isLoadableScheme:(NSURL*)url      { return IsLoadableScheme(url);      }
+ (NSString*)escapeHTML:(NSString*)str    { return EscapeHTML(str);            }
@end
