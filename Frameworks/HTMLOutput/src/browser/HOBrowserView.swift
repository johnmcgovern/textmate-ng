import AppKit
import WebKit
import os

// Ported from HOBrowserView.mm — the web view, its status bar and the navigation
// policy that decides what an HTML output window may load.
//
// The four helpers at the bottom are the whole of this file's logic and all of it
// is the kind that fails quietly: a URL rewritten slightly wrong loads the wrong
// page rather than raising. They were pinned first (1083677b) through a Testing
// category, and they are `@objc static func` here for exactly that reason —
// t_browser_view.mm compiles against them unchanged. A free function would not
// have survived, since Swift can call one but never export one (rule 19).
//
// The single C++ call, path::exists, is `access(path, F_OK) == 0` — that is its
// definition, not an approximation — so this file needed no boundary.
//
// The class's ObjC face is the hand declaration in HOBrowserView.h (rule 23).

private let log = Logger(subsystem: "com.j23software.TextMate-NG", category: "html-output")

private let kUserDefaultsDefaultURLProtocolKey = "defaultURLProtocol"

@objc(HOBrowserView)
class HOBrowserView: NSView, @preconcurrency WKNavigationDelegate {
	private nonisolated(unsafe) static var progressContext = 0

	private var _webView: WKWebView!
	private var _statusBar: HOStatusBar!
	private var _needsNewWebView: Bool = false

	@objc var webView: WKWebView { _webView }
	@objc var statusBar: HOStatusBar { _statusBar }
	@objc var needsNewWebView: Bool { _needsNewWebView }

	private var webViewDelegateHelper: HOWebViewDelegateHelper!
	private var observingProgress: Bool = false

	@objc class func defaultConfiguration() -> WKWebViewConfiguration {
		let config = WKWebViewConfiguration()
		// One handler, two schemes: the job stream plus tm-file sub-resources.
		let handler = HOFileHandleSchemeHandler()
		config.setURLSchemeHandler(handler, forURLScheme: kHOFileHandleURLScheme)
		config.setURLSchemeHandler(handler, forURLScheme: kHOTMFileURLScheme)
		return config
	}

	override convenience init(frame: NSRect) {
		self.init(frame: frame, configuration: HOBrowserView.defaultConfiguration())
	}

