#import <oak/misc.h>

// Custom URL scheme used to stream a bundle command’s HTML output into the web view.
extern NSString* const kHOFileHandleURLScheme;

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
