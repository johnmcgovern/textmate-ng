@protocol HOJSBridgeDelegate
@property (nonatomic, getter = isBusy) BOOL busy;
@property (nonatomic) double progress;
@end

/*
	The app half of the bundle-facing `TextMate` JavaScript object.

	WKWebView cannot hand a native object to the page the way WebScriptObject did,
	so the object itself lives in resources/HTMLOutput.js and this class is the
	WKScriptMessageHandler behind it. Output from a running command is pushed back
	into the page with -evaluateJavaScript:.

	The message handler must be registered under the name "textmate".
*/
@interface HOJSBridge : NSObject <WKScriptMessageHandler>
@property (nonatomic, weak) id <HOJSBridgeDelegate> delegate;
@property (nonatomic, weak) WKWebView* webView;

- (void)setEnvironment:(const std::map<std::string, std::string>&)variables;
- (std::map<std::string, std::string> const&)environment;

// Cancels every in-flight command and forgets it. Call on navigation and teardown:
// the page that owns these command objects is going away.
- (void)invalidate;
@end
