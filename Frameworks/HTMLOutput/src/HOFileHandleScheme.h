#import <WebKit/WebKit.h>
#import <oak/misc.h>

// Custom URL scheme used to stream a bundle command’s HTML output into the web view.
extern NSString* const kHOFileHandleURLScheme;

/*
	Bundle command output references its stylesheets, scripts and images with
	absolute file:// URLs (see tm/htmloutput.rb in the Bundle Support bundle). The
	legacy WebView could load them because OakCommand called
	+[WebView registerURLSchemeAsLocal:], which gave the job scheme file-like
	privileges. WKWebView has no equivalent: a custom scheme gets an opaque origin
	and every file:// sub-resource is refused.

	So the streamed HTML is rewritten as it passes through the scheme handler —
	`file://` becomes `<job scheme>://job/__tm_local__` — which keeps those loads on
	the *same origin* as the page and routes them back to us to serve off disk.
	Navigations to such a URL are converted back to file:// by HOBrowserView, so
	clicking a link behaves exactly as before.
*/
extern NSString* const kHOLocalFilePathPrefix;

/*
	The synchronous half of TextMate.system(). WKWebView has no synchronous
	JS↔native call in either direction, so the page issues a *synchronous
	XMLHttpRequest* at this path instead: that blocks only the web content
	process, while the scheme handler answers from the app process and can take as
	long as the command does.

	The command arrives base64-encoded in an HTTP header rather than a POST body —
	WKURLSchemeTask does not deliver HTTPBody.
*/
extern NSString* const kHOSyncCommandPathPrefix;
extern NSString* const kHOSyncCommandHeader;

// TextMate's own scheme for local files. Navigations are rewritten to file:// by
// HOBrowserView (so directory/index.html resolution still applies), but
// *sub-resources* have to be served, which the same handler does.
extern NSString* const kHOTMFileURLScheme;

@protocol HOSyncCommandRunner <NSObject>
- (void)runSyncCommand:(NSString*)aCommand completionHandler:(void(^)(NSString* output, NSString* error, int status))aCompletionHandler;
@end

/*
	The legacy WebView read the streaming file handle straight off the request via
	NSURLProtocol properties. WKWebView copies the request before the URL scheme
	handler ever sees it, and those properties do not survive the copy, so the
	handle and the command’s process group are parked here instead — keyed by the
	request URL, which OakCommand already makes unique per job.

	Registration happens in -[OakHTMLOutputView loadRequest:…], which still holds
	the original request object (and can therefore still read the properties).
	The scheme handler claims the job when the load starts.

	Main thread only.
*/
@interface HOFileHandleJob : NSObject
@property (nonatomic, readonly) NSFileHandle* fileHandle;
@property (nonatomic, readonly) pid_t processIdentifier;
@end

@interface HOFileHandleRegistry : NSObject
+ (instancetype)sharedInstance;
- (void)registerJobForURL:(NSURL*)aURL fileHandle:(NSFileHandle*)aFileHandle processIdentifier:(pid_t)aProcessIdentifier;
- (HOFileHandleJob*)claimJobForURL:(NSURL*)aURL; // one-shot: also removes the entry
- (void)discardJobForURL:(NSURL*)aURL;
@end

@interface HOFileHandleSchemeHandler : NSObject <WKURLSchemeHandler>
// Set while the JavaScript API is installed; nil when the command opted out via
// disableJavaScriptAPI, which also disables the synchronous bridge.
@property (nonatomic, weak) id <HOSyncCommandRunner> syncRunner;
@end

// Rewrites `file://` to the same-origin local prefix across a byte stream,
// holding back a partial match at a chunk boundary until the next chunk arrives.
// Pinned by t_local_url_rewriter.mm.
@interface HOLocalURLRewriter : NSObject
- (NSData*)rewriteChunk:(NSData*)chunk;
@property (nonatomic, readonly) NSData* carry;
@end
