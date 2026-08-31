#import <WebKit/WebKit.h>
#import "../HOFileHandleScheme.h"

@protocol HOJSBridgeDelegate
@property (nonatomic, getter = isBusy) BOOL busy;
@property (nonatomic) double progress;
@property (nonatomic) NSString* statusText; // link under the pointer; see HTMLOutput.js
@end

/*
	The app half of the bundle-facing `TextMate` JavaScript object.

	WKWebView cannot hand a native object to the page the way WebScriptObject did,
	so the object itself lives in resources/HTMLOutput.js and this class is the
	WKScriptMessageHandler behind it. Output from a running command is pushed back
	into the page with -evaluateJavaScript:.

	The message handler must be registered under the name "textmate".
*/
@class HOEnvironment;

@interface HOJSBridge : NSObject <WKScriptMessageHandler, HOSyncCommandRunner>
@property (nonatomic, weak) id <HOJSBridgeDelegate> delegate;
@property (nonatomic, weak) WKWebView* webView;

- (void)setEnvironment:(const std::map<std::string, std::string>&)variables;
- (std::map<std::string, std::string> const&)environment;
// ObjC-clean spelling of -setEnvironment:, for callers that cannot name a
// std::map. OakHTMLOutputView is Swift and is the only one that sets this.
- (void)setEnvironmentBox:(HOEnvironment*)environmentBox;

// Cancels every in-flight command and forgets it. Call on navigation and teardown:
// the page that owns these command objects is going away.
- (void)invalidate;
@end
