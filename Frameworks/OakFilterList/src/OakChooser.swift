import AppKit

// Ported from OakChooser.mm (2026-08-20). The filter-list base class: a floating panel
// with a linked search field over a table, subclassed by SymbolChooser, FileChooser and
// BundleItemChooser (still ObjC++) and by FavoriteChooser in the app — so the class and
// everything a subclass touches is @objc, reached through the hand-declaration in
// OakChooser.h, and its contract is pinned by t_chooser.mm (rule 18).
//
// Two decisions carry the port:
//
// - EVERY @objc member is `dynamic`, not just the overridable hooks. A statically
//   compiled ObjC subclass has no Swift vtable, so any base-internal Swift call that
//   dispatches through one — even an innocuous lazy-view getter — reads garbage past the
//   ObjC class metadata and jumps into data when self is a subclass instance (found the
//   hard way: EXC_BAD_ACCESS in the items setter, via the itemCountTextField getter, on
//   the first ObjC-subclass instance t_chooser.mm creates). dynamic forces objc_msgSend
//   everywhere, which is also what lets subclass overrides of updateItems:/
//   updateStatusText:/updateFilterString:/showWindow:/accept:/cancel: win when the base
//   calls them on self.
//
// - Unlike the ported singletons, choosers are created and destroyed per use, so
//   deallocation really happens (rule 49 territory: no `final`), and the firstResponder
//   observation stays *classic* KVO registered on self — BundleItemChooser's
//   -observeValueForKeyPath: override piggybacks on it and forwards unknown contexts to
//   super, both of which a block-based token would silently break. See deinit for what
//   of the ObjC++ dealloc survived.
@objc(OakChooser)
@MainActor
class OakChooser: NSWindowController, NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
	@objc dynamic var action: Selector?
	@objc dynamic weak var target: AnyObject?

	// Classic KVO, not a block-based token, and load-bearing: BundleItemChooser's
	// -observeValueForKeyPath: override piggybacks on this registration (it inspects the
	// "firstResponder" callbacks itself) and forwards unknown contexts to super — both
	// only work if the base registers *self* as the observer and implements the classic
	// callback. The context is a one-byte allocation whose address identifies us, never
	// freed (class-lifetime), because Swift can't take a stable pointer to a static var
	// outside a call argument.
	nonisolated(unsafe) private static let firstResponderObserverContext = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
	private weak var observedWindow: NSWindow?

	private var accessoryViewController: NSTitlebarAccessoryViewController?

	private var _searchField: NSSearchField?
	private var _scrollView: NSScrollView?
	private var _tableView: NSTableView?
	private var _footerView: NSVisualEffectView?
	private var _statusTextField: NSTextField?
	private var _itemCountTextField: NSTextField?

	@objc init() {
		let panel = NSPanel(contentRect: NSRect(x: 600, y: 700, width: 400, height: 500), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
		super.init(window: panel)

		window?.standardWindowButton(.miniaturizeButton)?.isHidden = true
		window?.standardWindowButton(.zoomButton)?.isHidden = true
		window?.level    = .floating
		window?.setFrameAutosaveName(NSStringFromClass(type(of: self)))
		window?.delegate = self

		observedWindow = window
		window?.addObserver(self, forKeyPath: "firstResponder", options: [.old, .new], context: Self.firstResponderObserverContext)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		// The one teardown that matters: the classic firstResponder observation must be
		// removed before the window deallocates. removeObserver is nonisolated NSObject
		// API and observedWindow is our own stored property, so this is reachable from a
		// nonisolated deinit — unlike self.window, whose getter is main-actor-isolated.
		//
		// The rest of the ObjC++ dealloc is deliberately dropped: it nil'd the search
		// field's delegate and the table's target/dataSource/delegate — all weak, and the
		// chooser owns both views, so they die with it — and unbound the search field's
		// value binding, which post-10.13 KVO tolerates leaving in place for an object
		// graph that deallocates together (the OakPasteboardChooser argument).
		observedWindow?.removeObserver(self, forKeyPath: "firstResponder", context: Self.firstResponderObserverContext)
	}

	// MARK: - View Construction

	@objc(addTitlebarAccessoryView:)
	dynamic func addTitlebarAccessoryView(_ titlebarView: NSView) {
		titlebarView.translatesAutoresizingMaskIntoConstraints = false

		let controller = NSTitlebarAccessoryViewController()
		controller.view = titlebarView
		controller.view.setFrameSize(titlebarView.fittingSize)
		accessoryViewController = controller
		window?.addTitlebarAccessoryViewController(controller)
	}

	@objc dynamic func updateScrollViewInsets() {
		var insets = scrollView.contentInsets
		insets.bottom += footerView.fittingSize.height
		scrollView.automaticallyAdjustsContentInsets = false
		scrollView.contentInsets = insets
	}

	@objc dynamic var searchField: NSSearchField {
		if let searchField = _searchField {
			return searchField
		}

		let searchField = OakLinkedSearchField(frame: .zero)
		(searchField.cell as? NSSearchFieldCell)?.isScrollable = true
		(searchField.cell as? NSSearchFieldCell)?.sendsSearchStringImmediately = true
		searchField.setAccessibilitySharedFocusElements([tableView])
		if !NSApp.isFullKeyboardAccessEnabled {
			searchField.focusRingType = .none
		}
		searchField.delegate = self

		searchField.bind(.value, to: self, withKeyPath: "filterString", options: nil)

		_searchField = searchField
		return searchField
	}

	@objc dynamic var tableView: NSTableView {
		if let tableView = _tableView {
			return tableView
		}

		let tableView = NSTableView(frame: .zero)
		tableView.headerView              = nil
		tableView.focusRingType           = .none
		tableView.allowsEmptySelection    = false
		tableView.allowsMultipleSelection = false
		tableView.refusesFirstResponder   = true
		tableView.doubleAction            = #selector(accept(_:))
		tableView.target                  = self
		tableView.dataSource              = self
		tableView.delegate                = self

		tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))

		_tableView = tableView
		return tableView
	}

	@objc dynamic var scrollView: NSScrollView {
		if let scrollView = _scrollView {
			return scrollView
		}

		let scrollView = NSScrollView(frame: .zero)
		scrollView.hasVerticalScroller   = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers    = true
		scrollView.borderType            = .noBorder
		scrollView.documentView          = tableView

		if let contentView = window?.contentView {
			scrollView.translatesAutoresizingMaskIntoConstraints = false
			contentView.addSubview(scrollView, positioned: .below, relativeTo: nil)

			let views = ["scrollView": scrollView]
			contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[scrollView]|", options: [], metrics: nil, views: views))
			contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[scrollView]|", options: [], metrics: nil, views: views))
		}

		_scrollView = scrollView
		return scrollView
	}

	@objc dynamic var statusTextField: NSTextField {
		if let statusTextField = _statusTextField {
			return statusTextField
		}

		let statusTextField = NSTextField(frame: .zero)
		statusTextField.isBezeled       = false
		statusTextField.isBordered      = false
		statusTextField.drawsBackground = false
		statusTextField.isEditable      = false
		statusTextField.font            = OakStatusBarFont()
		statusTextField.isSelectable    = false
		statusTextField.cell?.lineBreakMode = .byTruncatingMiddle
		statusTextField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		statusTextField.setContentHuggingPriority(.defaultLow, for: .horizontal)

		_statusTextField = statusTextField
		return statusTextField
	}

	@objc dynamic var itemCountTextField: NSTextField {
		if let itemCountTextField = _itemCountTextField {
			return itemCountTextField
		}

		let itemCountTextField = NSTextField(frame: .zero)
		itemCountTextField.isBezeled       = false
		itemCountTextField.isBordered      = false
		itemCountTextField.drawsBackground = false
		itemCountTextField.isEditable      = false
		itemCountTextField.font            = OakStatusBarFont()
		itemCountTextField.isSelectable    = false
		itemCountTextField.setContentHuggingPriority(.defaultHigh, for: .horizontal)

		if let font = itemCountTextField.font {
			let descriptor = font.fontDescriptor.addingAttributes([
				.featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType, NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]]
			])
			itemCountTextField.font = NSFont(descriptor: descriptor, size: 0)
		}

		_itemCountTextField = itemCountTextField
		return itemCountTextField
	}

	@objc dynamic var footerView: NSVisualEffectView {
		if let footerView = _footerView {
			return footerView
		}

		let footerView = NSVisualEffectView(frame: .zero)
		footerView.blendingMode = .withinWindow
		footerView.material     = .headerView

		if let contentView = window?.contentView {
			contentView.wantsLayer = true
			footerView.translatesAutoresizingMaskIntoConstraints = false
			contentView.addSubview(footerView, positioned: .above, relativeTo: nil)

			let views = ["footerView": footerView]
			contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-(>=77)-[footerView]|", options: [], metrics: nil, views: views))
			contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[footerView]|", options: [], metrics: nil, views: views))
		}

		_footerView = footerView
		return footerView
	}

	// MARK: -

	override dynamic func showWindow(_ sender: Any?) {
		if isWindowLoaded, let window = window, window.isVisible, window.isKeyWindow {
			window.close()
			return
		}

		window?.makeFirstResponder(window?.initialFirstResponder)
		super.showWindow(sender)
	}

	@objc(showWindowRelativeToFrame:)
	dynamic func showWindow(relativeToFrame parentFrame: NSRect) {
		if let window = window, !window.isVisible {
			window.layoutIfNeeded()
			var frame = window.frame
			let parent = parentFrame

			frame.origin.x = parent.minX + ((parent.width  - frame.width)  * 1 / 4).rounded()
			frame.origin.y = parent.minY + ((parent.height - frame.height) * 3 / 4).rounded()
			window.setFrame(frame, display: false)
		}
		showWindow(self)
	}

	// MARK: - Table highlight follows search-field focus

	// The classic callback, kept as such (see firstResponderObserverContext above). It
	// overrides a nonisolated NSObject method; the firstResponder change always fires on
	// the main thread, so the main-actor state is reached through assumeIsolated. Like
	// the ObjC++, unknown contexts are ignored, not forwarded — the original never called
	// super here, and NSObject's implementation throws.
	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		if context == Self.firstResponderObserverContext {
			MainActor.assumeIsolated {
				guard let searchField = _searchField else {
					return
				}
				let oldValue = change?[.oldKey] as AnyObject?
				let newValue = change?[.newKey] as AnyObject?
				let oldIsSearchField = oldValue === searchField || oldValue === searchField.currentEditor()
				let newIsSearchField = newValue === searchField || newValue === searchField.currentEditor()
				if oldIsSearchField != newIsSearchField {
					drawTableViewAsHighlighted = newIsSearchField && tableView.refusesFirstResponder
				}
			}
		}
	}

	// MARK: - Forward search-field movement actions to the table

	func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
		let res = OakPerformTableViewActionFromSelector(tableView, commandSelector)
		if res == OakPerformTableViewActionResult.moveAcceptReturn.rawValue {
			performDefaultButtonClick(self)
		} else if res == OakPerformTableViewActionResult.moveCancelReturn.rawValue {
			cancel(self)
		}
		return res != OakPerformTableViewActionResult.moveNoActionReturn.rawValue
	}

	// MARK: - Properties

	private var _filterString: String?

	// dynamic so the search field's value binding sees KVO notifications even for a
	// Swift-internal write, and any subclass override always wins.
	@objc dynamic var filterString: String? {
		get { _filterString }
		set {
			if _filterString == newValue {
				return
			}

			_filterString = newValue
			_searchField?.stringValue = newValue ?? ""

			updateFilterString(_filterString)

			// see https://lists.apple.com/archives/accessibility-dev/2014/Aug/msg00024.html
			if let tableView = _tableView {
				NSAccessibility.post(element: tableView, notification: .selectedRowsChanged)
			}
		}
	}

	@objc(updateFilterString:)
	dynamic func updateFilterString(_ string: String?) {
		if let tableView = _tableView, tableView.numberOfRows != 0 {
			tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
			tableView.scrollRowToVisible(0)
		}
		updateItems(self)
	}

	private var _items: [Any] = []

	@objc dynamic var items: [Any] {
		get { _items }
		set {
			let oldSelectedRowIndexes = _tableView?.selectedRowIndexes ?? IndexSet()
			var selectedItems: [Any] = []
			if oldSelectedRowIndexes.count > 1 || (oldSelectedRowIndexes.count == 1 && oldSelectedRowIndexes.first! > 0) {
				selectedItems = oldSelectedRowIndexes.compactMap { $0 < _items.count ? _items[$0] : nil }
			}

			_items = newValue
			_tableView?.reloadData()

			var rowIndexes = IndexSet()
			for item in selectedItems {
				let row = (_items as NSArray).index(of: item) // isEqual:, matching the original -indexOfObject:
				if row != NSNotFound {
					rowIndexes.insert(row)
				}
			}

			if rowIndexes.isEmpty {
				rowIndexes.insert(0)
			}

			_tableView?.selectRowIndexes(rowIndexes, byExtendingSelection: false)
			if !UserDefaults.standard.bool(forKey: "disableFilterListAutoScroll"), let firstRow = rowIndexes.first {
				_tableView?.scrollRowToVisible(firstRow)
			}

			updateStatusText(self)

			itemCountTextField.stringValue = Self.itemCountString(for: _items.count)
		}
	}

	private static func itemCountString(for count: Int) -> String {
		let number = NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
		return "\(number) item\(count == 1 ? "" : "s")"
	}

	@objc dynamic var selectedItems: [Any] {
		let indexes = _tableView?.selectedRowIndexes ?? IndexSet()
		return indexes.compactMap { $0 < _items.count ? _items[$0] : nil }
	}

	@objc(removeItemsAtIndexes:)
	@discardableResult dynamic func removeItems(at indexSet: IndexSet) -> UInt {
		_tableView?.removeRows(at: indexSet, withAnimation: .effectFade)
		for index in indexSet.reversed() where index < _items.count { // not remove(atOffsets:) — that's SwiftUI, and auto-links it
			_items.remove(at: index)
		}
		itemCountTextField.stringValue = Self.itemCountString(for: _items.count)

		if let tableView = _tableView, tableView.numberOfRows != 0, tableView.selectedRowIndexes.isEmpty, let firstRemoved = indexSet.first {
			tableView.selectRowIndexes(IndexSet(integer: min(firstRemoved, tableView.numberOfRows - 1)), byExtendingSelection: false)
		}

		return UInt(indexSet.count)
	}

	// MARK: - Actions

	@objc(performDefaultButtonClick:)
	dynamic func performDefaultButtonClick(_ sender: Any?) {
		if let defaultButtonCell = window?.defaultButtonCell {
			defaultButtonCell.performClick(sender)
		} else {
			accept(sender)
		}
	}

	@objc(accept:)
	dynamic func accept(_ sender: Any?) {
		window?.orderOut(self)
		if let action = action {
			NSApp.sendAction(action, to: target, from: self)
		}
		window?.close()
	}

	@objc(cancel:)
	dynamic func cancel(_ sender: Any?) {
		window?.performClose(self)
	}

	// MARK: - NSTableViewDataSource / NSTableViewDelegate

	func numberOfRows(in tableView: NSTableView) -> Int {
		_items.count
	}

	func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		OakInactiveTableRowView()
	}

	private var _drawTableViewAsHighlighted = false

	@objc dynamic var drawTableViewAsHighlighted: Bool {
		get { _drawTableViewAsHighlighted }
		set {
			_drawTableViewAsHighlighted = newValue
			_tableView?.enumerateAvailableRowViews { rowView, _ in
				(rowView as? OakInactiveTableRowView)?.drawAsHighlighted = newValue
			}
		}
	}

	func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
		(rowView as? OakInactiveTableRowView)?.drawAsHighlighted = _drawTableViewAsHighlighted
	}

	dynamic func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard let identifier = tableColumn?.identifier else {
			return nil
		}
		let res = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField) ?? {
			let label = OakCreateLabel("", NSFont.controlContentFont(ofSize: 0), .left, .byTruncatingMiddle)!
			label.identifier = identifier
			return label
		}()
		// objectValue, not stringValue-as-String: the original passed whatever
		// -objectForKey: returned straight to -setStringValue:, and for SymbolChooser —
		// the one subclass that uses this base implementation — that value is an
		// NSAttributedString carrying the match highlighting. ObjC's setStringValue:
		// stores such an object as the cell's objectValue and draws it with its
		// attributes; a Swift `as? String` would fail the cast and blank every row.
		res.objectValue = (_items[row] as? NSObject)?.value(forKey: identifier.rawValue)
		return res
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		updateStatusText(self)
	}

	// MARK: - Overridden by subclasses

	@objc(updateItems:)
	dynamic func updateItems(_ sender: Any?) {
	}

	@objc(updateStatusText:)
	dynamic func updateStatusText(_ sender: Any?) {
		_statusTextField?.stringValue = ""
	}
}
