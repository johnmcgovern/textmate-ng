// Hand-declared (rule 23): this class is defined in HOBrowserView.swift.
//
// It must not appear in HTMLOutput-Bridging-Header.h, where it would collide with
// the generated HTMLOutput-Swift.h (rule 43) — it was there for the
// HOWebViewDelegateHelper port and has been taken back out.
#import <WebKit/WebKit.h>
#import <oak/misc.h>

@class HOStatusBar;

NS_ASSUME_NONNULL_BEGIN

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

NS_ASSUME_NONNULL_END
