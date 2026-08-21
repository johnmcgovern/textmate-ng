import AppKit

// Ported from BundleItemChooser.mm (2026-08-21). The ⌃⌘T "Select Bundle Item" panel, and
// the last file in this framework. Its C++ went first, into BundleItemChooserSupport — the
// row model, the gathering that reads the bundle and settings indexes, the menu and
// key-binding scraping, and the ranking — so what is left here is the controller: a
// titlebar that swaps a search field for a key-equivalent recorder, a scope bar over three
// sources, a Search menu over five fields, and Select/Edit buttons whose default-button
// status follows the ⌥ key. Contract pinned by t_bundle_item_chooser.mm (rule 18).
//
// AppController.mm is the only consumer, through the hand-declaration in
// BundleItemChooser.h. The scope arrives as a TMScopeContext (rule 17); the wildcard the
// app passes is deliberate and is not the empty scope — see that header.

// One row's view. The FIXME the ObjC++ carried is still true: the highlight restyle and
// the accessibility children are OakFileTableCellView's, copied rather than shared, and
// unifying them is a separate change from this port.
private class BundleItemTableCellView: NSTableCellView {
	private var contextTextField: NSTextField!
	private var shortcutTextField: NSTextField!

	init() {
		super.init(frame: .zero)

		let imageView = NSImageView()
		imageView.setContentHuggingPriority(.required, for: .horizontal)
		imageView.setContentCompressionResistancePriority(.required, for: .horizontal)

		let textField = OakCreateLabel("", NSFont.systemFont(ofSize: 13), .left, .byTruncatingMiddle)!
		let contextTextField = OakCreateLabel("", NSFont.controlContentFont(ofSize: 10), .left, .byTruncatingMiddle)!

		let shortcutTextField = OakCreateLabel("", NSFont.controlContentFont(ofSize: 13), .left, .byTruncatingMiddle)!
		shortcutTextField.setContentHuggingPriority(.required, for: .horizontal)
		shortcutTextField.setContentCompressionResistancePriority(.required, for: .horizontal)

		let views: [String: NSView] = ["icon": imageView, "name": textField, "context": contextTextField, "shortcut": shortcutTextField]
		OakAddAutoLayoutViewsToSuperview(Array(views.values), self)

		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(4)-[icon]-(4)-[name]-(4)-[shortcut]-(8)-|", options: [], metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:[context]-(8)-|", options: [], metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[name]-(2)-[context]-(5)-|", options: .alignAllLeading, metrics: nil, views: views))

		imageView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
		shortcutTextField.firstBaselineAnchor.constraint(equalTo: textField.firstBaselineAnchor).isActive = true

		self.imageView         = imageView
		self.textField         = textField
		self.contextTextField  = contextTextField
		self.shortcutTextField = shortcutTextField
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override var objectValue: Any? {
		didSet {
			guard let item = objectValue as? ActionItem else {
				return
			}

			imageView?.image           = BundleItemChooserSupport.icon(for: item)
			textField?.objectValue     = item.name
			contextTextField.objectValue = item.path

			var str: Any = ""
			if let keyEquivalent = item.keyEquivalent {
				shortcutTextField.font = NSFont.controlContentFont(ofSize: 0)
				str = BundleItemChooserSupport.attributedString(forEventString: keyEquivalent, font: shortcutTextField.font) ?? ""
			} else if let tabTrigger = item.tabTrigger {
				shortcutTextField.font = NSFont.controlContentFont(ofSize: 10)
				str = tabTrigger + "⇥"
			}
			shortcutTextField.objectValue = str
		}
	}

	private func selectedString(for value: Any?) -> NSAttributedString? {
		let str: NSMutableAttributedString
		if let string = value as? String {
			str = NSMutableAttributedString(string: string)
		} else if let attributed = value as? NSAttributedString, let copy = attributed.mutableCopy() as? NSMutableAttributedString {
			str = copy
		} else {
			return nil
		}

		str.enumerateAttributes(in: NSRange(location: 0, length: str.length), options: .longestEffectiveRangeNotRequired) { attrs, range, _ in
			if attrs[.backgroundColor] != nil {
				str.addAttribute(.backgroundColor, value: NSColor.tmMatchedTextSelectedBackground()!, range: range)
			}
			if attrs[.underlineColor] != nil {
				str.addAttribute(.underlineColor, value: NSColor.tmMatchedTextSelectedUnderline()!, range: range)
			}
		}
		return str
	}

	override var backgroundStyle: NSView.BackgroundStyle {
		didSet {
			if backgroundStyle == .emphasized {
				textField?.objectValue        = selectedString(for: value(forKeyPath: "objectValue.name"))
				contextTextField.textColor    = NSColor(calibratedWhite: 0.9, alpha: 1)
				contextTextField.objectValue  = selectedString(for: value(forKeyPath: "objectValue.path"))
			} else {
				textField?.objectValue        = value(forKeyPath: "objectValue.name")
				contextTextField.textColor    = NSColor(calibratedWhite: 0.5, alpha: 1)
				contextTextField.objectValue  = value(forKeyPath: "objectValue.path")
			}
		}
	}

	@available(macOS, deprecated: 10.10)
	override func accessibilityAttributeValue(_ attribute: NSAccessibility.Attribute) -> Any? {
		if attribute == .children {
			return MainActor.assumeIsolated {
				[textField?.cell, imageView?.cell, contextTextField.cell, shortcutTextField.cell].compactMap { $0 }
			}
		}
		return super.accessibilityAttributeValue(attribute)
	}
}

@objc(BundleItemChooser)
class BundleItemChooser: OakChooser {
	@objc static let sharedInstance = BundleItemChooser()

