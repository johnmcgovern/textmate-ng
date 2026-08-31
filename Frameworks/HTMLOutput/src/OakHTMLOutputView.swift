import AppKit
import WebKit
import os

// Ported from OakHTMLOutputView.mm — the framework's public face, and the view
// OakCommand loads a command's output into. A subclass of HOBrowserView, which is
// itself Swift now.
//
// The only C++ was a `std::map` ivar; it went ahead into HOEnvironment (54dbe451)
// and every use of it reaches an ObjC-clean seam. What stayed behind is one
// three-line forwarder in OakHTMLOutputViewCxx.mm: rule 17 keeps
// -loadRequest:environment:autoScrolls: in ObjC++ permanently, because
// OakCommand.mm is its only caller and is not moving.
//
// **This class is declared twice on purpose.** OakHTMLOutputView.h says
// `: HOBrowserView` and is internal; <HTMLOutput/HTMLOutput.h> says `: NSView`
// and is what the four external consumers see, none of which needs anything a
// browser view adds. Both are hand declarations (rule 23) and neither may enter
// the bridging header (rule 43). t_html_output_view.mm pins the runtime answer.

private let log = Logger(subsystem: "com.j23software.TextMate-NG", category: "html-output")

private let kHOScriptMessageHandlerName = "textmate"

// The bundle-facing TextMate object (resources/HTMLOutput.js). Copied into every
// bundle that links HTMLOutput by the seed's require-closure resource pass.
private func BridgeUserScript() -> WKUserScript? {
	guard let url = Bundle(for: OakHTMLOutputView.self).url(forResource: "HTMLOutput", withExtension: "js") else {
		log.error("HTMLOutput: HTMLOutput.js missing from the bundle — the TextMate JavaScript API will be unavailable")
		return nil
	}

	let source: String
	do {
		source = try String(contentsOf: url, encoding: .utf8)
	}
	catch {
		log.error("HTMLOutput: cannot read HTMLOutput.js: \(error.localizedDescription, privacy: .public)")
		return nil
	}

	return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
}

/*
	HOAutoScroll watched the WebFrameView’s document view for frame changes. There
	is no equivalent view to observe under WKWebView (the content lives in another
	process), so the behaviour moves into the page: stick to the bottom only while
	the reader is already at the bottom, re-evaluated on every content resize.

	This is a plain scrolling helper, not the TextMate JavaScript API — that stays
	absent until slice 2.
*/
private func AutoScrollUserScript() -> WKUserScript {
	let source = ""
		+ "(function() {"
		+ "  var stick = true;"
		+ "  var atBottom = function() { return (window.innerHeight + window.scrollY) >= (document.body.scrollHeight - 4); };"
		+ "  window.addEventListener('scroll', function() { stick = atBottom(); }, { passive: true });"
		+ "  var start = function() {"
		+ "    if(!document.body) return;"
		+ "    new ResizeObserver(function() { if(stick) window.scrollTo(0, document.body.scrollHeight); }).observe(document.body);"
		+ "  };"
		+ "  if(document.body) start(); else document.addEventListener('DOMContentLoaded', start);"
		+ "})();"
	return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
}

// The status bar already has every member HOJSBridgeDelegate asks for — busy,
// progress and statusText. The ObjC++ said so with a category in this same file;
// this is that statement, in the same place.
extension HOStatusBar: HOJSBridgeDelegate {
}

// The two values -stopLoadingWithUserInteraction: has to hand to both the
// notification observer and the sheet's completion handler, whichever answers
// first. `@unchecked Sendable` because the guarantee is the same one the ObjC++
// relied on without saying: everything here happens on the main thread.
private final class StopContext: @unchecked Sendable {
	private let handler: (Bool) -> Void
	var token: (any NSObjectProtocol)?

	init(handler: @escaping (Bool) -> Void) {
		self.handler = handler
	}

	// Answers once and unregisters; either path may get here first.
	func finish(_ didStop: Bool) {
		handler(didStop)
		if let token {
			NotificationCenter.default.removeObserver(token)
			self.token = nil
		}
	}
}

@objc(OakHTMLOutputView)
class OakHTMLOutputView: HOBrowserView {
	private var _runningCommand = false
	@objc var runningCommand: Bool {
		@objc(isRunningCommand) get { _runningCommand }
		set { _runningCommand = newValue }
	}

	private var _reusable = false
	@objc var reusable: Bool {
		@objc(isReusable) get { _reusable }
		@objc(setReusable:) set { _reusable = newValue }
	}

	private var _visible = false
	@objc var visible: Bool {
		@objc(isVisible) get { _visible }
		set { _visible = newValue }
	}

	@objc var commandIdentifier: NSUUID?
	@objc var disableJavaScriptAPI: Bool = false

