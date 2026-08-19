import AppKit

// The Bundle Editor window: an NSBrowser over the bundle tree on the left, the
// selected item's body in a text view below it, and that item's properties in a
// pane on the right.
//
// This was the framework the roadmap called second-worst in the tree, and the
// reason was never its size — it was that its state was C++: a be::entry_t
// browser tree, a std::map<bundles::item_ptr, plist::dictionary_t> of pending
// edits, and bundles::item_ptr for the selection. TMBundleItem and BEEntry are
// what made it portable; what genuinely could not move is in BEInterop.mm.

@MainActor
@objc(BundleEditor)
class BundleEditor: NSWindowController {
	@objc static let sharedInstance = BundleEditor()

	// MARK: - Item kinds

	// Per-kind facts the editor needs: which plist key holds the body, what
	// grammar to edit it with, which property xib to show. The ObjC++ table had
	// an eighth `kind_string` field that nothing ever read; it is not carried
	// over.
	private struct ItemInfo {
		let kind: TMBundleItemKind
		let plistKey: String?       // nil where the body is a subset of keys, not one
		let grammar: String?
		let fileType: String
		let scope: String
		let viewController: String? // nil where the kind has no extra property pane
		let file: String            // template resource, menu title, and icon name
	}

	private static let itemInfos: [ItemInfo] = [
		ItemInfo(kind: .bundle,      plistKey: "description", grammar: "text.html.basic",                fileType: "tmBundle",      scope: "attr.bundle-editor.bundle",       viewController: "BundleProperties",   file: "Bundle"),
		ItemInfo(kind: .command,     plistKey: "command",     grammar: nil,                              fileType: "tmCommand",     scope: "attr.bundle-editor.command",      viewController: "CommandProperties",  file: "Command"),
		ItemInfo(kind: .dragCommand, plistKey: "command",     grammar: nil,                              fileType: "tmDragCommand", scope: "attr.bundle-editor.command.drop", viewController: "FileDropProperties", file: "Drag Command"),
		ItemInfo(kind: .snippet,     plistKey: "content",     grammar: "text.tm-snippet",                fileType: "tmSnippet",     scope: "attr.bundle-editor.snippet",      viewController: "SnippetProperties",  file: "Snippet"),
		ItemInfo(kind: .settings,    plistKey: "settings",    grammar: "source.plist.textmate.settings", fileType: "tmPreferences", scope: "attr.bundle-editor.settings",     viewController: nil,                  file: "Settings"),
		ItemInfo(kind: .grammar,     plistKey: nil,           grammar: "source.plist.textmate.grammar",  fileType: "tmLanguage",    scope: "attr.bundle-editor.grammar",      viewController: "GrammarProperties",  file: "Grammar"),
		ItemInfo(kind: .proxy,       plistKey: "content",     grammar: "text.plain",                     fileType: "tmProxy",       scope: "attr.bundle-editor.proxy",        viewController: nil,                  file: "Proxy"),
		ItemInfo(kind: .theme,       plistKey: nil,           grammar: "source.plist",                   fileType: "tmTheme",       scope: "attr.bundle-editor.theme",        viewController: "ThemeProperties",    file: "Theme"),
		ItemInfo(kind: .macro,       plistKey: "commands",    grammar: "source.plist",                   fileType: "tmMacro",       scope: "attr.bundle-editor.macro",        viewController: "MacroProperties",    file: "Macro"),
	]

	// Kinds whose body is itself a property list rather than plain text.
	private static let plistItemKinds: Set<TMBundleItemKind> = [ .settings, .macro, .theme ]

	private static func info(for kind: TMBundleItemKind) -> ItemInfo? {
		return itemInfos.first { $0.kind == kind }
	}

	// MARK: - State

	private var bundlesRoot: BEEntry = BEEntry.bundlesRoot

	// Was std::map<bundles::item_ptr, plist::dictionary_t>. Keyed on the item,
	// which works because TMBundleItem is interned and NSCopying — that
	// requirement is why the wrapper is a reference type at all.
	private var changes: [TMBundleItem: [AnyHashable: Any]] = [:]

	private var bundleItem: TMBundleItem?
	private var bundleItemContent: OakDocument?
	private var propertiesChanged = false

	private var browser: NSBrowser!
	@objc private(set) var documentView: OakDocumentView!

	private var maxLabelWidth: CGFloat = 0
	private var minPropertiesViewWidth: CGFloat = 0

	private var browserViewControllerStorage: NSViewController?
	private var documentViewControllerStorage: NSViewController?
	private var splitViewControllerStorage: NSSplitViewController?
	private var propertiesViewController: NSViewController!
	private var propertiesHeightConstraint: NSLayoutConstraint!
	private var windowSplitViewControllerStorage: NSSplitViewController?

