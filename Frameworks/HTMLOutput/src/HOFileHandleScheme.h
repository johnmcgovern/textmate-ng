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
@end