	// Classic KVO on the recorder's `recording`, matching the base's arrangement: the base
	// registers self for "firstResponder" and this override forwards anything else to it,
	// which only works while both use the classic callback. Same one-byte allocation trick
	// OakChooser uses for a stable context address.
	nonisolated(unsafe) private static let recordingObserverContext = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

	private var titlebarView: NSView!
	private var actionsPopUpButton: NSPopUpButton!
	private var scopeBar: OakScopeBarViewController!
	private var topDivider: NSView!
	private var bottomDivider: NSView!
	private var selectButton: NSButton!
	private var editButton: NSButton!
	private var layoutConstraints: [NSLayoutConstraint] = []
	private var sourceListLabels: [String] = []

	private var unfilteredItemsCache: [ActionItem]?
	private var eventMonitor: Any?

	@objc var path: String?
	@objc var directory: String?
	@objc var editAction: Selector?

	@objc var scope: TMScopeContext? {
		didSet {
			unfilteredItemsCache = nil
			updateItems(self)
		}
	}

	@objc var hasSelection = false {
		didSet {
			guard hasSelection != oldValue else { return }
			unfilteredItemsCache = nil
			updateItems(self)
		}
	}

	@objc override init() {
		super.init()

		tableView.rowHeight = 38

		sourceListLabels = ["Actions", "Settings", "Other"]
		bundleItemFieldStorage = kBundleItemTitleField
		searchSourceStorage    = kSearchSourceActionItems | kSearchSourceMenuItems | kSearchSourceKeyBindingItems

		window?.title = "Select Bundle Item"

		actionsPopUpButton = OakCreateActionPopUpButton(true /* bordered */)
		let actionMenu = actionsPopUpButton.menu!
		actionMenu.addItem(withTitle: "Placeholder", action: nil, keyEquivalent: "")

		let fields: [(title: String, tag: UInt)] = [
			("Title",          kBundleItemTitleField),
			("Key Equivalent", kBundleItemKeyEquivalentField),
			("Tab Trigger",    kBundleItemTabTriggerField),
			("Semantic Class", kBundleItemSemanticClassField),
			("Scope Selector", kBundleItemScopeSelectorField),
		]

		var key: UInt8 = 0

		actionMenu.addItem(withTitle: "Search", action: #selector(nop(_:)), keyEquivalent: "")
		for info in fields {
			let equivalent: String
			if key < 2 {
				key += 1
				equivalent = String(UnicodeScalar(UInt8(ascii: "0") + key % 10))
			} else {
				equivalent = ""
			}
			let item = actionMenu.addItem(withTitle: info.title, action: #selector(takeBundleItemFieldFrom(_:)), keyEquivalent: equivalent)
			item.indentationLevel = 1
			item.tag = Int(info.tag)
		}

		actionMenu.addItem(NSMenuItem.separator())
		let allScopesEquivalent: String
		if key < 9 {
			key += 1
			allScopesEquivalent = String(UnicodeScalar(UInt8(ascii: "0") + key % 10))
		} else {
			allScopesEquivalent = ""
		}
		actionMenu.addItem(withTitle: "Search All Scopes", action: #selector(toggleSearchAllScopes(_:)), keyEquivalent: allScopesEquivalent)

		scopeBar = OakScopeBarViewController()
		scopeBar.labels = sourceListLabels

		topDivider    = OakCreateNSBoxSeparator()
		bottomDivider = OakCreateNSBoxSeparator()

		selectButton             = OakCreateButton("Select")
		selectButton.font        = NSFont.messageFont(ofSize: NSFont.systemFontSize(for: .small))
		selectButton.controlSize = .small
		selectButton.target      = self
		selectButton.action      = #selector(accept(_:))

		editButton             = OakCreateButton("Edit")
		editButton.font        = NSFont.messageFont(ofSize: NSFont.systemFontSize(for: .small))
		editButton.controlSize = .small
		editButton.target      = self
		editButton.action      = #selector(editItem(_:))

		let titlebarViews: [String: NSView] = [
			"searchField": keyEquivalentInput ? keyEquivalentView : searchField,
			"actions":     actionsPopUpButton,
			"dividerView": topDivider,
			"scopeBar":    scopeBar.view,
		]

		titlebarView = NSView(frame: .zero)
		OakAddAutoLayoutViewsToSuperview(Array(titlebarViews.values), titlebarView)
		setupLayoutConstraints()

		addTitlebarAccessoryView(titlebarView)

		let footerViews: [String: NSView] = [
			"dividerView": bottomDivider,
			"status":      statusTextField,
			"edit":        editButton,
			"select":      selectButton,
		]

		let footer = footerView
		OakAddAutoLayoutViewsToSuperview(Array(footerViews.values), footer)

		footer.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[dividerView]|", options: [], metrics: nil, views: footerViews))
		footer.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(24)-[status]-(>=0)-[edit]-[select]-|", options: .alignAllCenterY, metrics: nil, views: footerViews))
		footer.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[dividerView(==1)]-(4)-[select]-(5)-|", options: [], metrics: nil, views: footerViews))

		updateScrollViewInsets()

		OakSetupKeyViewLoop([searchField, actionsPopUpButton, scopeBar.view, editButton, selectButton])
		window?.initialFirstResponder = searchField

		scopeBar.bind(.value, to: self, withKeyPath: "sourceIndex", options: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(windowDidChangeKeyStatus(_:)), name: NSWindow.didBecomeKeyNotification, object: window)
		NotificationCenter.default.addObserver(self, selector: #selector(windowDidChangeKeyStatus(_:)), name: NSWindow.didResignKeyNotification, object: window)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
		MainActor.assumeIsolated {
			_keyEquivalentView?.removeObserver(self, forKeyPath: "recording", context: Self.recordingObserverContext)
			scopeBar?.unbind(.value)
		}
	}

	@objc private func nop(_ sender: Any?) {}

	@objc private func windowDidChangeKeyStatus(_ notification: Notification?) {
		updateDefaultButton(NSApp.currentEvent)
		if NSApp.keyWindow == window {
			eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
				MainActor.assumeIsolated {
					self?.updateDefaultButton(event)
				}
				return event
			}
		} else if let monitor = eventMonitor {
			NSEvent.removeMonitor(monitor)
			eventMonitor = nil
		}
	}

	// The ObjC++ kept this as a block so the notification handler and the event monitor
	// shared one body; a method is the same thing without the capture question.
	private func updateDefaultButton(_ event: NSEvent?) {
		let isKeyWindow = NSApp.keyWindow == window
		let optionDown  = event.map { $0.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option } ?? false
		window?.defaultButtonCell = canEdit() && (!canAccept() || (optionDown && isKeyWindow)) ? editButton.cell as? NSButtonCell : selectButton.cell as? NSButtonCell
	}

	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		if context == Self.recordingObserverContext {
			let isRecording = change?[.newKey] as? NSNumber
			drawTableViewAsHighlighted = !(isRecording?.boolValue ?? false)
		} else {
			super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)

			if let view = _keyEquivalentView, !view.recording, keyPath == "firstResponder" {
				let oldIsKeyEquivalentView = (change?[.oldKey] as? NSObject) === view
				let newIsKeyEquivalentView = (change?[.newKey] as? NSObject) === view
				if oldIsKeyEquivalentView != newIsKeyEquivalentView {
					drawTableViewAsHighlighted = newIsKeyEquivalentView
				}
			}
		}
	}

	private func setupLayoutConstraints() {
		let titlebarViews: [String: NSView] = [
			"searchField": keyEquivalentInput ? keyEquivalentView : searchField,
			"actions":     actionsPopUpButton,
			"dividerView": topDivider,
			"scopeBar":    scopeBar.view,
		]

		var constraints: [NSLayoutConstraint] = []
		constraints += NSLayoutConstraint.constraints(withVisualFormat: "H:|-(8)-[searchField(>=50)]-[actions]-(8)-|", options: .alignAllCenterY, metrics: nil, views: titlebarViews)
		constraints += NSLayoutConstraint.constraints(withVisualFormat: "H:|[dividerView]|", options: [], metrics: nil, views: titlebarViews)
		constraints += NSLayoutConstraint.constraints(withVisualFormat: "H:|-(8)-[scopeBar]-(>=8)-|", options: [], metrics: nil, views: titlebarViews)
		constraints += NSLayoutConstraint.constraints(withVisualFormat: "V:|-(4)-[searchField]-(8)-[dividerView(==1)]-(4)-[scopeBar]-(4)-|", options: [], metrics: nil, views: titlebarViews)
		titlebarView.addConstraints(constraints)
		layoutConstraints = constraints
	}

	override func showWindow(_ sender: Any?) {
		bundleItemField = kBundleItemTitleField
		if tableView.numberOfRows > 0 {
			tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
			tableView.scrollRowToVisible(0)
		}
		super.showWindow(sender)
	}

	func windowWillClose(_ notification: Notification) {
		unfilteredItemsCache = nil
		items = []
	}

	@objc var sourceIndex: UInt = 0 {
		didSet {
			switch sourceIndex {
				case 0:  searchSource = kSearchSourceActionItems | kSearchSourceMenuItems | kSearchSourceKeyBindingItems
				case 1:  searchSource = kSearchSourceSettingsItems
				case 2:  searchSource = kSearchSourceGrammarItems | kSearchSourceThemeItems
				default: break
			}
		}
	}

	override func keyDown(with event: NSEvent) {
		let res = OakPerformTableViewActionFromKeyEvent(tableView, event)
		if res == OakPerformTableViewActionResult.moveAcceptReturn.rawValue {
			performDefaultButtonClick(self)
		} else if res == OakPerformTableViewActionResult.moveCancelReturn.rawValue {
			cancel(self)
		}
	}

	private var _keyEquivalentView: OakKeyEquivalentView?
	private var keyEquivalentView: OakKeyEquivalentView {
		if let view = _keyEquivalentView {
			return view
		}
		let view = OakKeyEquivalentView(frame: .zero)
		view.translatesAutoresizingMaskIntoConstraints = false
		view.bind(.value, to: self, withKeyPath: "keyEquivalentString", options: nil)
		view.addObserver(self, forKeyPath: "recording", options: .new, context: Self.recordingObserverContext)
		view.setAccessibilitySharedFocusElements([tableView])
		_keyEquivalentView = view
		return view
	}

	private func replaceView(_ oldView: NSView, with newView: NSView) {
		let next = oldView.nextKeyView
		let prev = oldView.previousKeyView

		let contentView = oldView.superview
		oldView.removeFromSuperview()

		contentView?.addSubview(newView)

		prev?.nextKeyView = newView
		newView.nextKeyView = next

		newView.window?.initialFirstResponder = newView
		newView.window?.makeFirstResponder(newView)
	}

	@objc var keyEquivalentInput = false {
		didSet {
			guard keyEquivalentInput != oldValue else { return }

			let contentView = titlebarView
			contentView?.removeConstraints(layoutConstraints)
			layoutConstraints = []

			if keyEquivalentInput {
				replaceView(searchField, with: keyEquivalentView)
			} else {
				replaceView(keyEquivalentView, with: searchField)
			}

			setupLayoutConstraints()

			keyEquivalentView.eventString = nil
			keyEquivalentView.recording   = keyEquivalentInput

			updateItems(self)
		}
	}

	@objc var searchAllScopes = false

	@objc private func toggleSearchAllScopes(_ sender: Any?) {
		searchAllScopes = !searchAllScopes
		unfilteredItemsCache = nil
		updateItems(self)
	}

	@objc var keyEquivalentString: String? {
		didSet {
			guard keyEquivalentString != oldValue else { return }
			updateItems(self)
		}
	}

	// Backing storage kept explicit for the two fields whose setters run before init has
	// finished configuring the panel; assigning the property there would fire didSet.
	private var bundleItemFieldStorage: UInt = 0
	@objc var bundleItemField: UInt {
		get { bundleItemFieldStorage }
		set {
			guard bundleItemFieldStorage != newValue else { return }
			bundleItemFieldStorage = newValue
			keyEquivalentInput = bundleItemFieldStorage == kBundleItemKeyEquivalentField
			filterString = nil
			updateItems(self)
		}
	}

	private var searchSourceStorage: UInt = 0
	@objc var searchSource: UInt {
		get { searchSourceStorage }
		set {
			guard searchSourceStorage != newValue else { return }
			searchSourceStorage = newValue
			unfilteredItemsCache = nil
			updateItems(self)
		}
	}

	@objc private func takeBundleItemFieldFrom(_ sender: Any?) {
		if let item = sender as? NSMenuItem {
			bundleItemField = UInt(item.tag)
		}
	}

	override func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard let identifier = tableColumn?.identifier else {
			return nil
		}

		var res = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
		if res == nil {
			let cellView = BundleItemTableCellView()
			cellView.identifier = identifier
			res = cellView
		}

		res?.objectValue = items[row]
		return res
	}

