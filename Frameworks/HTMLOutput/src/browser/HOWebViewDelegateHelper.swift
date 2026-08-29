import AppKit
import WebKit

// Ported from HOWebViewDelegateHelper.mm — the WKUIDelegate for an HTML output
// view: the three panels JavaScript can raise, plus window.open and
// window.close.
//
// **Almost none of this is covered by tests, and it cannot be.** Every method
// here ends in a sheet or a new window positioned against the web view's own
// window, so there is nothing to assert without one. It is listed under "what has
// no automated coverage" for the release, and it was exercised by hand.
//
// -[NSAlert tmAlertWithMessageText:informativeText:buttons:] and -addButtons: did
// not come with it: both are ObjC variadics, which Swift cannot call at all. They
// are also pure convenience — between them they set two strings and call
// -addButtonWithTitle: once per title — so the alerts below are built with
// NSAlert's own API to exactly the same result. That is an equivalence, not a
// substitution: no prerequisite was needed in OakAppKit.
//
// The class's ObjC face is the hand declaration in HOWebViewDelegateHelper.h
// (rule 23).

@objc(HOWebViewDelegateHelper)
class HOWebViewDelegateHelper: NSObject, @preconcurrency WKUIDelegate {
	// Vestigial, and kept as it was: nothing assigns this and nothing reads it —
	// HOBrowserView creates the helper with -new and never sets it — and
	// HOWebViewDelegateHelperProtocol has no adopters. Removing them is a separate
	// decision from this port.
	@objc weak var delegate: AnyObject?

	// ================
	// = WKUIDelegate =
	// ================

	func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
		let alert = NSAlert()
		alert.messageText     = NSLocalizedString("Script Message", comment: "JavaScript alert title")
		alert.informativeText = message
		alert.addButton(withTitle: NSLocalizedString("OK", comment: "JavaScript alert confirmation"))

		guard let window = webView.window else {
			// Unreachable in practice — a script raising an alert implies an on-screen
			// web view. The handler is still called, because leaving it uncalled stalls
			// the page's JavaScript for good; that is WKWebView's contract, not a
			// choice about what the alert should say.
			completionHandler()
			return
		}

		alert.beginSheetModal(for: window) { _ in
			completionHandler()
		}
	}

	func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
		let alert = NSAlert()
		alert.messageText     = NSLocalizedString("Script Message", comment: "JavaScript alert title")
		alert.informativeText = message
		alert.addButton(withTitle: NSLocalizedString("OK", comment: "JavaScript alert confirmation"))
		alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "JavaScript alert cancel"))

		guard let window = webView.window else {
			completionHandler(false)
			return
		}

		// A sheet, where the legacy WebUIDelegate ran this one modally: WKWebView
		// cannot block for the answer, so the completion handler carries it back.
		alert.beginSheetModal(for: window) { returnCode in
			completionHandler(returnCode == .alertFirstButtonReturn)
		}
	}

	func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
		let panel = NSOpenPanel()
		panel.directoryURL            = URL(fileURLWithPath: NSHomeDirectory())
		panel.allowsMultipleSelection = parameters.allowsMultipleSelection

		guard let window = webView.window else {
			completionHandler(nil)
			return
		}

		panel.beginSheetModal(for: window) { returnCode in
			completionHandler(returnCode == .OK ? panel.urls : nil)
		}
	}

	func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
		// Written through Optionals rather than guarded, so a web view with no window
		// still lands where the ObjC++ put it: messaging nil there yielded zeroes and
		// the new window was positioned from them.
		let hostFrame = webView.window?.frame ?? .zero
		var origin = webView.window?.cascadeTopLeft(from: NSPoint(x: hostFrame.minX, y: hostFrame.maxY)) ?? .zero
		origin.y -= hostFrame.height

		// WebKit requires the returned view to be built from the configuration it
		// supplies here — creating our own would sever the script relationship with
		// the opener and raise.
		let view = HOBrowserView(frame: .zero, configuration: configuration)
		let window = NSWindow(contentRect: NSRect(origin: origin, size: NSSize(width: 750, height: 800)),
		                      styleMask: [ .titled, .closable, .resizable, .miniaturizable ],
		                      backing: .buffered,
		                      defer: false)
		window.bind(.title, to: view.webView, withKeyPath: "title", options: nil)
		window.contentView = view

		// WebKit loads navigationAction.request into the new view itself; loading it
		// here as well would double-fetch (and re-run the command for a job URL).

		// The window owns itself until it is closed — the retain balances
		// -setReleasedWhenClosed:, and without it nothing holds the window at all.
		_ = Unmanaged.passRetained(window)
		window.isReleasedWhenClosed = true

		return view.webView
	}

	func webViewDidClose(_ webView: WKWebView) {
		if !webView.tryToPerform(NSSelectorFromString("toggleHTMLOutput:"), with: self) {
			webView.tryToPerform(NSSelectorFromString("performClose:"), with: self)
		}
	}
}