	private var environment: HOEnvironment?
	// The request object OakCommand handed us. WKWebView copies requests, and
	// NSURLProtocol properties do not survive the copy, so the original is kept here
	// for the processName/command lookups that used to read them back off the frame.
	private var initialRequest: URLRequest?
	private var jobURL: URL?
	private var pendingScrollY: CGFloat = 0
	private var jsBridge: HOJSBridge?

	@objc class func keyPathsForValuesAffectingMainFrameTitle() -> Set<String> {
		[ "webView.title" ]
	}

	// The *designated* initialiser, not init(frame:) — that one is a convenience on
	// HOBrowserView and funnels through here, so this covers both entry points the
	// way overriding -initWithFrame: did when both were ObjC.
	override init(frame: NSRect, configuration: WKWebViewConfiguration) {
		super.init(frame: frame, configuration: configuration)
		// Not the ivar's zero: an output window is recycled for the next command
		// unless something opts out.
		_reusable = true
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		MainActor.assumeIsolated {
			if let jobURL {
				HOFileHandleRegistry.sharedInstance.discardJob(forURL: jobURL)
			}
			teardownJavaScriptAPI()
		}
	}

	// The legacy bridge was re-attached per navigation in didClearWindowObject:. A WK
	// user script and message handler are per-content-controller instead, so they are
	// installed for the life of a load and torn down before the next one.
	private func teardownJavaScriptAPI() {
		(webView.configuration.urlSchemeHandler(forURLScheme: kHOFileHandleURLScheme) as? HOFileHandleSchemeHandler)?.syncRunner = nil

		jsBridge?.invalidate()
		jsBridge = nil

		// -removeScriptMessageHandlerForName: is a no-op when nothing is registered,
		// but -addScriptMessageHandler:name: *raises* on a duplicate name, so the
		// remove has to happen before every add.
		webView.configuration.userContentController.removeScriptMessageHandler(forName: kHOScriptMessageHandlerName)
	}

	private func installJavaScriptAPI() {
		let contentController = webView.configuration.userContentController

		guard let script = BridgeUserScript() else {
			return
		}

		let bridge = HOJSBridge()
		bridge.delegate = statusBar
		bridge.webView  = webView
		bridge.setEnvironmentBox(environment)
		jsBridge = bridge

		contentController.add(bridge, name: kHOScriptMessageHandlerName)
		contentController.addUserScript(script)

		// The synchronous form is answered by the scheme handler rather than the
		// message handler, so it needs its own route back to the bridge.
		(webView.configuration.urlSchemeHandler(forURLScheme: kHOFileHandleURLScheme) as? HOFileHandleSchemeHandler)?.syncRunner = bridge
	}

	@objc(loadRequest:environmentBox:autoScrolls:)
	func loadRequest(_ aRequest: URLRequest, environmentBox anEnvironment: HOEnvironment?, autoScrolls flag: Bool) {
		teardownJavaScriptAPI()

		let contentController = webView.configuration.userContentController
		contentController.removeAllUserScripts()
		if flag {
			contentController.addUserScript(AutoScrollUserScript())
		}

		environment = anEnvironment // the bridge copies this, so set it first
		if !disableJavaScriptAPI {
			installJavaScriptAPI()
		}

		// Hand the streaming file handle to the scheme handler. We can still read the
		// NSURLProtocol properties here because this is the original request object.
		if let jobURL {
			HOFileHandleRegistry.sharedInstance.discardJob(forURL: jobURL)
		}
		jobURL = nil

		if let fileHandle = URLProtocol.property(forKey: "fileHandle", in: aRequest) as? FileHandle {
			jobURL = aRequest.url
			let pid = (URLProtocol.property(forKey: "processIdentifier", in: aRequest) as? NSNumber)?.int32Value ?? 0
			HOFileHandleRegistry.sharedInstance.registerJob(forURL: jobURL, fileHandle: fileHandle, processIdentifier: pid)
		}

		initialRequest    = aRequest
		commandIdentifier = URLProtocol.property(forKey: "commandIdentifier", in: aRequest) as? NSUUID
		runningCommand    = commandIdentifier != nil

		webView.load(aRequest)
	}