	// The gathering is in BundleItemChooserSupport; the cache stays here, because what
	// invalidates it is this panel's own state.
	private func unfilteredItems() -> [ActionItem] {
		if unfilteredItemsCache == nil {
			unfilteredItemsCache = BundleItemChooserSupport.unfilteredItems(forScope: scope, hasSelection: hasSelection, searchSource: searchSource, searchAllScopes: searchAllScopes, documentPath: path, documentDirectory: directory)
		}
		return unfilteredItemsCache ?? []
	}

	override func updateItems(_ sender: Any?) {
		let identifiers = OakAbbreviations.abbreviations(forName: "OakBundleItemChooserBindings").strings(forAbbreviation: filterString)
		let filter = keyEquivalentInput ? keyEquivalentString : filterString

		items = BundleItemChooserSupport.rankedItems(unfilteredItems(), filterString: filter, bundleItemField: bundleItemFieldStorage, searchSource: searchSourceStorage, bindings: identifiers)

		window?.title = "Select Bundle Item (\(itemCountTextField.stringValue))"
	}

	override func updateStatusText(_ sender: Any?) {
		var status: String?
		if tableView.selectedRow != -1, let item = (items as? [ActionItem])?.at(tableView.selectedRow) {
			status = item.semanticClass ?? item.scopeSelector ?? item.action.map { NSStringFromSelector($0) }
		}
		statusTextField.stringValue = status ?? ""

		// Our super class will ask for updated status text each time selection changes
		// so we use this to update enabled state for action buttons
		// FIXME Since 'canEdit' depends on 'editAction' we must update 'enabled' when 'editAction' changes.
		selectButton.isEnabled     = canAccept()
		editButton.isEnabled       = canEdit()
		window?.defaultButtonCell  = !canAccept() && canEdit() ? editButton.cell as? NSButtonCell : selectButton.cell as? NSButtonCell
		tableView.doubleAction     = !canAccept() && canEdit() ? #selector(editItem(_:)) : #selector(accept(_:))
	}

