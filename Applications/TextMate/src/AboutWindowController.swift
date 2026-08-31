import AppKit
import WebKit
import CommonCrypto
import os

// Ported from AboutWindowController.mm — the About window, five pages of bundled
// HTML behind a segmented control. The application shell's first Swift file.
//
// **No boundary file was needed**, which is unusual enough to say why. The three
// non-Objective-C uses in the original were `std::min`, `std::exchange` and
// CC_SHA1 — the first two are one-liners in Swift and the third is a *C* API, not
// C++. Nothing here had to be extracted first.
//
// CC_SHA1 is kept rather than modernised to CryptoKit on purpose: the digest is
// compared against one stored in NSUserDefaults to decide whether the release
// notes changed. A different algorithm would not match the stored value, so every
// existing user would be shown the notes once for no reason.
//
// The class's ObjC face is the hand declaration in AboutWindowController.h
// (rule 23) — AppController.mm is its only consumer.

private let log = Logger(subsystem: "com.j23software.TextMate-NG", category: "about")

private let kUserDefaultsReleaseNotesDigestKey = "releaseNotesDigest"

private func Digest(_ someString: String) -> Data {
	var md = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
	let bytes = Array(someString.utf8)
	CC_SHA1(bytes, CC_LONG(bytes.count), &md)
	return Data(md)
}

private func RemoveOldCommits(_ src: [String: Any]) -> [String: Any] {
	var res = src
	var commits: [Any] = []

	let year = Calendar(identifier: .gregorian).component(.year, from: Date())
	let years = ((year - 2)...year).map { String(format: "%4zu-", $0) }

	for commit in (src["commits"] as? [[String: Any]]) ?? [] {
		let dateString = (commit["date"] as? String) ?? ""
		for prefix in years {
			// this is significantly faster than having to parse the date
			if dateString.hasPrefix(prefix) {
				commits.append(commit)
			}
		}
	}

	res["commits"] = commits
	return res
}

@objc(AboutWindowController)
class AboutWindowController: NSWindowController, @preconcurrency NSWindowDelegate, @preconcurrency NSToolbarDelegate, @preconcurrency WKNavigationDelegate, @preconcurrency WKScriptMessageHandler {
	@objc private(set) var segmentLabels: [String] = []
	@objc var toolbar: NSToolbar?
	@objc var segmentedControl: NSSegmentedControl!
	@objc var webView: WKWebView!

