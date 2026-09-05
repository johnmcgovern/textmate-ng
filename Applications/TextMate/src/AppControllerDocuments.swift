import AppKit

// Ported from `AppController Documents.mm`, which was already free of C++ before
// the flip — the txmt:// URL handler's text::range_t work moved to
// TxMtURLSupport in an earlier commit.
//
// DidHandleODBEditorEvent is a C function taking `AppleEvent const*`, which the
// importer takes without help (rule 61); ODBEditorSuite.h is in the bridging
// header for it.

extension AppController {
	@objc func newDocument(_ sender: Any?) {
		DocumentWindowController().showWindow(self)
	}

	@objc func newFileBrowser(_ sender: Any?) {
		let urlString = UserDefaults.standard.string(forKey: kUserDefaultsInitialFileBrowserURLKey)
		let url = urlString.flatMap { URL(string: $0) }

		let controller = DocumentWindowController()
		controller.defaultProjectPath = (url?.isFileURL == true) ? url?.path : NSHomeDirectory()
		controller.fileBrowserVisible = true
		controller.showWindow(self)
	}

	@objc func openDocument(_ sender: Any?) {
		let openPanel = NSOpenPanel()
		openPanel.allowsMultipleSelection         = true
		openPanel.canChooseDirectories            = true
		openPanel.canChooseFiles                  = true
		openPanel.treatsFilePackagesAsDirectories = true
		let appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? ProcessInfo.processInfo.processName
		openPanel.title = "\(appName): Open"

		openPanel.setShowsHiddenFilesCheckBox(true)
		if openPanel.runModal() == .OK {
			var filenames: [String] = []
			for url in openPanel.urls {
				if let path = url.standardizedFileURL.path as String? {
					filenames.append(path)
				}
			}

			OakOpenDocuments(filenames)
		}
	}

	func application(_ sender: NSApplication, openFile path: String) -> Bool {
		if !DidHandleODBEditorEvent(NSAppleEventManager.shared().currentAppleEvent?.aeDesc) {
			OakOpenDocuments([path])
		}
		return true
	}

	func application(_ sender: NSApplication, openFiles filenames: [String]) {
		if !DidHandleODBEditorEvent(NSAppleEventManager.shared().currentAppleEvent?.aeDesc) {
			OakOpenDocuments(filenames)
		}
		sender.reply(toOpenOrPrint: .success)
	}

	func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
		if UserDefaults.standard.bool(forKey: kUserDefaultsShowFavoritesInsteadOfUntitledKey) {
			openFavorites(self)
		} else {
			newDocument(self)
		}
		return true
	}

	@objc func handleTxMtURL(_ aURL: URL) {
		guard aURL.host == "open" else {
			let alert = NSAlert()
			alert.messageText     = "Unknown URL Scheme"
			alert.informativeText = "This version of TextMate does not support “\(aURL.host ?? "")” in its URL scheme."
			alert.addButton(withTitle: "Continue")
			alert.runModal()
			return
		}

		let parameters = TxMtURLSupport.parameters(fromQuery: aURL.query)

		let url     = parameters["url"]
		let uuid    = parameters["uuid"]
		let project = parameters["project"]

		// nil exactly when there was no line parameter, which is the
		// `range == text::range_t::undefined` the three branches below used to test.
		let selection = TxMtURLSupport.selectionString(forLine: parameters["line"], column: parameters["column"])

		let projectUUID = project.flatMap { UUID(uuidString: $0) }
		if let url {
			// nil for a url that matches no file:// prefix — the NULL_STR the
			// original carried into path::is_directory and path::exists, which both
			// answer NO for it, and then into the alert, which showed "(null)".
			// Deliberately not guarded here, so that path is unchanged.
			let path = TxMtURLSupport.path(forFileURLString: url)

			if TxMtURLSupport.pathIsDirectory(path ?? "") {
				OakDocumentController.sharedInstance.showFileBrowser(atPath: path ?? "")
			} else if TxMtURLSupport.pathExists(path ?? "") {
				let doc = OakDocumentController.sharedInstance.document(withPath: path ?? "")
				doc?.isRecentTrackingDisabled = true
				if let selection {
					doc?.selection = selection
				}
				OakDocumentController.sharedInstance.showDocument(doc, inProject: projectUUID, bringToFront: true)
			} else {
				let alert = NSAlert()
				alert.messageText     = "File Does not Exist"
				alert.informativeText = "The item “\(path ?? "(null)")” does not exist."
				alert.addButton(withTitle: "Continue")
				alert.runModal()
			}
		} else if let uuid {
			if let identifier = UUID(uuidString: uuid), let doc = OakDocumentController.sharedInstance.findDocument(withIdentifier: identifier) {
				doc.isRecentTrackingDisabled = true
				if let selection {
					doc.selection = selection
				}
				OakDocumentController.sharedInstance.showDocument(doc, inProject: projectUUID, bringToFront: true)
			} else {
				let alert = NSAlert()
				alert.messageText     = "File Does not Exist"
				alert.informativeText = "No document found for UUID \(uuid)."
				alert.addButton(withTitle: "Continue")
				alert.runModal()
			}
		} else if let selection {
			for win in NSApp.orderedWindows {
				var foundTextView = win.firstResponder?.tryToPerform(Selector(("setSelectionString:")), with: selection) ?? false
				if !foundTextView {
					var allViews = win.contentView?.subviews ?? []
					var i = 0
					while i < allViews.count {
						allViews.append(contentsOf: allViews[i].subviews)
						i += 1
					}

					for view in allViews {
						if view.responds(to: Selector(("setSelectionString:"))) {
							view.perform(Selector(("setSelectionString:")), with: selection)
							win.makeFirstResponder(view)
							foundTextView = true
							break
						}
					}
				}

				if foundTextView {
					win.makeKeyAndOrderFront(self)
					break
				}
			}
		} else {
			let alert = NSAlert()
			alert.messageText     = "Missing Parameter"
			alert.informativeText = "You need to provide either a (file) url or line parameter. The URL given was: ‘\(aURL)’."
			alert.addButton(withTitle: "Continue")
			alert.runModal()
		}
	}

	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		let disableUntitledAtReactivationPrefs = UserDefaults.standard.bool(forKey: kUserDefaultsDisableNewDocumentAtReactivationKey)
		let showFavoritesInsteadPrefs          = UserDefaults.standard.bool(forKey: kUserDefaultsShowFavoritesInsteadOfUntitledKey)
		return flag || !disableUntitledAtReactivationPrefs || showFavoritesInsteadPrefs
	}

	// ===========================
	// = Application Termination =
	// ===========================

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		return DocumentWindowController.applicationShouldTerminate(sender)
	}
}