	@objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		if menuItem.action == #selector(takeBundleItemFieldFrom(_:)) {
			menuItem.state = bundleItemField == UInt(menuItem.tag) ? .on : .off
		} else if menuItem.action == #selector(toggleSearchAllScopes(_:)) {
			menuItem.state = searchAllScopes ? .on : .off
		}
		return true
	}

	private func selectedItem() -> ActionItem? {
		guard tableView.selectedRow != -1 else {
			return nil
		}
		return (items as? [ActionItem])?.at(tableView.selectedRow)
	}

	@objc func canAccept() -> Bool {
		BundleItemChooserSupport.canAccept(selectedItem())
	}

	@objc func canEdit() -> Bool {
		guard let item = selectedItem() else {
			return false
		}
		return (item.uuid != nil && editAction != nil) || item.file != nil
	}

	override func accept(_ sender: Any?) {
		if bundleItemFieldStorage == kBundleItemTitleField, OakNotEmptyString(filterString), tableView.selectedRow > 0 || (filterString?.count ?? 0) > 1 {
			if let item = selectedItem(), let identifier = BundleItemChooserSupport.abbreviationIdentifier(for: item), let filterString {
				OakAbbreviations.abbreviations(forName: "OakBundleItemChooserBindings").learn(abbreviation: filterString, forString: identifier)
			}
		}

		if let item = selectedItem() {
			var action: Selector?
			var target: Any?
			var actionSender: Any? = self

			if let menuItem = item.menuItem {
				target       = menuItem.target
				action       = menuItem.action
				actionSender = menuItem
			} else {
				action = item.action
			}

			if let action {
				window?.orderOut(self)
				NSApp.sendAction(action, to: target, from: actionSender)
				window?.close()

				return
			}
		}

		super.accept(sender)
	}

	@objc func editItem(_ sender: Any?) {
		guard canEdit(), let editAction else {
			NSSound.beep()
			return
		}

		window?.orderOut(self)
		NSApp.sendAction(editAction, to: target, from: self)
		window?.close()
	}

	@objc func selectNextTab(_ sender: Any?) { scopeBar.selectNextButton(sender) }
	@objc func selectPreviousTab(_ sender: Any?) { scopeBar.selectPreviousButton(sender) }
}

private extension Array {
	func at(_ index: Int) -> Element? {
		indices.contains(index) ? self[index] : nil
	}
}