	private var sharedPropertiesViewController: PropertiesViewController?
	private var extraPropertiesViewController: PropertiesViewController?

	private var bundleItemProperties: NSMutableDictionary? {
		willSet { stopObserving(bundleItemProperties) }
		didSet {
			startObserving(bundleItemProperties)
			propertiesChanged = false
		}
	}

	// MARK: - Lifecycle

	@objc init() {
		super.init(window: nil)

		// Was a bundles::callback_t subclass, which Swift cannot express;
		// TMBundleModel owns the one subscriber and re-broadcasts.
		//
		// The selector form rather than the block form on purpose: a block
		// observer hands back a token that has to be removed by hand, and under
		// Swift 6 a @MainActor class cannot touch its own state from deinit to do
		// it — the problem CommitWindow solved with an explicit teardown call.
		// A selector observer is unregistered automatically when the observer
		// deallocates, so there is nothing to tear down.
		NotificationCenter.default.addObserver(self, selector: #selector(didChangeBundleItems), name: .TMBundleItemsDidChange, object: nil)

		window = NSWindow(contentViewController: windowSplitViewController)
		window?.delegate = self

		if let visible = window?.screen?.visibleFrame {
			window?.setFrame(visible.insetBy(dx: max(0, ((visible.width - 1200) / 2).rounded()),
			                                 dy: max(0, ((visible.height - 700) / 2).rounded())), display: false)
		}
		windowFrameAutosaveName = "Bundle Editor"

		splitViewController.splitView.setPosition((splitViewController.splitView.frame.height / 3).rounded(), ofDividerAt: 0)
		splitViewController.splitView.autosaveName = "Bundle Editor"

		windowSplitViewController.splitView.setPosition(windowSplitViewController.splitView.frame.width - minPropertiesViewWidth, ofDividerAt: 0)
		windowSplitViewController.splitView.autosaveName = "Bundle Editor Properties"

		browser.loadColumnZero()
		window?.makeFirstResponder(browser)
	}

	required init?(coder: NSCoder) {
		fatalError("BundleEditor is not restorable from a coder")
	}

	// MARK: - View construction

	private var browserViewController: NSViewController {
		if let browserViewControllerStorage { return browserViewControllerStorage }

		let controller = NSViewController(nibName: nil, bundle: nil)
		let browser = NSBrowser(frame: .zero)
		browser.autoresizingMask = [.width, .height]
		controller.view = browser

		browser.isTitled = false
		browser.autohidesScroller = true
		browser.hasHorizontalScroller = true
		browser.columnResizingType = .userColumnResizing
		browser.setDefaultColumnWidth(180)
		browser.columnsAutosaveName = "OakBundleEditorBrowserColumnWidths"
		browser.delegate = self
		browser.target = self
		browser.action = #selector(browserSelectionDidChange(_:))

		self.browser = browser
		browserViewControllerStorage = controller
		return controller
	}

	private var documentViewController: NSViewController {
		if let documentViewControllerStorage { return documentViewControllerStorage }

		let view = OakDocumentView(frame: .zero)
		// The text view's delegate is C++-typed (-variables returns std::map), so
		// the Swift controller cannot conform. Nothing in the Bundle Editor needs
		// that method, and -scopeAttributes is reached through the responder
		// chain, so leaving the delegate unset costs nothing here.
		documentView = view

		let controller = NSViewController(nibName: nil, bundle: nil)
		controller.view = view
		documentViewControllerStorage = controller
		return controller
	}

	private var splitViewController: NSSplitViewController {
		if let splitViewControllerStorage { return splitViewControllerStorage }

		let controller = NSSplitViewController()
		controller.splitView.isVertical = false
		controller.splitView.dividerStyle = .paneSplitter

		controller.addSplitViewItem(NSSplitViewItem(viewController: browserViewController))
		controller.addSplitViewItem(NSSplitViewItem(viewController: documentViewController))

		controller.splitViewItems[0].minimumThickness = 50
		controller.splitViewItems[0].canCollapse = true

		splitViewControllerStorage = controller
		return controller
	}

	private var windowSplitViewController: NSSplitViewController {
		if let windowSplitViewControllerStorage { return windowSplitViewControllerStorage }

		// Every property pane is instantiated once up front purely to measure it:
		// the properties column is sized to fit the widest of them, and their
		// labels are aligned to a common gutter.
		var maxWidth: CGFloat = 0
		var maxLabelWidth: CGFloat = 0
		for name in [ "SharedProperties", "BundleProperties", "CommandProperties", "FileDropProperties", "SnippetProperties", "GrammarProperties", "ThemeProperties", "MacroProperties" ] {
			guard let controller = PropertiesViewController(name: name) else { continue }
			let view = controller.view
			maxWidth = max(maxWidth, view.frame.width - controller.labelWidth)
			maxLabelWidth = max(maxLabelWidth, controller.labelWidth)
		}

		self.maxLabelWidth = maxLabelWidth
		minPropertiesViewWidth = maxLabelWidth + maxWidth

		let propertiesController = NSViewController()
		propertiesController.view = NSView(frame: .zero)
		propertiesController.view.widthAnchor.constraint(greaterThanOrEqualToConstant: minPropertiesViewWidth).isActive = true
		propertiesHeightConstraint = propertiesController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 0)
		propertiesViewController = propertiesController

		let controller = NSSplitViewController()
		controller.splitView.isVertical = true
		controller.addSplitViewItem(NSSplitViewItem(viewController: splitViewController))
		controller.addSplitViewItem(NSSplitViewItem(viewController: propertiesController))
		controller.splitViewItems[0].holdingPriority = NSLayoutConstraint.Priority(rawValue: NSLayoutConstraint.Priority.defaultLow.rawValue - 1)

		windowSplitViewControllerStorage = controller
		return controller
	}

