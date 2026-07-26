#import <WebKit/WebKit.h>
#import <oak/misc.h>

@class HOStatusBar;

@interface HOBrowserView : NSView <WKNavigationDelegate>
- (instancetype)initWithFrame:(NSRect)aRect configuration:(WKWebViewConfiguration*)aConfiguration;

// A configuration carrying the x-txmt-filehandle scheme handler. Exposed so the
// UI delegate can honour WebKit's rule that a window opened by script must use
// the configuration WebKit hands it.
+ (WKWebViewConfiguration*)defaultConfiguration;

@property (nonatomic, readonly) WKWebView* webView;
@property (nonatomic, readonly) BOOL needsNewWebView;
@property (nonatomic, readonly) HOStatusBar* statusBar;
- (void)setUpdatesProgress:(BOOL)flag;
@end
