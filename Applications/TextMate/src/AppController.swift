import AppKit
import os

// Ported from AppController.mm — the application delegate, and the last large
// piece of the app shell.
//
// MainMenu.xib instantiates this class by name and wires NSApplication.delegate
// to it, which is why it is `@objc(AppController)` and not final (rule 49). Its
// ObjC face is the hand declaration in AppController.h (rule 23), kept out of
// TextMate-Bridging-Header.h where it would collide with the generated
// TextMate-Swift.h (rule 43). `AppController Commands.mm` imports that header
// unchanged and still compiles a category onto this class.
//
// **What did not come across, and why.** `AppController Commands.mm` stays
// ObjC++ permanently: `-performBundleItem:` takes a `bundles::item_ptr` and is
// *called* with one by DocumentWindowController and OakTextView, so it is
// C++-typed on both sides and no boundary file helps (rule 37).
//
// The five `find::options_t` cases in -validateMenuItem: are literals here for
// the same reason MainMenu.swift's Find tags are: <regexp/find.h> is a C++
// namespace the importer drops. They are pinned by static_assert in
// t_app_controller.mm, which is where the corresponding menu tags are pinned
// too, so a renumbering fails the build rather than silently mis-routing.
//
// NSApplicationDelegate is adopted explicitly, where the ObjC declared only
// <NSMenuDelegate> and let AppKit find the rest by -respondsToSelector:. That is
// the same set of methods, with the compiler now checking the signatures — the
// rule-18 failure it removes is a delegate callback that is silently never
// called because its selector drifted by one colon.

private let log = Logger(subsystem: "com.j23software.TextMate-NG", category: "swift-interop")

// Was a file-scope C++ function in AppController.mm. Swift can call a global but
// can never export one (rule 19), and after the flip every caller is Swift — the
// two here and the three in AppControllerDocuments.swift — so it needs no ObjC
// declaration at all and OakOpenDocuments.h is gone.
@MainActor
func OakOpenDocuments(_ paths: [String], treatFilePackageAsFolder: Bool = false) {
	let bundleExtensions = ["tmbundle", "tmcommand", "tmdragcommand", "tmlanguage", "tmmacro", "tmpreferences", "tmsnippet", "tmtheme"]

	var documents: [OakDocument] = []
	var itemsToInstall: [String] = []
	var plugInsToInstall: [String] = []
	let enableInstallHandler = treatFilePackageAsFolder == false && !NSEvent.modifierFlags.contains(.option)

	for path in paths {
		var isDirectory: ObjCBool = false
		let pathExt = (path as NSString).pathExtension.lowercased()
		if enableInstallHandler && bundleExtensions.contains(pathExt) {
			itemsToInstall.append(path)
		} else if enableInstallHandler && pathExt == "tmplugin" {
			plugInsToInstall.append(path)
		} else if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue {
			OakDocumentController.sharedInstance.showFileBrowser(atPath: path)
		} else {
			documents.append(OakDocumentController.sharedInstance.document(withPath: path))
		}
	}

	if !itemsToInstall.isEmpty {
		BundlesManager.sharedInstance.installBundleItems(atPaths: itemsToInstall)
	}

	for path in plugInsToInstall {
		TMPlugInController.sharedInstance.installPlugIn(atPath: path)
	}

	OakDocumentController.sharedInstance.showDocuments(documents)
}

@MainActor
private func HasDocumentWindow(_ windows: [NSWindow]) -> Bool {
	for window in windows where window.delegate is DocumentWindowController {
		return true
	}
	return false
}

// @MainActor is not a new constraint, it is the one this class always had:
// MainMenu.xib instantiates it on the main thread, AppKit calls every delegate
// method there, and every API it touches is main-thread-only. Saying so is what
// lets Swift 6 accept passing `self` to -showWindow: and friends.
@MainActor
@objc(AppController)
class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation, @preconcurrency OakUserDefaultsObserver {
	// MBCreateMenu wrote these four through `NSMenu* __strong*` out-parameters
	// while it built; the Swift builder hands them back instead. -menuNeedsUpdate:
	// dispatches on their identity, which is why the comparisons in
	// AppControllerMenus.swift are `===` and not `==`.
	var bundlesMenu: NSMenu?
	var themesMenu: NSMenu?
	var spellingMenu: NSMenu?
	var wrapColumnMenu: NSMenu?

