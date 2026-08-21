// The preferences window and its toolbar-driven pane switching.
//
// The Swift type is named PreferencesWindowController, not Preferences: a Swift
// type whose name matches its own module (this target's module is `Preferences`)
// is a recipe for lookup ambiguity. @objc(Preferences) keeps the ObjC runtime
// name that Preferences.h declares and AppController.mm calls.
import AppKit

private let kMASPreferencesFrameTopLeftKey = "MASPreferences Frame Top Left"
private let kMASPreferencesSelectedViewKey = "MASPreferences Selected Identifier View"

// =============================
// = PreferencesViewController =
// =============================

// Not `final`, for the same reason its superclass is not — and here the
// subclasser is **KVO**, not source code. This is the window's
// contentViewController, and +[NSWindow _windowWithContentViewController:] binds
// the window title to it, which makes KVO build an NSKVONotifying_ subclass at
// run time. Against a `final` Swift class that traps inside
// swift_objc_classCopyFixupHandler before the window ever appears.
class PreferencesViewController: OakTransitionViewController {
	var selectedViewIdentifier: String? {
		didSet {
			guard oldValue != selectedViewIdentifier else { return }
			applySelectedViewIdentifier(previous: oldValue)
		}
	}

	override func viewWillAppear() {
		let viewIdentifier = UserDefaults.standard.string(forKey: kMASPreferencesSelectedViewKey)
		selectedViewIdentifier = viewIdentifier ?? children.first?.identifier?.rawValue
	}

	private func applySelectedViewIdentifier(previous: String?) {
		// An editing pane that refuses to commit wins: put the toolbar selection
		// back and undo the change without re-entering this observer.
		if let oldViewController = viewController(forIdentifier: previous), !oldViewController.commitEditing() {
			view.window?.toolbar?.selectedItemIdentifier = oldViewController.identifier.map { NSToolbarItem.Identifier($0.rawValue) }
			return
		}

		guard let identifier = selectedViewIdentifier else { return }

		view.window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(identifier)
		UserDefaults.standard.set(identifier, forKey: kMASPreferencesSelectedViewKey)

		guard let newViewController = viewController(forIdentifier: identifier) else { return }
		title = newViewController.title ?? "Preferences"
		// The window title came from the title binding before; set it directly now.
		view.window?.title = title ?? "Preferences"

		subview = newViewController.view

		let setNewFirstResponder = view.window?.firstResponder === view.window
		view.window?.recalculateKeyViewLoop()
		if setNewFirstResponder, let newKeyView = newViewController.view.nextValidKeyView, newKeyView.isDescendant(of: newViewController.view) {
			view.window?.makeFirstResponder(newKeyView)
		}
	}

	func viewController(forIdentifier identifier: String?) -> NSViewController? {
		guard let identifier else { return nil }
		return children.first { $0.identifier?.rawValue == identifier }
	}
}

// ===============================
// = PreferencesWindowController =
// ===============================