	private var _selectedPage: String?
	@objc var selectedPage: String? {
		get { _selectedPage }
		set {
			guard _selectedPage != newValue else {
				return
			}
			// **Assigned before the lookup**, deliberately: a name that is not one of
			// the five is still recorded here and then falls out of the `if` below, so
			// nothing loads and the control does not move. Pinned in t_about_window.mm.
			_selectedPage = newValue

			let pages = [
				"About":         "About/About",
				"Changes":       "About/Changes",
				"Bundles":       "About/Bundles",
				"Legal":         "About/Legal",
				"Contributions": "About/Contributions",
			]

			if let pageName = newValue, let file = pages[pageName] {
				if let url = Bundle.main.url(forResource: file, withExtension: "html") {
					webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60))
				}
				segmentedControl.selectedSegment = segmentLabels.firstIndex(of: pageName) ?? -1
			}
		}
	}

	@objc static let sharedInstance = AboutWindowController()

	@objc class func showChangesIfUpdated() {
		let url = Bundle.main.url(forResource: "Changes", withExtension: "html")
		DispatchQueue.global(qos: .utility).async {
			guard let url, let releaseNotes = try? String(contentsOf: url, encoding: .utf8) else {
				return
			}

			let lastDigest    = UserDefaults.standard.data(forKey: kUserDefaultsReleaseNotesDigestKey)
			let currentDigest = Digest(releaseNotes)
			DispatchQueue.main.async {
				MainActor.assumeIsolated {
					// Only when a digest was already stored: a first run records the notes
					// rather than showing them.
					if let lastDigest, lastDigest != currentDigest {
						AboutWindowController.sharedInstance.showChangesWindow(self)
					}
					UserDefaults.standard.set(currentDigest, forKey: kUserDefaultsReleaseNotesDigestKey)
				}
			}
		}
	}

	init() {
		let visibleRect = NSScreen.main?.visibleFrame ?? .zero
		var rect = NSRect(x: 0, y: 0, width: min(700, visibleRect.width), height: min(800, visibleRect.height))

		let dy = visibleRect.height - rect.height

		rect.origin.y = round(visibleRect.minY + dy*3/4)
		// maxY, not maxX — as it was. On a single screen at origin zero the two are
		// interchangeable, which is presumably why it has never been noticed.
		rect.origin.x = visibleRect.maxY - rect.maxY

		let win = NSPanel(contentRect: rect, styleMask: [ .titled, .closable, .resizable, .miniaturizable, .fullSizeContentView ], backing: .buffered, defer: false)

		super.init(window: win)

		segmentLabels    = [ "About", "Changes", "Bundles", "Legal", "Contributions" ]
		segmentedControl = NSSegmentedControl(labels: segmentLabels, trackingMode: .selectOne, target: self, action: #selector(takeSelectedSegmentFrom(_:)))

		let toolbar = NSToolbar(identifier: "About TextMate")
		toolbar.allowsUserCustomization = false
		toolbar.displayMode             = .iconOnly
		toolbar.delegate                = self
		self.toolbar = toolbar
		win.toolbar  = toolbar

		win.setFrameAutosaveName("BundlesReleaseNotes")
		win.delegate                    = self
		win.autorecalculatesKeyViewLoop = true
		win.hidesOnDeactivate           = false
		win.titleVisibility             = .hidden

		let webConfig = WKWebViewConfiguration()
		webConfig.userContentController.add(self, name: "textmate")

		webView = WKWebView(frame: .zero, configuration: webConfig)
		webView.navigationDelegate = self
		// A private property, reached by KVC as it was.
		webView.setValue(false, forKey: "drawsBackground")

		if let url = Bundle.main.url(forResource: "WKWebView", withExtension: "js") {
			do {
				var jsBridge = try String(contentsOf: url, encoding: .utf8)

				let variables: [String: Any?] = [
					"version":   Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString"),
					"copyright": Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright"),
				]

				for (key, value) in variables {
					jsBridge += "TextMate.\(key) = \(javaScriptEscapedString((value as? String) ?? ""));\n"
				}

				webView.configuration.userContentController.addUserScript(WKUserScript(source: jsBridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
			}
			catch {
				log.error("Failed to load WKWebView.js: \(error.localizedDescription, privacy: .public)")
			}
		}
		else {
			log.error("Failed to locate WKWebView.js in application bundle")
		}

		webView.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive  = true
		webView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

		win.contentView = webView
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		MainActor.assumeIsolated {
			webView.configuration.userContentController.removeAllUserScripts()
			webView.navigationDelegate = nil
			webView.stopLoading()
		}
	}

	@objc func showAboutWindow(_ sender: Any?) {
		selectedPage = "About"
		showWindow(self)
	}

	@objc func showChangesWindow(_ sender: Any?) {
		selectedPage = "Changes"
		showWindow(self)

		if let url = Bundle.main.url(forResource: "Changes", withExtension: "html"), let releaseNotes = try? String(contentsOf: url, encoding: .utf8) {
			UserDefaults.standard.set(Digest(releaseNotes), forKey: kUserDefaultsReleaseNotesDigestKey)
		}
	}

	@objc func takeSelectedSegmentFrom(_ sender: Any?) {
		if let sender = sender as? NSSegmentedControl, sender === segmentedControl {
			selectedPage = segmentLabels[segmentedControl.selectedSegment]
		}
		else if let item = sender as? NSMenuItem {
			selectedPage = item.representedObject as? String
		}
	}

	@objc func selectPage(atRelativeOffset offset: Int) {
		// NSNotFound in the ObjC++: a page name that is not in the list returns early
		// rather than wrapping a garbage index.
		guard let index = segmentLabels.firstIndex(of: selectedPage ?? "") else {
			return
		}
		// The `+ count` is what keeps a backwards step off the front positive.
		selectedPage = segmentLabels[(index + segmentLabels.count + offset) % segmentLabels.count]
	}

	@objc func selectNextTab(_ sender: Any?)     { selectPage(atRelativeOffset: +1) }
	@objc func selectPreviousTab(_ sender: Any?) { selectPage(atRelativeOffset: -1) }

	// ====================
	// = Toolbar Delegate =
	// ====================

	func toolbar(_ aToolbar: NSToolbar, itemForItemIdentifier anIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
		let res = NSToolbarItem(itemIdentifier: anIdentifier)
		if anIdentifier != .flexibleSpace {
			res.view = segmentedControl
		}
		return res
	}

	func toolbarAllowedItemIdentifiers(_ aToolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		toolbarDefaultItemIdentifiers(aToolbar)
	}

	func toolbarDefaultItemIdentifiers(_ aToolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		[ .flexibleSpace, NSToolbarItem.Identifier("TMSegmentedControlIdentifier"), .flexibleSpace ]
	}

	@objc func updateShowTabMenu(_ aMenu: NSMenu) {
		guard window?.isKeyWindow == true else {
			aMenu.addItem(withTitle: "No Tabs", action: NSSelectorFromString("nop:"), keyEquivalent: "")
			return
		}

		for (i, label) in segmentLabels.enumerated() {
			let item = aMenu.addItem(withTitle: label, action: #selector(takeSelectedSegmentFrom(_:)), keyEquivalent: i < 9 ? String(UnicodeScalar(UInt8(ascii: "1") + UInt8(i))) : "")
			item.representedObject = label
			item.target = self
			item.state = i == segmentedControl.selectedSegment ? .on : .off
		}
	}

	// =============
	// = WKWebView =
	// =============

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		guard _selectedPage == "Bundles" else {
			return
		}

		var first = true
		var str = "{\"bundles\":["
		// Already filtered to installed-with-a-path — see AboutBundlesSupport.h for
		// why the summary crosses rather than BundlesManager's own model.
		for bundle in AboutBundlesSupport.installedBundles() {
			let changesPath = (bundle.path as NSString).appendingPathComponent("Changes.json")
			do {
				let content = try String(contentsOfFile: changesPath, encoding: .utf8)
				guard let obj = try JSONSerialization.jsonObject(with: Data(content.utf8), options: []) as? [String: Any] else {
					throw CocoaError(.propertyListReadCorrupt)
				}
				let data = try JSONSerialization.data(withJSONObject: RemoveOldCommits(obj), options: [])

				// std::exchange(first, false): append a comma for everything after the
				// first, then stop being first.
				if !first {
					str += ","
				}
				first = false

				str += String(data: data, encoding: .utf8) ?? ""
			}
			catch {
				NSLog("%@: %@", bundle.name, error.localizedDescription)
			}
		}
		str += "]}"

		webView.evaluateJavaScript("setJSON(\(javaScriptEscapedString(str)));") { _, _ in }
	}

	@objc func javaScriptEscapedString(_ src: String?) -> String {
		let regex = try! NSRegularExpression(pattern: "['\"\\\\]", options: [])
		var escaped = ""
		if let src {
			escaped = regex.stringByReplacingMatches(in: src, options: [], range: NSRange(location: 0, length: (src as NSString).length), withTemplate: "\\\\$0")
		}
		escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
		return "'\(escaped)'"
	}

	func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
		if let url = navigationAction.request.url, url.scheme != "file", NSWorkspace.shared.open(url) {
			decisionHandler(.cancel)
		}
		else {
			decisionHandler(.allow)
		}
	}

	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		guard message.name == "textmate" else {
			log.error("Message received for unknown message handler: \(message.name, privacy: .public)")
			return
		}

		guard let body = message.body as? [String: Any] else {
			return
		}
		let command = body["command"] as? String
		let payload = body["payload"] as? [String: Any] ?? [:]

		if command == "log" {
			if (payload["level"] as? String) == "error" {
				let jsLog = Logger(subsystem: "com.j23software.JavaScript", category: "error")
				jsLog.error("\(String(describing: payload["filename"]), privacy: .public):\(String(describing: payload["lineno"]), privacy: .public): \(String(describing: payload["message"]), privacy: .public)")
			}
			else {
				let jsLog = Logger(subsystem: "com.j23software.JavaScript", category: "log")
				jsLog.log("\(self.webView.title ?? "", privacy: .public): \(String(describing: payload["message"]), privacy: .public)")
			}
		}
	}
}