	// Read through the responder chain by OakTextView to scope the editor's own
	// key bindings to the kind of item being edited.
	@objc var scopeAttributes: String? {
		guard let bundleItem, bundleItemContent != nil else { return nil }
		return BundleEditor.info(for: bundleItem.kind)?.scope
	}

	// MARK: - Reacting to change

	@objc private func didChangeBundleItems() {
		// Remember the selection by identifier, not by object: the tree is
		// rebuilt wholesale, so none of the entries survive — which is exactly
		// why BEEntry is not interned.
		var selection: [String] = []
		var entry = bundlesRoot
		for column in 0...max(0, browser.lastColumn) {
			let row = browser.selectedRow(inColumn: column)
			guard row >= 0, row < entry.children.count else { break }
			entry = entry.children[row]
			if let identifier = entry.identifier {
				selection.append(identifier)
			}
		}

		bundlesRoot = BEEntry.bundlesRoot
		browser.loadColumnZero()

		entry = bundlesRoot
		for (column, identifier) in selection.enumerated() {
			guard let row = entry.children.firstIndex(where: { $0.identifier == identifier }) else { break }
			browser.selectRow(row, inColumn: column)
			entry = entry.children[row]
		}
	}

	private func didChangeModifiedState() {
		let edited = bundleItem.map { changes[$0] != nil || propertiesChanged || (bundleItemContent?.isDocumentEdited ?? false) } ?? false
		setDocumentEdited(edited)
	}

	// MARK: - Actions

	private func createItem(ofKind kind: TMBundleItemKind) {
		guard let info = BundleEditor.info(for: kind),
		      let path = Bundle(for: BundleEditor.self).path(forResource: info.file, ofType: "plist"),
		      let template = NSDictionary(contentsOfFile: path) as? [String: Any]
		else { return }

		let row = browser.selectedRow(inColumn: 0)
		let bundle: TMBundleItem? = row >= 0 && row < bundlesRoot.children.count ? bundlesRoot.children[row].representedItem : nil
		guard kind == .bundle || bundle != nil else { return }

		var properties = BEExpandVariables(template, BEDefaultTemplateVariables()) as? [String: Any] ?? [:]
		if properties["name"] == nil {
			properties["name"] = "untitled"
		}

		let item = TMBundleItem.createItem(of: kind, inBundle: kind == .bundle ? nil : bundle, properties: properties)
		changes[item] = item.properties
		revealItem(item)
		didChangeModifiedState()
	}

	@objc func newDocument(_ sender: Any?) {
		let menu = NSMenu(title: "Item Types")
		let creatable: Set<TMBundleItemKind> = [ .bundle, .command, .dragCommand, .snippet, .settings, .grammar, .proxy, .theme ]
		for info in BundleEditor.itemInfos where creatable.contains(info.kind) {
			menu.addItem(withTitle: info.file, action: nil, keyEquivalent: "").tag = Int(info.kind.rawValue)
		}

		let alert = NSAlert()
		alert.messageText = "Create New Item"
		alert.informativeText = "Please choose what you want to create:"
		alert.addButton(withTitle: "Create")
		alert.addButton(withTitle: "Cancel")

		let typeChooser = NSPopUpButton(frame: .zero, pullsDown: false)
		typeChooser.menu = menu
		typeChooser.sizeToFit()
		alert.accessoryView = typeChooser

		guard let window else { return }
		alert.beginSheetModal(for: window) { [weak self] response in
			guard response == .alertFirstButtonReturn, let tag = typeChooser.selectedItem?.tag else { return }
			// The tag is the kind's raw value, round-tripped through NSInteger.
			// Validated rather than force-converted: an out-of-range raw value is
			// undefined behaviour for an imported NS_ENUM, not a caught error.
			guard tag > 0, let kind = TMBundleItemKind(rawValue: UInt(tag)) else { return }
			self?.createItem(ofKind: kind)
		}
		alert.window.recalculateKeyViewLoop()
		alert.window.makeFirstResponder(typeChooser)
	}