@objc(Preferences) class PreferencesWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
	@objc static let sharedInstance = PreferencesWindowController()

	private let preferencesViewController = PreferencesViewController()

	init() {
		// Deliberately NOT NSPanel(contentViewController:). That setter calls
		// -[NSWindow _bindTitleToContentViewController], which makes KVO build an
		// NSKVONotifying_ subclass of this Swift view controller — and that class copy
		// corrupts the heap, killing the app the moment Settings opens in a Release build
		// (alpha.15 shipped it; see the handoff). Owning the content view directly avoids
		// the binding entirely; the two things the binding gave us — the window title
		// following the pane, and -viewWillAppear firing — are done explicitly below.
		let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
		window.contentView = preferencesViewController.view
		super.init(window: window)

		if let topLeft = UserDefaults.standard.string(forKey: kMASPreferencesFrameTopLeftKey) {
			window.setFrameTopLeftPoint(NSPointFromString(topLeft))
		}

		let viewControllers: [NSViewController] = [
			FilesPreferences(),
			ProjectsPreferences(),
			BundlesPreferences(),
			VariablesPreferences(),
			SoftwareUpdatePreferences(),
			TerminalPreferences(),
		]

		for viewController in viewControllers {
			preferencesViewController.addChild(viewController)
		}

		let toolbar = NSToolbar(identifier: "Preferneces")
		toolbar.allowsUserCustomization = false
		toolbar.delegate = self

		let hasToolbarImages = viewControllers.contains { $0.responds(to: #selector(getter: PreferencesPane.toolbarItemImage)) }
		toolbar.displayMode = hasToolbarImages ? .iconAndLabel : .labelOnly

		window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
		window.delegate = self
		window.hidesOnDeactivate = false
		window.toolbar = toolbar
		window.toolbarStyle = .preference
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported — Preferences is a singleton built in code")
	}

	// AppKit called -viewWillAppear itself while the panel owned a contentViewController;
	// it is the hook that restores the last selected pane, so drive it on show.
	override func showWindow(_ sender: Any?) {
		preferencesViewController.viewWillAppear()
		super.showWindow(sender)
	}

	func windowDidMove(_ notification: Notification) {
		guard let frame = window?.frame else { return }
		UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: frame.minX, y: frame.maxY)), forKey: kMASPreferencesFrameTopLeftKey)
	}

	private func selectView(atRelativeOffset offset: Int) {
		guard let toolbar = window?.toolbar else { return }
		let identifiers = toolbarSelectableItemIdentifiers(toolbar).map(\.rawValue)
		guard !identifiers.isEmpty else { return }

		if let selected = preferencesViewController.selectedViewIdentifier, let index = identifiers.firstIndex(of: selected) {
			preferencesViewController.selectedViewIdentifier = identifiers[(index + identifiers.count + offset) % identifiers.count]
		} else {
			preferencesViewController.selectedViewIdentifier = offset < 0 ? identifiers.last : identifiers.first
		}
	}

	@objc func selectNextTab(_ sender: Any?)     { selectView(atRelativeOffset: +1) }
	@objc func selectPreviousTab(_ sender: Any?) { selectView(atRelativeOffset: -1) }

	@objc func updateShowTabMenu(_ menu: NSMenu) {
		guard isWindowLoaded, window?.isKeyWindow == true else { return }

		let selectedIdentifier = preferencesViewController.selectedViewIdentifier

		for (i, viewController) in preferencesViewController.children.enumerated() {
			let keyEquivalent = i < 9 ? String(UnicodeScalar(UInt8(UInt8(ascii: "1") + UInt8(i)))) : ""
			let item = menu.addItem(withTitle: viewController.title ?? "", action: #selector(takeSelectedViewControllerIdentifierFrom(_:)), keyEquivalent: keyEquivalent)
			item.representedObject = viewController.identifier?.rawValue
			item.target = self
			if viewController.identifier?.rawValue == selectedIdentifier {
				item.state = .on
			}
		}
	}

	@objc func takeSelectedViewControllerIdentifierFrom(_ sender: Any?) {
		if let toolbarItem = sender as? NSToolbarItem {
			preferencesViewController.selectedViewIdentifier = toolbarItem.itemIdentifier.rawValue
		} else if let menuItem = sender as? NSMenuItem, let identifier = menuItem.representedObject as? String {
			preferencesViewController.selectedViewIdentifier = identifier
		}
	}

	// ====================
	// = Toolbar Delegate =
	// ====================

	func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
		let res = NSToolbarItem(itemIdentifier: itemIdentifier)
		res.action = #selector(takeSelectedViewControllerIdentifierFrom(_:))
		res.target = self

		if let viewController = preferencesViewController.viewController(forIdentifier: itemIdentifier.rawValue) {
			res.label = viewController.title ?? ""
			if let pane = viewController as? PreferencesPaneProtocol {
				res.image = pane.toolbarItemImage ?? nil
			}
		}

		return res
	}

	func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		preferencesViewController.children.compactMap { $0.identifier.map { NSToolbarItem.Identifier($0.rawValue) } }
	}

	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		toolbarAllowedItemIdentifiers(toolbar)
	}

	func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		toolbarAllowedItemIdentifiers(toolbar)
	}
}