	@objc(stopLoadingWithUserInteraction:completionHandler:)
	func stopLoading(withUserInteraction askUserFlag: Bool, completionHandler handler: @escaping (Bool) -> Void) {
		guard let request = initialRequest, let command = URLProtocol.property(forKey: "command", in: request) else {
			// Nothing was running, so answer *synchronously* with YES — the caller
			// closes the window on that.
			handler(true)
			return
		}

		// -tmAlertWithMessageText:…buttons: is an ObjC variadic, which Swift cannot
		// call; it only sets two strings and adds buttons, so this is the same alert.
		var alert: NSAlert? = nil
		if askUserFlag {
			let processName = (URLProtocol.property(forKey: "processName", in: request) as? String) ?? ""
			let a = NSAlert()
			a.messageText     = "Stop “\(processName)”?"
			a.informativeText = "The job that the task is performing will not be completed."
			a.addButton(withTitle: "Stop")
			a.addButton(withTitle: "Cancel")
			alert = a
		}

		// The observer fires on whichever thread posts, and both it and the sheet's
		// completion need the same two values. The ObjC++ captured them with a
		// __block token and assumed main-thread delivery; the box says that out loud
		// instead — OakCommand posts OakCommandDidTerminateNotification on the main
		// thread, which is also the only thread that reads these back.
		let context = StopContext(handler: handler)

		context.token = NotificationCenter.default.addObserver(forName: NSNotification.Name("OakCommandDidTerminateNotification"), object: command, queue: nil) { [weak self] _ in
			MainActor.assumeIsolated {
				if let alert {
					self?.window?.endSheet(alert.window, returnCode: .alertFirstButtonReturn)
				}
				context.finish(true)
			}
		}

		if let alert, let window {
			alert.beginSheetModal(for: window) { [weak self] returnCode in
				if returnCode == .alertFirstButtonReturn { // "Stop"
					self?.webView.stopLoading()
				}
				else {
					context.finish(false)
				}
			}
		}
		else {
			webView.stopLoading()
		}
	}

	@objc(setContent:)
	func setContent(_ someHTML: String) {
		// The scroll offset used to be read straight off the document view. Reading it
		// out of the page is asynchronous, so the load moves into the completion
		// handler to keep save-then-replace ordering intact.
		webView.evaluateJavaScript("window.scrollY") { [weak self] result, error in
			MainActor.assumeIsolated {
				guard let self else {
					return
				}
				self.pendingScrollY = (result as? NSNumber)?.doubleValue ?? 0
				self.webView.loadHTMLString(someHTML, baseURL: URL(fileURLWithPath: NSHomeDirectory()))
			}
		}
	}

	@objc var mainFrameTitle: String {
		if OakIsEmptyString(webView.title) {
			if let request = initialRequest, let processName = URLProtocol.property(forKey: "processName", in: request) as? String {
				return processName
			}
			// "" rather than nil: the window binds to this, and nil would leave the
			// previous title in place.
			return ""
		}
		return webView.title ?? ""
	}

	override func viewDidMoveToWindow() {
		NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
		if let window {
			NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: window)
		}
		visible = window != nil
	}

	@objc func windowWillClose(_ aNotification: Notification?) {
		visible = false
	}

	// ========================
	// = Navigation  Delegate =
	// ========================

	override func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
		statusBar.isBusy = true
		setUpdatesProgress(!runningCommand)
	}

	override func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		runningCommand = false

		// This happens when we redirect to a PDF file
		if let window, window.firstResponder === window {
			let rect = webView.frame
			var view = webView.hitTest(NSPoint(x: rect.midX, y: rect.midY))
			while let candidate = view {
				if candidate.acceptsFirstResponder {
					window.makeFirstResponder(candidate)
					break
				}
				view = candidate.superview
			}
		}

		if pendingScrollY > 0 {
			webView.evaluateJavaScript(String(format: "window.scrollTo(0, %.0f);", pendingScrollY), completionHandler: nil)
			pendingScrollY = 0
		}

		super.webView(webView, didFinish: navigation)
	}

	override func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		runningCommand = false
		super.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
	}

	override func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		runningCommand = false
		super.webView(webView, didFail: navigation, withError: error)
	}

	// ==========================================
	// = Navigation policy : Intercept txmt:// =
	// ==========================================

	override func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
		var url = navigationAction.request.url
		if url?.scheme == "txmt" {
			decisionHandler(.cancel)

			if let projectUUID = environment?.value(forVariable: "TM_PROJECT_UUID"), let current = url {
				url = URL(string: current.absoluteString + "&project=\(projectUUID)")
			}
			NSApp.sendAction(NSSelectorFromString("handleTxMtURL:"), to: nil, from: url)
			return
		}

		super.webView(webView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler)
	}

	// ====================
	// = Printing Support =
	// ====================

	@objc func printDocument(_ sender: Any?) {
		// -[WKWebView printOperationWithPrintInfo:] takes the print info up front,
		// where the legacy path mutated it on an already-created operation.
		let info = NSPrintInfo.shared.copy() as! NSPrintInfo

		let display = info.imageablePageBounds.intersection(NSRect(origin: .zero, size: info.paperSize))
		info.leftMargin   = display.minX
		info.rightMargin  = info.paperSize.width - display.maxX
		info.topMargin    = info.paperSize.height - display.maxY
		info.bottomMargin = display.minY

		let printer = webView.printOperation(with: info)
		printer.printPanel.options = printer.printPanel.options.union([ .showsPaperSize, .showsOrientation ])
		printer.runModal(for: window!, delegate: nil, didRun: nil, contextInfo: nil)
	}
}