	@IBOutlet var goToLinePanel: NSPanel!
	@IBOutlet var goToLineTextField: NSTextField!

	private var didFinishLaunching = false

	// Was a @property with a hand-written setter; the early return is not an
	// optimisation, it is what keeps the key-equivalent shuffle below from running
	// on every -applicationDidUpdate:.
	private var _keyWindowHasBackAndForwardActions = false
	private var keyWindowHasBackAndForwardActions: Bool {
		get { _keyWindowHasBackAndForwardActions }
		set {
			guard _keyWindowHasBackAndForwardActions != newValue else { return }
			_keyWindowHasBackAndForwardActions = newValue

			let textMenu        = NSApp.mainMenu?.item(withTitle: "Text")?.submenu
			let fileBrowserMenu = NSApp.mainMenu?.item(withTitle: "File Browser")?.submenu

			func itemWithAction(_ menu: NSMenu?, _ action: Selector) -> NSMenuItem? {
				guard let menu else { return nil }
				let index = menu.indexOfItem(withTarget: nil, andAction: action)
				return index == -1 ? nil : menu.items[index]
			}

			let backMenuItem       = itemWithAction(fileBrowserMenu, Selector(("goBack:")))
			let forwardMenuItem    = itemWithAction(fileBrowserMenu, Selector(("goForward:")))
			let shiftLeftMenuItem  = itemWithAction(textMenu,        Selector(("shiftLeft:")))
			let shiftRightMenuItem = itemWithAction(textMenu,        Selector(("shiftRight:")))

			guard let backMenuItem, let forwardMenuItem, let shiftLeftMenuItem, let shiftRightMenuItem else { return }

			for menuItem in [backMenuItem, forwardMenuItem, shiftLeftMenuItem, shiftRightMenuItem] {
				menuItem.keyEquivalent = ""
			}

			let leftItem  = newValue ? backMenuItem : shiftLeftMenuItem
			let rightItem = newValue ? forwardMenuItem : shiftRightMenuItem
			leftItem.keyEquivalent = "["
			leftItem.keyEquivalentModifierMask = .command
			rightItem.keyEquivalent = "]"
			rightItem.keyEquivalentModifierMask = .command
		}
	}

	// MARK: - Menus

	@objc func mainMenu() -> NSMenu {
		// Read the display name from CFBundleName rather than spelling it out here, so
		// the fork's name lives in exactly one place. Note this is deliberately not
		// ${TARGET_NAME}: the target (and therefore CFBundleExecutable) stays
		// "TextMate", only the user-visible name is TextMate-NG.
		let appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "TextMate"

		let menu = OakMainMenu(title: "AMainMenu")
		let refs = TMMenus.buildMainMenu(into: menu, target: self, appName: appName)

		bundlesMenu    = refs.bundlesMenu
		themesMenu     = refs.themesMenu
		spellingMenu   = refs.spellingMenu
		wrapColumnMenu = refs.wrapColumnMenu

		// The delegates are assigned afterwards exactly as before —
		// MBCreateMenuItem set a submenu's delegate from the item's own `.delegate`,
		// which is nil for all four.
		bundlesMenu?.delegate    = self
		themesMenu?.delegate     = self
		spellingMenu?.delegate   = self
		wrapColumnMenu?.delegate = self
		return menu
	}