	@objc func delete(_ sender: Any?) {
		guard let trashedItem = bundleItem, trashedItem.moveToTrash() else { return }
		OakPlayUISound(OakSoundDidTrashItemUISound)

		// Pick the next selection before the item leaves the index, and skip the
		// menu scaffolding — selecting a separator would leave the editor with
		// nothing to show.
		var newSelectedItem: TMBundleItem?
		var foundItem = false
		if let siblings = parentEntry(forColumn: browser.selectedColumn)?.children {
			for entry in siblings {
				guard let item = entry.representedItem else { continue }
				if item.uuidString == trashedItem.uuidString {
					foundItem = true
				} else if item.kind != .menu && item.kind != .menuItemSeparator {
					newSelectedItem = item
				}
				if foundItem, newSelectedItem != nil { break }
			}
		}

		if let newSelectedItem {
			revealItem(newSelectedItem)
		}

		changes.removeValue(forKey: trashedItem)
		trashedItem.removeFromIndex()
		didChangeModifiedState()

		if let first = trashedItem.paths.first {
			var itemFolder = (first as NSString).deletingLastPathComponent
			if trashedItem.kind == .bundle && trashedItem.paths.count == 1 {
				itemFolder = (itemFolder as NSString).deletingLastPathComponent
			}
			BundlesManager.sharedInstance.reloadPath(itemFolder)
		}
	}

	@objc func revealItem(_ item: TMBundleItem?) {
		guard let item else { return }

		showWindow(self)
		setBundleItem(item)

		// An item with no file on disk has never been saved, so it counts as a
		// pending change the moment it is revealed.
		if item.paths.isEmpty {
			if changes[item] == nil {
				changes[item] = item.properties
			}
			didChangeModifiedState()
		}

		let target = item.bundle ?? item
		guard let bundleRow = bundlesRoot.children.firstIndex(where: { $0.representedItem == target }) else { return }
		browser.selectRow(bundleRow, inColumn: 0)

		// Depth-first walk to the item, selecting the path taken. Written
		// recursively rather than as the ObjC++'s explicit stack of
		// (children, index) pairs — same traversal, and no signed/unsigned
		// comparison to get wrong.
		var path: [Int] = []
		func find(in entry: BEEntry) -> Bool {
			for (index, child) in entry.children.enumerated() {
				if child.hasChildren {
					path.append(index)
					if find(in: child) { return true }
					path.removeLast()
				} else if child.representedItem == item {
					path.append(index)
					return true
				}
			}
			return false
		}

		if find(in: bundlesRoot.children[bundleRow]) {
			for (depth, row) in path.enumerated() {
				browser.selectRow(row, inColumn: depth + 1)
			}
		}
	}

	// MARK: - Editing

	// Not an override: -commitEditing is the informal NSEditorRegistration
	// protocol, which NSWindowController does not declare, so this is the
	// implementation AppKit looks up by selector.
	@discardableResult
	@objc func commitEditing() -> Bool {
		guard let bundleItem, let bundleItemContent, let info = BundleEditor.info(for: bundleItem.kind) else { return true }

		sharedPropertiesViewController?.commitEditing()
		extraPropertiesViewController?.commitEditing()

		guard propertiesChanged || bundleItemContent.isDocumentEdited else { return true }

		guard let properties = (bundleItemProperties?.mutableCopy() as? NSMutableDictionary) else { return true }
		let content = bundleItemContent.content ?? ""

		// A body that is itself a property list has to parse before it can be
		// stored, and a parse failure must not silently discard the edit.
		var parsedContent: Any?
		if info.plistKey == nil || BundleEditor.plistItemKinds.contains(info.kind) {
			guard let parsed = BEObjectFromPlistString(content) else {
				let alert = NSAlert()
				alert.messageText = "Error Parsing Property List"
				alert.informativeText = "The property list is not valid.\n\nUnfortunately I am presently unable to point to where the parser failed."
				alert.addButton(withTitle: "OK")
				if let window { alert.beginSheetModal(for: window) { _ in } }
				return false
			}
			parsedContent = parsed
		}

		if let plistKey = info.plistKey {
			if BundleEditor.plistItemKinds.contains(info.kind) {
				properties[plistKey] = parsedContent
			} else {
				properties[plistKey] = content
			}
		} else if let subset = parsedContent as? [String: Any] {
			// A grammar or theme keeps only a named subset of keys in its body;
			// a key absent from the edited text has been deleted, not left alone.
			for key in BundleEditor.bodyKeys(for: info.kind) {
				if let value = subset[key] {
					properties[key] = value
				} else {
					properties.removeObject(forKey: key)
				}
			}
		}

		// The two multi-valued fields are edited through a table, so they come
		// back as an array of one-key dictionaries rather than as plain strings.
		switch info.kind {
			case .grammar:    properties["fileTypes"] = BundleEditor.unwrap(properties["fileTypes"], key: "extension")
			case .dragCommand: properties["draggedFileExtensions"] = BundleEditor.unwrap(properties["draggedFileExtensions"], key: "extension")
			default:          break
		}

		if bundleItem.storedPropertiesEqual(properties as! [AnyHashable: Any]) {
			changes.removeValue(forKey: bundleItem)
		} else {
			changes[bundleItem] = properties as! [AnyHashable: Any]
		}

		propertiesChanged = false
		bundleItemContent.markSaved()
		didChangeModifiedState()
		return true
	}

