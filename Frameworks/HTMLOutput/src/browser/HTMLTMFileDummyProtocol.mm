#import <Foundation/Foundation.h>

// An NSURLProtocol that claims the tm-file scheme and does nothing with it.
//
// Moved verbatim out of HOWebViewDelegateHelper.mm, which is otherwise portable:
// this class registers itself from +load, and +load has no Swift spelling at all.
// Unlike +initialize there is no "do it on first construction" equivalent either,
// because nothing ever constructs this — registering at load time is the whole
// point. So it has to keep an ObjC++ home, and it should not keep one inside a
// file that is about to become Swift.
//
// ==========================================================================
// = It is almost certainly dead, and that is a separate decision to make   =
// ==========================================================================
//
// It is referenced nowhere; +load is its only entry point. The evidence that its
// one consumer is gone:
//
//   * A "dummy" protocol claiming a scheme is the trick that makes
//     +[NSURLConnection canHandleRequest:] answer YES for it. The legacy path
//     asked exactly that question to decide whether the web view could load a
//     URL itself — and HOBrowserView.mm now says, in the comment above
//     IsLoadableScheme, that the port replaced that call with an explicit set.
//     Nothing in the tree calls +canHandleRequest: any more.
//
//   * WKWebView does not consult NSURLProtocol subclasses registered in the app
//     process; its loads happen in the networking process. So even a tm-file
//     navigation would not reach this.
//
//   * tm-file has two live paths and neither is this one: RewrittenURL turns a
//     tm-file *navigation* into file://localhost before the scheme check, and
//     tm-file *sub-resources* are served by the WKURLSchemeHandler in
//     HOFileHandleScheme.mm.
//
//   * The other NSURLProtocol uses in the tree (OakCommand, OakHTMLOutputView)
//     are +setProperty:forKey:inRequest: and +propertyForKey:inRequest: — using
//     the class as a key-value store on a request, unrelated to registration.
//
//   * The one remaining legacy WebView (PlugIns/dialog's TMDHTMLTips) loads with
//     -loadHTMLString:baseURL:nil and never fetches a tm-file URL.
//
// Keeping it is not free: +canInitWithRequest: claims tm-file while the class
// implements no -startLoading, so any app-process NSURLSession load of such a URL
// would be claimed and then stall. That is latent rather than live, since no such
// load exists — but it is a trap, not merely dead weight.
//
// **Left in place deliberately.** Deleting a registered URL protocol is a
// behaviour change, and this commit is a move; the two should not be the same
// commit. It is now one `git rm` away whenever that call is made.

@interface HTMLTMFileDummyProtocol : NSURLProtocol { }
@end

@implementation HTMLTMFileDummyProtocol
+ (void)load                                                                                                                                      { [self registerClass:self]; }
+ (BOOL)canInitWithRequest:(NSURLRequest*)request                                                                                                 { return [[[request URL] scheme] isEqualToString:@"tm-file"]; }
+ (NSURLRequest*)canonicalRequestForRequest:(NSURLRequest*)request                                                                                { return request; }
+ (BOOL)requestIsCacheEquivalent:(NSURLRequest*)a toRequest:(NSURLRequest*)b                                                                      { return NO; }
@end