	func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
		return TMMenus.dockMenu(target: self)
	}

	// MARK: - Application delegate

	func applicationDidUpdate(_ notification: Notification) {
		var foundBackAndForwardActions = false
		var responder = NSApp.keyWindow?.firstResponder
		while let current = responder, !foundBackAndForwardActions {
			if current.responds(to: Selector(("shiftLeft:"))) {
				break
			} else if current.responds(to: Selector(("goBack:"))) {
				foundBackAndForwardActions = true
			}
			responder = current.nextResponder
		}
		keyWindowHasBackAndForwardActions = foundBackAndForwardActions
	}

	@objc func userDefaultsDidChange(_ aNotification: Notification!) {
		let disableRmate    = UserDefaults.standard.bool(forKey: kUserDefaultsDisableRMateServerKey)
		let rmateInterface  = UserDefaults.standard.string(forKey: kUserDefaultsRMateServerListenKey)
		let rmatePort       = UserDefaults.standard.integer(forKey: kUserDefaultsRMateServerPortKey)
		setup_rmate_server(!disableRmate, UInt16(truncatingIfNeeded: rmatePort), rmateInterface == kRMateServerListenRemote)
	}

	func applicationWillFinishLaunching(_ notification: Notification) {
		// First, because it used to run at nib-load time — see the note on the method.
		AppController.setupThemeDefaultsAndObservers()

		NSApp.mainMenu = mainMenu()

		// SoftwareUpdate.sharedInstance.channels is deliberately left unconfigured
		// (Phase 2.5, 2026-07-26): these previously resolved against MacroMates'
		// api.textmate.org/releases — this fork's own TextMate-NG. "Check for
		// updates" now surfaces a clear "No channel named …" error instead of
		// silently offering the wrong product's releases. Wire this back up once a
		// J23-owned update feed exists; SoftwareUpdate.mm's checkForTestBuild: does
		// the lookup by name against whatever channels dict is set here.

		AppControllerSupport.setupSettingsPaths()

		UserDefaults.standard.register(defaults: [
			"NSRecentDocumentsLimit": 25,
			"WebKitDeveloperExtras":  true,
		])
		RegisterDefaults()

		TMPlugInController.sharedInstance.loadAllPlugIns(nil)

		AppControllerSupport.installDefaultBundlesIfNeeded()
		BundlesManager.sharedInstance.loadBundlesIndex()

		var restoreSession = !UserDefaults.standard.bool(forKey: kUserDefaultsDisableSessionRestoreKey)
		if restoreSession {
			let prematureTerminationDuringRestore = AppControllerSupport.sessionRestoreMarkerPath

			var promptUser: String? = nil
			if AppControllerSupport.markerExists(atPath: prematureTerminationDuringRestore) {
				promptUser = "Previous attempt of restoring your session caused an abnormal exit. Would you like to skip session restore?"
			} else if NSEvent.modifierFlags.contains(.shift) {
				promptUser = "By holding down shift (⇧) you have indicated that you wish to disable restoring the documents which were open in last session."
			}

			if let promptUser {
				let alert = NSAlert()
				alert.messageText     = "Disable Session Restore?"
				alert.informativeText = promptUser
				// -addButtons: is an ObjC variadic and therefore uncallable from Swift
				// (rule 16). This is the same three-line loop six other ported files
				// already spell out for the same reason.
				for title in ["Restore Documents", "Disable"] {
					alert.addButton(withTitle: title)
				}
				if alert.runModal() == .alertSecondButtonReturn { // "Disable"
					restoreSession = false
				}
			}

			if restoreSession {
				AppControllerSupport.createMarker(atPath: prematureTerminationDuringRestore)
				_ = DocumentWindowController.restoreSession()
			}
			AppControllerSupport.removeMarker(atPath: prematureTerminationDuringRestore)
		}
	}

	func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
		return didFinishLaunching
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		NSWindow.allowsAutomaticWindowTabbing = false

		NSApp.isAutomaticCustomizeTouchBarMenuItemEnabled = true

		if !HasDocumentWindow(NSApp.orderedWindows) {
			let disableUntitledAtStartupPrefs = UserDefaults.standard.bool(forKey: kUserDefaultsDisableNewDocumentAtStartupKey)
			let showFavoritesInsteadPrefs     = UserDefaults.standard.bool(forKey: kUserDefaultsShowFavoritesInsteadOfUntitledKey)

			if showFavoritesInsteadPrefs {
				openFavorites(self)
			} else if !disableUntitledAtStartupPrefs {
				newDocument(self)
			}
		}

		userDefaultsDidChange(nil) // setup mate/rmate server
		OakObserveUserDefaults(self)

		let selectMenu = NSApp.mainMenu?.item(withTitle: "Edit")?.submenu?.item(withTitle: "Select")?.submenu
		selectMenu?.item(withTitle: "Toggle Column Selection")?.setActivationString("⌥", with: nil)

		TerminalPreferences.updateMateIfRequired()
		AboutWindowController.showChangesIfUpdated()

		CrashReporter.sharedInstance.applicationDidFinishLaunching(notification)
		// Uploading is deliberately disabled (Phase 2.5, 2026-07-26): `REST_API` here
		// resolves to MacroMates' api.textmate.org, and this call defaulted to
		// enabled — most users would never see the opt-out checkbox in Preferences
		// before their first crash silently uploaded to a company this fork isn't
		// affiliated with. Re-enable once a J23-owned collector exists, by restoring
		// `[CrashReporter.sharedInstance postNewCrashReportsToURLString:...]` pointed
		// at it. macOS's own system crash reporting is unaffected either way.

		_ = OakCommitWindowServer.sharedInstance // Setup server

		// Phase 3 proof-of-life: the first Swift↔ObjC↔C++ round trip, once per
		// launch. Logged rather than shown — it proves the interop toolchain without
		// changing behavior. Remove once real Swift code exists (Phase 4).
		log.log("\(SwiftInterop.interopDescription(), privacy: .public)")

		didFinishLaunching = true
	}

	func applicationWillResignActive(_ notification: Notification) {
		AppControllerSupport.disableSCM()
	}

	func applicationWillBecomeActive(_ notification: Notification) {
		AppControllerSupport.enableSCM()
	}

	func applicationDidResignActive(_ notification: Notification) {
		// If the window to activate, when switching back to TextMate, has "Move to
		// Active Space" set, then the system will move this window to the current
		// space. This is not what we want for auxillary windows like the Find dialog
		// or HTML output, as these windows are tied to a document window.
		//
		// Starting with macOS 10.11 we have to change collection behavior after the
		// current event loop cycle, both when receiving the did become and did resign
		// active notification.

		// dispatch_async on the main queue, not a Task: "after the current event loop
		// cycle" above is the whole point, and a Task hop is not the same thing.
		// MainActor.assumeIsolated is sound for the same reason — this body only ever
		// runs on the main queue — and is what lets the NSWindow list, which is not
		// Sendable, be read back inside the become-active observer.
		DispatchQueue.main.async {
			MainActor.assumeIsolated {
				nonisolated(unsafe) var changedWindows: [NSWindow] = []
				for window in NSApp.windows {
					let both: NSWindow.CollectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
					if window.collectionBehavior.intersection(both) == both {
						window.collectionBehavior.remove(.moveToActiveSpace)
						changedWindows.append(window)
					}
				}

				if !changedWindows.isEmpty {
					nonisolated(unsafe) var token: NSObjectProtocol?
					token = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: nil) { _ in
						if let token { NotificationCenter.default.removeObserver(token) }
						DispatchQueue.main.async {
							MainActor.assumeIsolated {
								for window in changedWindows {
									window.collectionBehavior.insert(.moveToActiveSpace)
								}
							}
						}
					}
				}
			}
		}
	}

	// =========================
	// = Past Startup Delegate =
	// =========================

	@IBAction func newDocumentAndActivate(_ sender: Any?) {
		NSApp.activate(ignoringOtherApps: true)
		newDocument(sender)
	}

	@IBAction func openDocumentAndActivate(_ sender: Any?) {
		NSApp.activate(ignoringOtherApps: true)
		openDocument(sender)
	}

	@IBAction func orderFrontAboutPanel(_ sender: Any?) {
		AboutWindowController.sharedInstance.showAboutWindow(self)
	}

	@IBAction func orderFrontFindPanel(_ sender: Any?) {
		// `Find.sharedInstance` imports as an optional: Find.h carries no nullability
		// annotation (rule 44). Messaging nil was a no-op in the original, and the
		// optional binding is the same thing said out loud.
		guard let find = Find.sharedInstance else { return }
		// `[sender respondsToSelector:@selector(tag)]` in the original: the sender is
		// a menu item for the three Find entries and `self` for everything else.
		let mode = (sender as AnyObject?)?.responds(to: #selector(getter: NSMenuItem.tag)) == true
			? ((sender as? NSMenuItem)?.tag ?? FFSearchTarget.document.rawValue)
			: FFSearchTarget.document.rawValue

		switch mode {
			case FFSearchTarget.document.rawValue:  find.searchTarget = .document
			case FFSearchTarget.selection.rawValue: find.searchTarget = .selection
			case FFSearchTarget.project.rawValue:   find.searchTarget = .project
			case FFSearchTarget.other.rawValue:     return find.showFolderSelectionPanel(self)
			default: break
		}
		find.showWindow(self)
	}

	@IBAction func orderFrontGoToLinePanel(_ sender: Any?) {
		// KVC rather than a cast: the original messaged whatever -targetForAction:
		// returned, which is an OakTextView today but is not typed as one here or
		// there. Assigning nil to -stringValue would raise, so the optional binding
		// also removes a latent crash on a target whose selection is unset.
		if let target = NSApp.target(forAction: Selector(("selectionString"))) as AnyObject?,
		   let selection = target.value(forKey: "selectionString") as? String {
			goToLineTextField.stringValue = selection
		}
		goToLinePanel.makeKeyAndOrderFront(self)
	}

	@IBAction func performGoToLine(_ sender: Any?) {
		goToLinePanel.orderOut(self)
		NSApp.sendAction(Selector(("selectAndCenter:")), to: nil, from: goToLineTextField.stringValue)
	}

	@IBAction func performSoftwareUpdateCheck(_ sender: Any?) {
		SoftwareUpdate.sharedInstance.checkForUpdate(self)
	}

	@IBAction func showPreferences(_ sender: Any?) {
		Preferences.sharedInstance.showWindow(self)
	}

	@IBAction func showBundleEditor(_ sender: Any?) {
		BundleEditor.sharedInstance.showWindow(self)
	}

	@IBAction func openFavorites(_ sender: Any?) {
		guard let chooser = FavoriteChooser.sharedInstance else { return }
		chooser.action = #selector(didSelectFavorite(_:))
		chooser.showWindow(self)
	}

	@objc func didSelectFavorite(_ sender: Any?) {
		var paths: [String] = []
		for item in (sender as? OakChooser)?.selectedItems ?? [] {
			if let path = (item as AnyObject).value(forKey: "path") as? String {
				paths.append(path)
			}
		}
		OakOpenDocuments(paths, treatFilePackageAsFolder: true)
	}

	// =======================
	// = Bundle Item Chooser =
	// =======================

	@IBAction func showBundleItemChooser(_ sender: Any?) {
		guard let chooser = BundleItemChooser.sharedInstance else { return }
		chooser.action     = #selector(bundleItemChooserDidSelectItems(_:))
		chooser.editAction = #selector(editBundleItem(_:))

		let textView = NSApp.target(forAction: Selector(("scopeContext"))) as? NSView
		chooser.scope        = AppControllerSupport.scopeContext(forTarget: textView)
		chooser.hasSelection = AppControllerSupport.targetHasSelection(textView)

		if let controller = NSApp.target(forAction: Selector(("selectedDocument"))) as? DocumentWindowController {
			let doc = controller.selectedDocument
			chooser.path      = doc?.path
			chooser.directory = (doc?.path as NSString?)?.deletingLastPathComponent ?? doc?.directory
		} else {
			chooser.path      = nil
			chooser.directory = nil
		}

		let frame: NSRect
		if let window = textView?.window, let textView {
			frame = window.convertToScreen(textView.convert(textView.visibleRect, to: nil))
		} else {
			frame = NSScreen.main?.visibleFrame ?? .zero
		}
		chooser.showWindowRelative(toFrame: frame)
	}

	@objc func bundleItemChooserDidSelectItems(_ sender: Any?) {
		for item in (sender as? OakChooser)?.selectedItems ?? [] {
			if let uuid = (item as AnyObject).value(forKey: "uuid") {
				NSApp.sendAction(Selector(("performBundleItemWithUUIDStringFrom:")), to: nil, from: ["representedObject": uuid])
			}
		}
	}

	// ===========================
	// = Find options menu items =
	// ===========================

	@IBAction func toggleFindOption(_ sender: Any?) {
		Find.sharedInstance?.takeOptionToToggleFrom(sender)
	}

	func validateMenuItem(_ item: NSMenuItem) -> Bool {
		// find::options_t, which the importer drops with the rest of the namespace.
		// static_assert in t_app_controller.mm pins all five.
		let kFindFullWords         = 1
		let kFindIgnoreCase        = 2
		let kFindIgnoreWhitespace  = 4
		let kFindRegularExpression = 8
		let kFindWrapAround        = 128

		var enabled = true
		if item.action == #selector(toggleFindOption(_:)) {
			if let entry = OakPasteboard.find?.current() {
				var active = false
				switch item.tag {
					case kFindIgnoreCase:        active = UserDefaults.standard.bool(forKey: kUserDefaultsFindIgnoreCase)
					case kFindRegularExpression: active = entry.regularExpression
					case kFindFullWords:         active = entry.fullWordMatch;  enabled = !entry.regularExpression
					case kFindIgnoreWhitespace:  active = entry.ignoreWhitespace; enabled = !entry.regularExpression
					case kFindWrapAround:        active = UserDefaults.standard.bool(forKey: kUserDefaultsFindWrapAround)
					default: break
				}
				item.state = active ? .on : .off
			} else {
				enabled = false
			}
		} else if item.action == #selector(orderFrontGoToLinePanel(_:)) {
			enabled = NSApp.target(forAction: Selector(("setSelectionString:"))) != nil
		} else if item.action == Selector(("performBundleItemWithUUIDStringFrom:")) {
			let keyDelegate = NSApp.keyWindow?.delegate
			let menuItemValidator: Any? = keyDelegate?.responds(to: Selector(("performBundleItem:"))) == true
				? keyDelegate
				: NSApp.target(forAction: Selector(("performBundleItem:")))
			if let validator = menuItemValidator as? NSMenuItemValidation, (validator as AnyObject) !== self {
				enabled = validator.validateMenuItem(item)
			}
		} else {
			enabled = validateThemeMenuItem(item)
		}
		return enabled
	}

	@objc func editBundleItem(_ sender: Any?) {
		let selectedItems = (sender as? OakChooser)?.selectedItems
		assert(selectedItems != nil, "-editBundleItem: sender must respond to -selectedItems")
		assert(selectedItems?.count == 1)

		let last = selectedItems?.last as AnyObject?
		if let uuid = last?.value(forKey: "uuid") as? String {
			BundleEditor.sharedInstance.revealItem(TMBundleItem.item(uuidString: uuid))
		} else if let path = last?.value(forKey: "file") as? String {
			let doc = OakDocumentController.sharedInstance.document(withPath: path)
			let line = last?.value(forKey: "line") as? String

			// Was -showDocument:andSelect:inProject:bringToFront:, whose entire use of
			// its text::range_t is `aDocument.selection = to_ns(range)`. Setting it
			// here and calling the range-free variant — which forwards an undefined
			// range and therefore skips that assignment — is the same two steps in the
			// same order. Same move -handleTxMtURL: already made.
			if let selection = AppControllerSupport.selectionString(forPositionString: line) {
				doc?.selection = selection
			}
			OakDocumentController.sharedInstance.showDocument(doc, inProject: nil, bringToFront: true)
		}
	}

	@objc func editBundleItem(withUUIDString uuidString: String) {
		BundleEditor.sharedInstance.revealItem(TMBundleItem.item(uuidString: uuidString))
	}

	// ============
	// = Printing =
	// ============

	@IBAction func runPageLayout(_ sender: Any?) {
		NSPageLayout().runModal()
	}
}