	@objc func saveDocument(_ sender: Any?) {
		commitEditing()

		var failedToSave: [TMBundleItem: [AnyHashable: Any]] = [:]
		for (item, properties) in changes {
			item.properties = properties
			// -save exactly once per item: it writes to disk, so folding the
			// path lookup into the same condition would run it a second time
			// for any item that saved but reported no path.
			if item.save() {
				if let path = item.paths.first {
					BundlesManager.sharedInstance.reloadPath(path)
				}
			} else {
				failedToSave[item] = properties
			}
		}
		changes = failedToSave

		if !changes.isEmpty {
			let alert = NSAlert()
			alert.messageText = "Error Saving Bundle Item"
			alert.informativeText = "Sorry, but something went wrong while trying to save your changes. More info may be available via the console."
			alert.addButton(withTitle: "OK")
			if let window { alert.beginSheetModal(for: window) { _ in } }
		}

		didChangeModifiedState()
	}

	// The keys a grammar or theme edits as its body. Everything else lives in
	// the properties pane.
	private static func bodyKeys(for kind: TMBundleItemKind) -> [String] {
		switch kind {
			case .grammar: return [ "comment", "patterns", "repository", "injections" ]
			case .theme:   return [ "gutterSettings", "settings", "colorSpaceName" ]
			default:       return []
		}
	}

	private static func wrap(_ values: [String], key: String) -> NSMutableArray {
		let res = NSMutableArray()
		for value in values {
			res.add(NSMutableDictionary(dictionary: [ key: value ]))
		}
		return res
	}

	private static func unwrap(_ array: Any?, key: String) -> [String] {
		guard let rows = array as? [[String: Any]] else { return [] }
		return rows.compactMap { $0[key] as? String }
	}

	// MARK: - Selection

	@objc func browserSelectionDidChange(_ sender: Any?) {
		let column = browser.selectedColumn
		guard column >= 0 else { return }
		let row = browser.selectedRow(inColumn: column)
		guard row >= 0 else { return }

		guard let entry = parentEntry(forColumn: column), row < entry.children.count,
		      let item = entry.children[row].representedItem
		else { return }

		// Menus and separators are structure, not editable items.
		if item.kind != .menu && item.kind != .menuItemSeparator {
			setBundleItem(item)
		}
	}

	// The entry whose children fill `column`, found by walking the selected row
	// of each column before it.
	//
	// The ObjC++ spelled this `for(size_t col = 0; col < aColumn; ++col)` with
	// aColumn an NSInteger — so a column of -1 (which -selectedColumn returns
	// with nothing selected) converted to SIZE_MAX and the loop only survived by
	// bailing out on the first row lookup. In Swift that range is a trap, so the
	// guard is explicit.
	private func parentEntry(forColumn column: Int) -> BEEntry? {
		guard column >= 0 else { return nil }

		var entry = bundlesRoot
		for col in 0..<column {
			let row = browser.selectedRow(inColumn: col)
			guard row >= 0, row < entry.children.count else { return nil }
			entry = entry.children[row]
		}
		return entry
	}

	// MARK: - Property observation

	private static let bindingKeys = [
		"isDisabled", "name", "keyEquivalent", "tabTrigger", "scope", "semanticClass",
		"contentMatch", "hideFromUser", "draggedFileExtensions", "fileTypes",
		"firstLineMatch", "scopeName", "injectionSelector",
		"beforeRunningCommand", "input", "inputFormat", "outputLocation", "outputFormat",
		"outputCaret", "autoScrollOutput", "contactName", "contactEmailRot13",
		"description", "disableAutoIndent", "useGlobalClipboard", "author", "comment",
	]