	@objc(initWithFrame:configuration:)
	init(frame: NSRect, configuration: WKWebViewConfiguration) {
		super.init(frame: frame)

		_webView = WKWebView(frame: .zero, configuration: configuration)

		// WKWebView draws its own two-finger back/forward swipe, including the
		// page-peek animation the old trackSwipeEventWithOptions: handler left as
		// a TODO, so the manual scrollWheel: tracking is gone.
		_webView.allowsBackForwardNavigationGestures = true

		_statusBar = HOStatusBar(frame: .zero)
		_statusBar.delegate = _webView // WKWebView has goBack:/goForward: actions

		webViewDelegateHelper          = HOWebViewDelegateHelper()
		webViewDelegateHelper.delegate = _statusBar
		_webView.uiDelegate            = webViewDelegateHelper
		_webView.navigationDelegate    = self

		let views: [String: NSView] = [
			"webView":   _webView,
			"statusBar": _statusBar,
		]

		OakAddAutoLayoutViewsToSuperview(Array(views.values), self)

		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[webView(>=10)]|", options: [], metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[webView(>=10)][statusBar]|", options: [.alignAllLeft, .alignAllRight], metrics: nil, views: views))
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		MainActor.assumeIsolated {
			setUpdatesProgress(false)
			_webView.navigationDelegate = nil
			_webView.uiDelegate         = nil
			_webView.stopLoading()
		}
	}

	// WebViewProgress* notifications do not exist for WKWebView; estimatedProgress is
	// KVO-compliant instead. Keeping the same on/off entry point the callers already use.
	@objc(setUpdatesProgress:)
	func setUpdatesProgress(_ flag: Bool) {
		guard flag != observingProgress else {
			return
		}

		if flag {
			_webView.addObserver(self, forKeyPath: "estimatedProgress", options: [], context: &Self.progressContext)
		}
		else {
			_webView.removeObserver(self, forKeyPath: "estimatedProgress", context: &Self.progressContext)
		}

		observingProgress = flag
	}

	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		if context == &Self.progressContext {
			_statusBar.progress = _webView.estimatedProgress
		}
		else {
			super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
		}
	}

	// ==============
	// = Key Events =
	// ==============

	/*
	Since the webView is typically the first responder, the path for key events is as follows:

	For keyDown:
		webView
		HOBrowserView
		OakHTMLOutputView
		NSWindow

	For performKeyEquivalent:
		NSWindow
		OakHTMLOutputView
		HOBrowserView
		webView

	A webView default implementation passes all key events, including potential key equivalents (except ESC),
	to the webpage so that it may have a chance to respond. Unfortunately, we cannot know if these events are
	handled so the events are still forwarded down their respective chains as shown above. So to avoid the
	NSBeep when hitting the end of the responder chain, we let HOBrowserView swallow all key events. This is
	safe since performKeyEquivalent: is called first, which leads to another problem: we can pass
	the key event back to the webView (minus the modifier). Therefore, we also terminate the above chain for
	performKeyEquivalent: by overriding the method here and returning just NO. Note: that if none of the views
	in the hierachy returns YES, the key (equivalent) event is then passed to the menus.
	*/

	// **This does not override anything, and never did.** NSView's method is
	// -performKeyEquivalent:(NSEvent*), with an argument; this one has none, so
	// AppKit never calls it and the comment above describes an intent the code does
	// not carry out. Ported as-is rather than corrected: giving it the real
	// signature would start swallowing key equivalents before the web view sees
	// them, which is a behaviour change and belongs in its own commit.
	@objc func performKeyEquivalent() -> Bool {
		false
	}

	override func keyDown(with anEvent: NSEvent) {
	}

	// ========================
	// = Navigation  Delegate =
	// ========================

	func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
		_statusBar.busy = true
		setUpdatesProgress(true)
	}

	func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
		let requested = navigationAction.request.url
		var url = requested

		// Undo the sub-resource rewrite for navigations: the stream turned file:// into
		// the job scheme so stylesheets and images would load same-origin, but a
		// *clicked* file:// link should still go through the normal resolution below
		// (directory -> index.html, error_not_found, and so on).
		if let current = url, current.scheme == kHOFileHandleURLScheme, current.path.hasPrefix(kHOLocalFilePathPrefix) {
			let path = String(current.path.dropFirst(kHOLocalFilePathPrefix.count))
			if !path.isEmpty {
				url = URL(fileURLWithPath: path)
			}
		}

		if let current = url, let rewritten = Self.rewrittenURL(current) {
			url = rewritten
		}

		// WKWebView cannot rewrite a navigation in flight, so any change to the URL —
		// whether from the un-rewrite above or from RewrittenURL — is a cancel plus a
		// fresh load. Compared against what was *requested*, not the working copy.
		if url != requested {
			decisionHandler(.cancel)
			if let url {
				webView.load(URLRequest(url: url))
			}
			return
		}

		if let url, Self.isLoadableScheme(url) {
			decisionHandler(.allow)
		}
		else {
			decisionHandler(.cancel)
			if let url {
				NSWorkspace.shared.open(url)
			}
		}
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		Self.showLoadError(webView, webView.url, error)
		self.webView(webView, didFinish: navigation)
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		Self.showLoadError(webView, webView.url, error)
		self.webView(webView, didFinish: navigation)
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		_statusBar.canGoBack    = _webView.canGoBack
		_statusBar.canGoForward = _webView.canGoForward
		_statusBar.busy         = false
		_statusBar.progress     = 0
	}

	/*
		Replaces the WebKit-bug-121232 workaround the legacy path carried (a WebView
		could not be reused after window.close()). WKWebView has no such bug, but it
		does have a failure mode the old one did not: the web content process can die
		on its own, leaving a blank view. Either way the view must not be handed back
		out for reuse.
	*/
	func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
		log.error("HTMLOutput: web content process terminated for ‘\(webView.url?.absoluteString ?? "", privacy: .public)’")
		_needsNewWebView = true
	}

	/*
		The load-error page used to offer the failing URL as a link that shelled out
		through TextMate.system(). That API is not wired up under WKWebView yet (it
		returns with the JavaScript bridge, Stream 5 slice 3), so the URL is shown as
		plain text for now rather than as a link that would silently do nothing.
	*/
	private static func showLoadError(_ webView: WKWebView, _ url: URL?, _ error: Error) {
		let errorMsg = "<title>Load Error</title><h1>Load Error</h1><p>WebKit reported <em>\(escapeHTML(error.localizedDescription))</em> while loading <tt>\(escapeHTML(url?.absoluteString ?? ""))</tt>.</p>"
		webView.loadHTMLString(errorMsg, baseURL: URL(fileURLWithPath: NSTemporaryDirectory()))
	}

	// ==========================================================================
	// = The four helpers, pinned by t_browser_view.mm                          =
	// ==========================================================================

	@objc(isProtocolRelativeURL:)
	static func isProtocolRelativeURL(_ url: URL) -> Bool {
		if let scheme = url.scheme, scheme.hasPrefix("x-txmt"), url.host != "job" {
			return true
		}

		if url.scheme == "file", let host = url.host {
			// If host has a dot and does not exist on disk then treat as protocol-relative URL
			if host.contains("."), !FileManager.default.fileExists(atPath: "/" + host) {
				return true
			}
		}

		return false
	}

	/*
		Ported from the WebResourceLoadDelegate’s willSendRequest:, which WKWebView has
		no equivalent for. Returns a replacement URL, or nil to load as-is.

		Caveat carried over from the port: the legacy delegate saw *every* resource
		load, so these rewrites also applied to images and stylesheets. A navigation
		policy only sees navigations, so sub-resources are no longer rewritten.
	*/
	@objc(rewrittenURL:)
	static func rewrittenURL(_ aURL: URL) -> URL? {
		var url = aURL

		if url.scheme == "tm-file" {
			let fragment = url.fragment
			let encodedPath = url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path
			// Rebuilt by string, so the fragment survives only because it is put back.
			if let rebuilt = URL(string: "file://localhost\(encodedPath)\(fragment != nil ? "#" : "")\(fragment ?? "")") {
				url = rebuilt
			}
		}

		if isProtocolRelativeURL(url) {
			if var components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
				components.scheme = UserDefaults.standard.string(forKey: kUserDefaultsDefaultURLProtocolKey)
				if let replaced = components.url {
					url = replaced
				}
			}
		}

		if url.isFileURL {
			let errorPage = Bundle(for: HOBrowserView.self).path(forResource: "error_not_found", ofType: "html") ?? ""
			var redirectURL = URL(string: "file://localhost\(errorPage.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")?path=\(url.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&error=1")

			let fileURL = url
			fileURL.withUnsafeFileSystemRepresentation { pathPtr in
				guard let pathPtr else {
					return
				}

				var buf = stat()
				if stat(pathPtr, &buf) == 0 {
					if (buf.st_mode & S_IFMT) == S_IFREG || (buf.st_mode & S_IFMT) == S_IFLNK {
						redirectURL = nil
					}
					else if (buf.st_mode & S_IFMT) == S_IFDIR {
						// path::exists is access(_, F_OK) == 0, which is what this is.
						let joined = (String(cString: pathPtr) as NSString).appendingPathComponent("index.html")
						if access(joined, F_OK) == 0 {
							if var urlString = URL(string: "index.html", relativeTo: fileURL)?.absoluteString {
								if let query = fileURL.query {
									urlString += "?\(query)"
								}
								if let fragment = fileURL.fragment {
									urlString += "#\(fragment)"
								}
								redirectURL = URL(string: urlString)
							}
						}
					}
				}
			}

			if let redirectURL {
				url = redirectURL
			}
		}

		return url
	}

	// Schemes the web view can load itself. Spelled out rather than asking
	// +[NSURLConnection canHandleRequest:] as the legacy path did: the streaming job
	// scheme is served by a WKURLSchemeHandler now, not a registered NSURLProtocol,
	// so NSURLConnection no longer knows about it.
	private static let loadableSchemes: Set<String> = [ "http", "https", "file", "data", "about", "blob", kHOFileHandleURLScheme ]

	@objc(isLoadableScheme:)
	static func isLoadableScheme(_ url: URL) -> Bool {
		guard let scheme = url.scheme else {
			return false
		}
		return loadableSchemes.contains(scheme.lowercased())
	}

	@objc(escapeHTML:)
	static func escapeHTML(_ str: String) -> String {
		// `&` first, which is what stops the `&` of `&lt;` being escaped again. `>`
		// is deliberately not in the set.
		str.replacingOccurrences(of: "&", with: "&amp;")
		   .replacingOccurrences(of: "<", with: "&lt;")
		   .replacingOccurrences(of: "\"", with: "&quot;")
	}
}
