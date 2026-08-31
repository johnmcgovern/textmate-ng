// Hand-declared (rule 23): this class is defined in OakHTMLOutputView.swift.
//
// The *internal* declaration — <HTMLOutput/HTMLOutput.h> carries a second,
// narrower one saying `: NSView` for the four external consumers, none of which
// needs anything a browser view adds. Both are hand declarations and neither may
// enter HTMLOutput-Bridging-Header.h (rule 43). The runtime superclass is pinned
// by t_html_output_view.mm.
//
// The std::map-typed -loadRequest:environment:autoScrolls: lives in
// OakHTMLOutputViewCxx.h.
#import "browser/HOBrowserView.h"
#import "HOEnvironment.h"
@interface OakHTMLOutputView : HOBrowserView
- (void)loadRequest:(NSURLRequest*)aRequest environmentBox:(HOEnvironment*)anEnvironment autoScrolls:(BOOL)flag;
- (void)stopLoadingWithUserInteraction:(BOOL)askUserFlag completionHandler:(void(^)(BOOL didStop))handler;
- (void)setContent:(NSString*)someHTML;

@property (nonatomic, readonly) NSString* mainFrameTitle;
@property (nonatomic) NSUUID* commandIdentifier; // UUID from initial load request
@property (nonatomic, getter = isRunningCommand, readonly) BOOL runningCommand;
@property (nonatomic, getter = isReusable) BOOL reusable;
@property (nonatomic) BOOL disableJavaScriptAPI;
@end