	private func startObserving(_ properties: NSMutableDictionary?) {
		guard let properties else { return }
		for key in BundleEditor.bindingKeys {
			properties.addObserver(self, forKeyPath: key, options: [], context: nil)
		}
	}

	private func stopObserving(_ properties: NSMutableDictionary?) {
		guard let properties else { return }
		for key in BundleEditor.bindingKeys {
			properties.removeObserver(self, forKeyPath: key)
		}
	}

	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		if keyPath != "documentEdited" {
			propertiesChanged = true
		}
		didChangeModifiedState()
	}

	// MARK: - Showing an item

	private func editableProperties(of item: TMBundleItem) -> NSMutableDictionary {
		let res = NSMutableDictionary(dictionary: item.properties)

		switch item.kind {
			case .command:
				// The six popups are derived from the parsed command rather than
				// read straight out of the plist, because a v1 command expresses
				// them differently and has to be converted first.
				let popups = BECommandPopupValues(item)
				res.removeObject(forKey: "output")
				res.removeObject(forKey: "dontFollowNewOutput")
				res["version"] = 2
				if let autoScroll = popups["autoScrollOutput"] as? Bool, autoScroll {
					res["autoScrollOutput"] = true
				}
				for key in [ "beforeRunningCommand", "input", "inputFormat", "outputLocation", "outputFormat", "outputCaret" ] {
					res[key] = popups[key]
				}

			case .grammar:
				res["fileTypes"] = BundleEditor.wrap(item.values(forField: "fileTypes"), key: "extension")

			case .dragCommand:
				res["draggedFileExtensions"] = BundleEditor.wrap(item.values(forField: "draggedFileExtensions"), key: "extension")

			default:
				break
		}

		return res
	}

	private func editableProperties(pending: [AnyHashable: Any], of item: TMBundleItem) -> NSMutableDictionary {
		let res = NSMutableDictionary(dictionary: pending)

		switch item.kind {
			case .grammar:     res["fileTypes"] = BundleEditor.wrap(item.values(forField: "fileTypes"), key: "extension")
			case .dragCommand: res["draggedFileExtensions"] = BundleEditor.wrap(item.values(forField: "draggedFileExtensions"), key: "extension")
			default:           break
		}

		return res
	}

	private func setBundleItem(_ newItem: TMBundleItem) {
		guard bundleItem != newItem else { return }

		commitEditing()

		if let bundleItemContent {
			bundleItemContent.removeObserver(self, forKeyPath: "documentEdited")
		}

		bundleItem = newItem
		bundleItemContent = nil

		let pending = changes[newItem]
		bundleItemProperties = pending.map { editableProperties(pending: $0, of: newItem) } ?? editableProperties(of: newItem)

		guard let info = BundleEditor.info(for: newItem.kind) else { return }

		window?.title = newItem.nameWithBundle ?? ""
		let title = newItem.name ?? ""

		if newItem.paths.count == 1 {
			window?.representedURL = URL(fileURLWithPath: newItem.paths[0])
		} else {
			window?.representedFilename = NSHomeDirectory()
			window?.standardWindowButton(.documentIconButton)?.image = NSWorkspace.shared.icon(forFileType: info.fileType)
		}

		let properties = (pending as? [String: Any]) ?? (newItem.properties as? [String: Any]) ?? [:]

		if let plistKey = info.plistKey {
			if BundleEditor.plistItemKinds.contains(info.kind) {
				if let value = properties[plistKey] {
					bundleItemContent = OakDocument(string: BEPlistString(value), fileType: info.grammar, customName: title)
				}
			} else if var body = properties[plistKey] as? String {
				if info.kind == .command || info.kind == .dragCommand {
					body = BEFixShebang(body)
				}
				bundleItemContent = OakDocument(string: body, fileType: info.grammar, customName: title)
			}
		} else {
			var subset: [String: Any] = [:]
			for key in BundleEditor.bodyKeys(for: info.kind) {
				if let value = properties[key] {
					subset[key] = value
				}
			}
			bundleItemContent = OakDocument(string: BEPlistString(subset as NSDictionary), fileType: info.grammar, customName: title)
		}

		// Always a document, even for a kind whose body key is absent — the text
		// view must have something to show, and an empty one is what the ObjC++
		// fell back to.
		guard let content = bundleItemContent ?? OakDocument(string: "", fileType: nil, customName: title) else { return }
		bundleItemContent = content
		documentView.document = content
		content.addObserver(self, forKeyPath: "documentEdited", options: [], context: nil)

		layoutPropertyPanes(for: info)
	}

	private func layoutPropertyPanes(for info: ItemInfo) {
		propertiesHeightConstraint.isActive = false
		propertiesViewController.view.subviews.forEach { $0.removeFromSuperview() }

		sharedPropertiesViewController = nil
		extraPropertiesViewController = nil

		let contentView = propertiesViewController.view
		var maxY = contentView.frame.height

		// Everything but a bundle carries the shared properties (name, key
		// equivalent, scope selector…) above its kind-specific pane.
		if info.kind != .bundle, let controller = PropertiesViewController(name: "SharedProperties") {
			controller.properties = bundleItemProperties ?? NSMutableDictionary()
			sharedPropertiesViewController = controller
			maxY = add(controller, to: contentView, below: maxY)
		}

		if let name = info.viewController, let controller = PropertiesViewController(name: name) {
			controller.properties = bundleItemProperties ?? NSMutableDictionary()
			extraPropertiesViewController = controller
			maxY = add(controller, to: contentView, below: maxY)
		}

		propertiesHeightConstraint.constant = contentView.frame.height + -maxY

		// The panes did not fit: grow the window downwards rather than clipping.
		if maxY < 0, let window = contentView.window {
			var frame = window.frame.offsetBy(dx: 0, dy: maxY)
			frame.size.height += -maxY
			window.setFrame(frame, display: true, animate: true)
		}

		propertiesHeightConstraint.isActive = true
	}

	private func add(_ controller: PropertiesViewController, to contentView: NSView, below maxY: CGFloat) -> CGFloat {
		let view = controller.view
		let top = maxY - view.frame.height
		let indent = maxLabelWidth - controller.labelWidth
		view.frame = NSRect(x: indent, y: top, width: contentView.frame.width - indent, height: view.frame.height)
		contentView.addSubview(view)
		return top
	}
}

// MARK: - NSBrowserDelegate

extension BundleEditor: NSBrowserDelegate {
	func browser(_ sender: NSBrowser, numberOfRowsInColumn column: Int) -> Int {
		guard let entry = parentEntry(forColumn: column), entry.hasChildren else { return 0 }
		return entry.children.count
	}

	func browser(_ sender: NSBrowser, willDisplayCell cell: Any, atRow row: Int, column: Int) {
		guard let cell = cell as? NSBrowserCell,
		      let parent = parentEntry(forColumn: column), row < parent.children.count
		else { return }

		let entry = parent.children[row]

		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.lineBreakMode = .byTruncatingTail

		cell.attributedStringValue = NSAttributedString(string: entry.name ?? "", attributes: [
			.foregroundColor: entry.isDisabled ? NSColor.tertiaryLabelColor : NSColor.controlTextColor,
			.paragraphStyle: paragraphStyle,
		])
		cell.isLeaf = !entry.hasChildren
		cell.isLoaded = true

		let menu = NSMenu()
		if let item = entry.representedItem {
			let imageName = entry.identifier == "Menu Actions" ? "MenuItem" : (BundleEditor.info(for: item.kind)?.file ?? "")
			if let srcImage = NSImage(named: imageName, inSameBundleAsClass: BundleEditor.self) {
				// Two points of leading padding, drawn rather than inset, because
				// NSBrowserCell gives an image no margin of its own.
				cell.image = NSImage(size: NSSize(width: srcImage.size.width + 2, height: srcImage.size.height), flipped: false) { dstRect in
					srcImage.draw(in: NSRect(x: dstRect.minX + 2, y: dstRect.minY, width: dstRect.width - 2, height: dstRect.height),
					              from: .zero, operation: .copy, fraction: 1)
					return true
				}
			}

			if entry.identifier == "Menu Actions" {
				return
			}

			if item.kind == .bundle {
				let menuItem = menu.addItem(withTitle: "Export Bundle…", action: #selector(exportBundle(_:)), keyEquivalent: "")
				menuItem.target = self
				menuItem.representedObject = item.uuidString
			}

			let paths = item.paths
			if paths.count == 1 {
				menu.addItem(menuItem(forPath: paths[0]))
			} else if paths.count > 1 {
				let submenu = NSMenu()
				for path in paths {
					let item = menuItem(forPath: path)
					item.title = (path as NSString).abbreviatingWithTildeInPath
					submenu.addItem(item)
				}
				menu.addItem(withTitle: "Show in Finder", action: nil, keyEquivalent: "").submenu = submenu
			}

			let menuItem = menu.addItem(withTitle: "Copy UUID", action: #selector(copyUUID(_:)), keyEquivalent: "")
			menuItem.target = self
			menuItem.representedObject = item.uuidString
		} else if let path = entry.representedPath {
			cell.image = TMFileReference.image(for: URL(fileURLWithPath: path), size: NSSize(width: 16, height: 16))
			menu.addItem(menuItem(forPath: path))
		}

		cell.menu = menu
	}

	private func menuItem(forPath path: String) -> NSMenuItem {
		let displayName = FileManager.default.displayName(atPath: path)
		let item = NSMenuItem(title: "Show “\(displayName)” in Finder", action: #selector(showInFinder(_:)), keyEquivalent: "")
		item.target = self
		item.representedObject = path
		return item
	}

	@objc private func copyUUID(_ sender: NSMenuItem) {
		guard let uuid = sender.representedObject as? String else { return }
		NSPasteboard.general.declareTypes([ .string ], owner: nil)
		NSPasteboard.general.setString(uuid, forType: .string)
	}

	@objc private func showInFinder(_ sender: NSMenuItem) {
		guard let path = sender.representedObject as? String else { return }
		NSWorkspace.shared.activateFileViewerSelecting([ URL(fileURLWithPath: path) ])
	}

	@objc private func exportBundle(_ sender: NSMenuItem) {
		guard let uuid = sender.representedObject as? String,
		      let bundle = TMBundleItem.item(uuidString: uuid),
		      let window
		else { return }

		// A bundle name becomes a directory name, so the two characters that
		// would change the path's meaning are replaced rather than escaped.
		let name = (bundle.name ?? "").replacingOccurrences(of: "/", with: ":").replacingOccurrences(of: ".", with: "_")

		let savePanel = NSSavePanel()
		savePanel.nameFieldStringValue = name + ".tmbundle"
		savePanel.beginSheetModal(for: window) { result in
			guard result == .OK, let path = savePanel.url?.standardizedFileURL.path else { return }

			if FileManager.default.fileExists(atPath: path) {
				do {
					try FileManager.default.removeItem(atPath: path)
				} catch {
					window.presentError(error)
					return
				}
			}

			var everythingSaved = true
			let exportable = TMBundleItemKind(rawValue: ~(TMBundleItemKind.menu.rawValue | TMBundleItemKind.menuItemSeparator.rawValue))!
			for item in TMBundleItem.items(inBundle: bundle, ofKinds: exportable) {
				everythingSaved = item.save(toDirectory: path) && everythingSaved
			}

			if !everythingSaved {
				let alert = NSAlert()
				alert.messageText = "Failed to Save Bundle"
				alert.informativeText = "Unknown error while saving bundle as “\((path as NSString).abbreviatingWithTildeInPath)”."
				alert.addButton(withTitle: "OK")
				alert.runModal()
			}
		}
	}
}

// MARK: - NSWindowDelegate

extension BundleEditor: NSWindowDelegate {
	func window(_ window: NSWindow, shouldDragDocumentWith event: NSEvent, from dragImageLocation: NSPoint, with pasteboard: NSPasteboard) -> Bool {
		return bundleItem?.paths.count == 1
	}

	func window(_ window: NSWindow, shouldPopUpDocumentPathMenu menu: NSMenu) -> Bool {
		guard let paths = bundleItem?.paths, !paths.isEmpty else { return false }
		if paths.count == 1 { return true }

		menu.removeAllItems()
		for path in paths {
			let item = menuItem(forPath: path)
			item.title = (path as NSString).abbreviatingWithTildeInPath
			item.state = .off
			menu.addItem(item)
		}
		return true
	}

	func windowShouldClose(_ sender: NSWindow) -> Bool {
		commitEditing()
		if changes.isEmpty { return true }

		let alert = NSAlert()
		alert.alertStyle = .warning
		alert.messageText = descriptionForChanges()
		alert.informativeText = "Your changes will be lost if you don’t save them."
		alert.addButton(withTitle: "Save")
		alert.addButton(withTitle: "Cancel")
		alert.addButton(withTitle: "Don’t Save")

		guard let window else { return true }
		alert.beginSheetModal(for: window) { [weak self] response in
			guard let self, response != .alertSecondButtonReturn else { return } // not Cancel
			if response == .alertFirstButtonReturn {
				self.saveDocument(self)
			} else if response == .alertThirdButtonReturn {
				self.changes.removeAll()
			}
			self.close()
		}
		return false
	}

	private func descriptionForChanges() -> String {
		guard changes.count == 1, let item = changes.keys.first else {
			return "Do you want to save the changes made to \(changes.count) items?"
		}

		let name = item.name ?? ""
		if item.kind == .bundle {
			return "Do you want to save the changes made to the bundle named “\(name)”?"
		}

		let bundleName = item.bundle?.name ?? ""
		let type = (BundleEditor.info(for: item.kind)?.file ?? "").lowercased()
		return "Do you want to save the changes made to the \(type) item named “\(name)” in the “\(bundleName)” bundle?"
	}
}
