import AppKit

// Ported from OakPasteboardChooser.mm (2026-08-20). The Clipboard/Find History window:
// a floating panel with a search field, an All/Flagged scope bar, a table of entries
// bound through an NSArrayController, and a footer of flag/delete/clear/paste buttons.
// A straight translation — its only C++ was two std::exchange flag toggles in the
// display-string builder and a std::set<SEL> of forwarded field-editor commands.
//
// @objc(OakPasteboardChooser) and the @objc(…) selectors keep the surface t_pasteboard.mm
// pins and OakDocumentView calls. hasSelection / sourceIndex / filterString are
// @objc dynamic because the buttons, the scope bar and the search field bind to them.

private let kTableColumnIdentifierMain = NSUserInterfaceItemIdentifier("main")
private let kTableColumnIdentifierFlag = NSUserInterfaceItemIdentifier("flag")

private extension OakPasteboardEntry {
	// The attributed row text: regexp entries get oniguruma syntax styling, everything
	// else has its lines joined with ¬ and tabs with ‣, truncated past 1024 characters.
	var displayString: NSAttributedString {
		let joinerAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.tertiaryLabelColor]
		let lineJoiner = NSAttributedString(string: "¬", attributes: joinerAttributes)
		let tabJoiner  = NSAttributedString(string: "‣", attributes: joinerAttributes)
		let ellipsis   = NSAttributedString(string: "…", attributes: joinerAttributes)

		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.lineBreakMode = .byTruncatingTail
		let defaultAttributes: [NSAttributedString.Key: Any] = [
			.paragraphStyle: paragraphStyle,
			.font: NSFont.controlContentFont(ofSize: 0),
		]

		let res = NSMutableAttributedString()
		if (options[OakFindRegularExpressionOption] as? NSNumber)?.boolValue ?? false {
			let formatter = OakSyntaxFormatter(grammarName: "source.regexp.oniguruma")
			formatter.enabled = true
			res.setAttributedString(NSMutableAttributedString(string: string, attributes: defaultAttributes))
			formatter.addStyles(to: res)
		} else {
			var firstLine = true
			string.enumerateLines { line, stop in
				if !firstLine {
					res.append(lineJoiner)
				}
				firstLine = false

				var firstTab = true
				for str in line.components(separatedBy: "\t") {
					if res.string.count > 1024 {
						res.append(ellipsis)
						stop = true
						break
					}
					if !firstTab {
						res.append(tabJoiner)
					}
					firstTab = false
					res.append(NSAttributedString(string: str))
				}
			}
			res.addAttributes(defaultAttributes, range: NSRange(location: 0, length: res.length))
		}

		return res
	}
}

nonisolated(unsafe) private var SharedChoosers: [String: OakPasteboardChooser] = [:]

@objc(OakPasteboardChooser)
class OakPasteboardChooser: NSWindowController, NSWindowDelegate, NSTextFieldDelegate, NSTableViewDelegate, NSTableViewDataSource, NSSearchFieldDelegate {
	private let pasteboard: OakPasteboard
	private let arrayController = NSArrayController()
	private var accessoryViewController: NSTitlebarAccessoryViewController?
	private var scopeBar = OakScopeBarViewController()
	private var skipUpdatePasteboard = false
	private var actionButton: NSButton!
	private var eventMonitor: Any?

	@objc dynamic var filterString: String = "" { didSet { filterStringChanged(from: oldValue) } }
	@objc var action: Selector?
	@objc var alternateAction: Selector?
	@objc weak var target: AnyObject?

	@objc dynamic private var hasSelection = false
	@objc dynamic private var sourceIndex: UInt = 0 { didSet { sourceIndexChanged(from: oldValue) } }

	@objc(sharedChooserForPasteboard:)
	static func sharedChooser(for pboard: OakPasteboard) -> OakPasteboardChooser {
		SharedChoosers[pboard.name] ?? OakPasteboardChooser(pasteboard: pboard)
	}

	@objc(initWithPasteboard:)
	init(pasteboard aPasteboard: OakPasteboard) {
		self.pasteboard = aPasteboard
		let panel = NSPanel(contentRect: NSRect(x: 600, y: 700, width: 400, height: 500), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
		super.init(window: panel)

		var windowTitle = "Clipboard History"
		var actionName = "Paste"
		if pasteboard.isEqual(OakPasteboard.find) {
			windowTitle = "Find History"
			actionName = "Find Next"
		}

		scopeBar.labels = ["All", "Flagged"]

		let tableColumn = NSTableColumn(identifier: kTableColumnIdentifierMain)
		tableColumn.resizingMask = .autoresizingMask
		tableColumn.isEditable = false
		tableColumn.dataCell = NSTextFieldCell(textCell: "")
		(tableColumn.dataCell as? NSCell)?.lineBreakMode = .byTruncatingMiddle
		tableView.addTableColumn(tableColumn)

		let flagColumn = NSTableColumn(identifier: kTableColumnIdentifierFlag)
		flagColumn.resizingMask = []
		flagColumn.isEditable = false
		flagColumn.width = 32
		tableView.addTableColumn(flagColumn)

		window?.standardWindowButton(.miniaturizeButton)?.isHidden = true
		window?.standardWindowButton(.zoomButton)?.isHidden = true
		window?.autorecalculatesKeyViewLoop = true
		window?.delegate = self
		window?.level = .floating
		window?.title = windowTitle

		let titlebarViews: [String: NSView] = [
			"searchField": searchField,
			"dividerView": OakCreateNSBoxSeparator(),
			"scopeBar": scopeBar.view,
		]

		let titlebarView = NSView(frame: .zero)
		OakAddAutoLayoutViewsToSuperview(Array(titlebarViews.values), titlebarView)

		titlebarView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(8)-[searchField]-(8)-|", options: [], metrics: nil, views: titlebarViews))
		titlebarView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[dividerView]|", options: [], metrics: nil, views: titlebarViews))
		titlebarView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(8)-[scopeBar]-(>=8)-|", options: [], metrics: nil, views: titlebarViews))
		titlebarView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-(4)-[searchField]-(8)-[dividerView(==1)]-(4)-[scopeBar]-(4)-|", options: [], metrics: nil, views: titlebarViews))

		addTitlebarAccessoryView(titlebarView)

		let flagButton = OakCreateButton("⚑", .texturedRounded)!
		let deleteButton = OakCreateButton("Delete", .texturedRounded)!
		let clearAllButton = OakCreateButton("Clear History", .texturedRounded)!
		actionButton = OakCreateButton(actionName, .texturedRounded)!

		flagButton.action = #selector(toggleCurrentBookmark(_:))
		deleteButton.action = #selector(deleteForward(_:))
		clearAllButton.action = #selector(clearAll(_:))
		actionButton.action = #selector(accept(_:))

		let footerViews: [String: NSView] = [
			"dividerView": OakCreateNSBoxSeparator(),
			"flag": flagButton,
			"delete": deleteButton,
			"clearAll": clearAllButton,
			"action": actionButton,
		]

		OakAddAutoLayoutViewsToSuperview(Array(footerViews.values), footerView)

		footerView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[dividerView]|", options: [], metrics: nil, views: footerViews))
		footerView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(8)-[flag]-[delete]-[clearAll]-(>=20)-[action]-(8)-|", options: .alignAllLastBaseline, metrics: nil, views: footerViews))
		footerView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[dividerView(==1)]-(5)-[clearAll]-(6)-|", options: [], metrics: nil, views: footerViews))

		updateScrollViewInsets()

		window?.defaultButtonCell = actionButton.cell as? NSButtonCell

		flagButton.bind(.enabled, to: self, withKeyPath: "hasSelection")
		deleteButton.bind(.enabled, to: self, withKeyPath: "hasSelection")
		actionButton.bind(.enabled, to: self, withKeyPath: "hasSelection")
		scopeBar.bind(.value, to: self, withKeyPath: "sourceIndex")

		NotificationCenter.default.addObserver(self, selector: #selector(clipboardDidChange(_:)), name: NSNotification.Name.OakPasteboardDidChange, object: pasteboard)

		if pasteboard.isEqual(OakPasteboard.find) {
			NotificationCenter.default.addObserver(self, selector: #selector(windowDidChangeKeyStatus(_:)), name: NSWindow.didBecomeKeyNotification, object: window)
			NotificationCenter.default.addObserver(self, selector: #selector(windowDidChangeKeyStatus(_:)), name: NSWindow.didResignKeyNotification, object: window)
		}
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	deinit {
		// The ObjC++ also nil'd the window delegate and the table's data source /
		// delegate / target; all are weak and the chooser owns the table (it deallocs
		// with it), so removing the notification observer — which is not — is the only
		// teardown that matters, and the only one a @MainActor deinit can reach.
		NotificationCenter.default.removeObserver(self)
	}

	@objc private func windowDidChangeKeyStatus(_ aNotification: Notification) {
		let updateDefaultButton: (NSEvent?) -> NSEvent? = { [weak self] event in
			let optionDown = event?.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option
			self?.actionButton.title = optionDown ? "Find in Project" : "Find Next"
			return event
		}

		_ = updateDefaultButton(NSApp.currentEvent)
		if NSApp.keyWindow == window {
			eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: updateDefaultButton)
		} else if let eventMonitor = eventMonitor {
			NSEvent.removeMonitor(eventMonitor)
			self.eventMonitor = nil
		}
	}

	// =====================
	// = View Construction =
	// =====================

	private func addTitlebarAccessoryView(_ titlebarView: NSView) {
		titlebarView.translatesAutoresizingMaskIntoConstraints = false

		let controller = NSTitlebarAccessoryViewController()
		controller.view = titlebarView
		controller.view.setFrameSize(titlebarView.fittingSize)
		window?.addTitlebarAccessoryViewController(controller)
		accessoryViewController = controller
	}

	private func updateScrollViewInsets() {
		var insets = scrollView.contentInsets
		insets.bottom += footerView.fittingSize.height
		scrollView.automaticallyAdjustsContentInsets = false
		scrollView.contentInsets = insets
	}

	private lazy var searchField: NSSearchField = {
		let field = NSSearchField(frame: .zero)
		(field.cell as? NSSearchFieldCell)?.isScrollable = true
		(field.cell as? NSSearchFieldCell)?.sendsSearchStringImmediately = true
		field.delegate = self
		return field
	}()

	private func refreshTableViewAndSelect(_ clipboardEntry: OakPasteboardEntry?) {
		arrayController.content = pasteboard.entries()
		tableView.reloadData()

		let row = clipboardEntry.flatMap { pasteboardEntries.firstIndex(of: $0) }
		if let row = row {
			tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
			tableView.scrollRowToVisible(tableView.selectedRow)
		} else if let historyIds = clipboardEntry?.options["historyIds"] as? [Int] {
			let set = Set(historyIds)
			let indexSet = pasteboardEntries.enumerated().reduce(into: IndexSet()) { result, pair in
				if set.contains(pair.element.historyId) {
					result.insert(pair.offset)
				}
			}
			if !indexSet.isEmpty {
				tableView.selectRowIndexes(indexSet, byExtendingSelection: false)
			}
		}
	}

	@objc private func selectCurrentClipboardEntry(_ sender: Any?) {
		skipUpdatePasteboard = true
		refreshTableViewAndSelect(pasteboard.currentEntry)
		skipUpdatePasteboard = false
	}

	@objc private func clipboardDidChange(_ aNotification: Notification) {
		selectCurrentClipboardEntry(self)
	}

	private var _tableView: NSTableView?
	private var tableView: NSTableView {
		if let tableView = _tableView { return tableView }
		let tableView = NSTableView(frame: .zero)
		tableView.allowsTypeSelect = false
		tableView.headerView = nil
		tableView.focusRingType = .none
		tableView.allowsEmptySelection = true
		tableView.allowsMultipleSelection = true
		tableView.usesAlternatingRowBackgroundColors = true
		tableView.doubleAction = #selector(accept(_:))
		tableView.target = self
		tableView.delegate = self
		tableView.dataSource = self
		_tableView = tableView
		return tableView
	}

	private var _scrollView: NSScrollView?
	private var scrollView: NSScrollView {
		if let scrollView = _scrollView { return scrollView }
		let scrollView = NSScrollView(frame: .zero)
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers = true
		scrollView.borderType = .noBorder
		scrollView.documentView = tableView

		let contentView = window!.contentView!
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(scrollView, positioned: .below, relativeTo: nil)

		let views = ["scrollView": scrollView]
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[scrollView]|", options: [], metrics: nil, views: views))
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[scrollView]|", options: [], metrics: nil, views: views))
		_scrollView = scrollView
		return scrollView
	}

	private var _footerView: NSVisualEffectView?
	private var footerView: NSVisualEffectView {
		if let footerView = _footerView { return footerView }
		let footerView = NSVisualEffectView(frame: .zero)
		footerView.blendingMode = .withinWindow
		footerView.material = .headerView

		let contentView = window!.contentView!
		contentView.wantsLayer = true
		footerView.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(footerView, positioned: .above, relativeTo: nil)

		let views = ["footerView": footerView]
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-(>=77)-[footerView]|", options: [], metrics: nil, views: views))
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[footerView]|", options: [], metrics: nil, views: views))
		_footerView = footerView
		return footerView
	}

	// =====================

	override func showWindow(_ sender: Any?) {
		SharedChoosers[pasteboard.name] = self

		searchField.bind(.value, to: self, withKeyPath: "filterString")
		selectCurrentClipboardEntry(self)

		window?.makeFirstResponder(tableView)
		window?.makeKeyAndOrderFront(self)
	}

	@objc(showWindowRelativeToFrame:)
	func showWindow(relativeToFrame parentFrame: NSRect) {
		if let window = window, !window.isVisible {
			window.layoutIfNeeded()
			var frame = window.frame
			let parent = parentFrame
			frame.origin.x = parent.minX + ((parent.width - frame.width) * 1 / 4).rounded()
			frame.origin.y = parent.minY + ((parent.height - frame.height) * 3 / 4).rounded()
			window.setFrame(frame, display: false)
		}
		showWindow(self)
	}

	func windowWillClose(_ aNotification: Notification) {
		searchField.unbind(.value)
		SharedChoosers.removeValue(forKey: pasteboard.name)
	}

	@IBAction func selectNextTab(_ sender: Any?) { scopeBar.selectNextButton(sender) }
	@IBAction func selectPreviousTab(_ sender: Any?) { scopeBar.selectPreviousButton(sender) }
	@objc func updateShowTabMenu(_ aMenu: NSMenu) { scopeBar.updateGoToMenu(aMenu) }

	private func sourceIndexChanged(from oldValue: UInt) {
		guard oldValue != sourceIndex else { return }
		if sourceIndex == 0 {
			arrayController.filterPredicate = nil
			selectCurrentClipboardEntry(self)
		} else {
			arrayController.filterPredicate = NSPredicate(format: "isFlagged == YES")
			tableView.selectRowIndexes(IndexSet(), byExtendingSelection: false)
			refreshTableViewAndSelect(nil)
		}
	}

	private func filterStringChanged(from oldValue: String) {
		guard oldValue != filterString else { return }

		let oldSelectedRowIndexes = tableView.selectedRowIndexes
		let oldSelectedEntries = pasteboardEntries.enumerated().filter { oldSelectedRowIndexes.contains($0.offset) }.map { $0.element }
		let oldRowCount = tableView.numberOfRows

		arrayController.filterPredicate = OakIsEmptyString(filterString) ? nil : NSPredicate(format: "string CONTAINS[cd] %@", filterString)
		tableView.reloadData()

		if tableView.numberOfRows != 0, tableView.numberOfRows != oldRowCount {
			var newSelectedRowIndexes = IndexSet()

			if oldSelectedRowIndexes.count != 1 || oldSelectedRowIndexes.first != 0 {
				newSelectedRowIndexes = pasteboardEntries.enumerated().reduce(into: IndexSet()) { result, pair in
					if oldSelectedEntries.contains(pair.element) {
						result.insert(pair.offset)
					}
				}
			}

			if newSelectedRowIndexes.isEmpty {
				newSelectedRowIndexes = IndexSet(integer: 0)
			}

			if let first = newSelectedRowIndexes.first {
				didSelect(pasteboardEntries[first], updatePasteboard: true)
			}
		}
	}

	// ========================
	// = NSTableView Delegate =
	// ========================

	func tableView(_ aTableView: NSTableView, willDisplayCell aCell: Any, for aTableColumn: NSTableColumn?, row rowIndex: Int) {
		guard let cell = aCell as? NSCell else { return }
		if cell.backgroundStyle == .emphasized, aTableColumn?.identifier == kTableColumnIdentifierMain, let obj = cell.objectValue as? NSAttributedString {
			let str = NSMutableAttributedString(attributedString: obj)
			str.addAttribute(.foregroundColor, value: NSColor.alternateSelectedControlTextColor, range: NSRange(location: 0, length: str.length))
			str.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: str.length))
			cell.attributedStringValue = str
		}
	}

	private func didSelect(_ clipboardEntry: OakPasteboardEntry?, updatePasteboard flag: Bool) {
		let row = clipboardEntry.flatMap { pasteboardEntries.firstIndex(of: $0) }
		if let row = row {
			tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
			tableView.scrollRowToVisible(tableView.selectedRow)
		}

		if flag {
			NotificationCenter.default.removeObserver(self, name: NSNotification.Name.OakPasteboardDidChange, object: pasteboard)
			pasteboard.updatePasteboard(with: clipboardEntry)
			NotificationCenter.default.addObserver(self, selector: #selector(clipboardDidChange(_:)), name: NSNotification.Name.OakPasteboardDidChange, object: pasteboard)
		}
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		let selectedRowIndexes = tableView.selectedRowIndexes
		hasSelection = !selectedRowIndexes.isEmpty

		if selectedRowIndexes.count == 1, !skipUpdatePasteboard, let first = selectedRowIndexes.first {
			didSelect(pasteboardEntries[first], updatePasteboard: true)
		}
	}

	// ==========================
	// = NSTableView DataSource =
	// ==========================

	private var pasteboardEntries: [OakPasteboardEntry] {
		(arrayController.arrangedObjects as? [OakPasteboardEntry]) ?? []
	}

	func numberOfRows(in aTableView: NSTableView) -> Int {
		pasteboardEntries.count
	}

	func tableView(_ aTableView: NSTableView, objectValueFor aTableColumn: NSTableColumn?, row rowIndex: Int) -> Any? {
		let entry = pasteboardEntries[rowIndex]
		if aTableColumn?.identifier == kTableColumnIdentifierMain {
			return entry.displayString
		} else if aTableColumn?.identifier == kTableColumnIdentifierFlag {
			return entry.isFlagged() ? "⚑" : ""
		}
		return nil
	}

	// =================
	// = Action Method =
	// =================

	@IBAction func orderFrontFindPanel(_ sender: Any?) { window?.makeFirstResponder(searchField) }
	@IBAction func findAllInSelection(_ sender: Any?) { window?.makeFirstResponder(searchField) }

	private func updatePasteboardWithSelectedEntries(_ sender: Any?) {
		if let selectedEntries = selectedEntries, selectedEntries.count > 1 {
			pasteboard.updatePasteboard(withEntries: selectedEntries)
		}
	}

	@objc func accept(_ sender: Any?) {
		updatePasteboardWithSelectedEntries(self)
		window?.orderOut(self)

		if let alternateAction = alternateAction, OakIsAlternateKeyOrMouseEvent(NSEvent.ModifierFlags.option.rawValue, NSApp.currentEvent), NSApp.target(forAction: alternateAction) != nil {
			NSApp.sendAction(alternateAction, to: target, from: self)
		} else if let action = action {
			NSApp.sendAction(action, to: target, from: self)
		}
		window?.close()
	}

	@objc func cancel(_ sender: Any?) {
		updatePasteboardWithSelectedEntries(self)
		window?.performClose(self)
	}

	@objc func clearAll(_ sender: Any?) {
		pasteboard.removeAllEntries()
		pasteboard.updatePasteboard(with: nil) // Triggers OakPasteboardDidChangeNotification
	}

	private var selectedEntries: [OakPasteboardEntry]? {
		let res = pasteboardEntries.enumerated().filter { tableView.selectedRowIndexes.contains($0.offset) }.map { $0.element }
		return res.isEmpty ? nil : res
	}

	override func deleteForward(_ sender: Any?) {
		guard let entries = selectedEntries else { return }
		let row = tableView.selectedRowIndexes.first ?? 0

		pasteboard.removeEntries(entries)
		refreshTableViewAndSelect(nil)

		if tableView.numberOfRows != 0 {
			didSelect(pasteboardEntries[min(row, tableView.numberOfRows - 1)], updatePasteboard: true)
		} else {
			pasteboard.updatePasteboard(with: nil)
		}
	}

	override func deleteBackward(_ sender: Any?) {
		guard let entries = selectedEntries else { return }
		let row = tableView.selectedRowIndexes.first ?? 0

		pasteboard.removeEntries(entries)
		refreshTableViewAndSelect(nil)

		if tableView.numberOfRows != 0 {
			didSelect(pasteboardEntries[row > 0 ? row - 1 : row], updatePasteboard: true)
		} else {
			pasteboard.updatePasteboard(with: nil)
		}
	}

	@objc func toggleCurrentBookmark(_ sender: Any?) {
		guard let entries = selectedEntries else { return }
		let shouldFlag = entries.contains { !$0.isFlagged() }
		for entry in entries {
			entry.setFlagged(shouldFlag)
		}
		tableView.reloadData(forRowIndexes: tableView.selectedRowIndexes, columnIndexes: IndexSet(integer: tableView.column(withIdentifier: kTableColumnIdentifierFlag)))
	}

	override func insertTab(_ sender: Any?) {
		window?.selectNextKeyView(self)
	}

	override func insertBacktab(_ sender: Any?) {
		window?.selectPreviousKeyView(self)
	}

	override func insertText(_ aString: Any) {
		filterString = aString as? String ?? ""
		window?.makeFirstResponder(searchField)
		if let fieldEditor = window?.firstResponder as? NSText {
			fieldEditor.selectedRange = NSRange(location: fieldEditor.string.count, length: 0)
		}
	}

	override func doCommand(by aSelector: Selector) {
		if responds(to: aSelector) {
			super.doCommand(by: aSelector)
		} else {
			let res = OakPerformTableViewActionFromSelector(tableView, aSelector)
			if res == OakPerformTableViewActionResult.moveAcceptReturn.rawValue {
				accept(self)
			} else if res == OakPerformTableViewActionResult.moveCancelReturn.rawValue {
				cancel(self)
			}
		}
	}

	override func keyDown(with anEvent: NSEvent) {
		interpretKeyEvents([anEvent])
	}

	// ========================
	// = NSTextField Delegate =
	// ========================

	func control(_ aControl: NSControl, textView aTextView: NSTextView, doCommandBy aCommand: Selector) -> Bool {
		let forward: Set<Selector> = [
			#selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)),
			#selector(NSResponder.moveUpAndModifySelection(_:)), #selector(NSResponder.moveDownAndModifySelection(_:)),
			#selector(NSResponder.pageUp(_:)), #selector(NSResponder.pageDown(_:)),
			#selector(NSResponder.pageUpAndModifySelection(_:)), #selector(NSResponder.pageDownAndModifySelection(_:)),
			#selector(NSResponder.scrollPageUp(_:)), #selector(NSResponder.scrollPageDown(_:)),
			#selector(NSResponder.moveToBeginningOfDocument(_:)), #selector(NSResponder.moveToEndOfDocument(_:)),
			#selector(NSResponder.scrollToBeginningOfDocument(_:)), #selector(NSResponder.scrollToEndOfDocument(_:)),
			#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
			#selector(NSResponder.cancelOperation(_:)),
		]
		if !forward.contains(aCommand) {
			return false
		}

		let res = OakPerformTableViewActionFromSelector(tableView, aCommand)
		if res == OakPerformTableViewActionResult.moveAcceptReturn.rawValue {
			accept(aControl)
		} else if res == OakPerformTableViewActionResult.moveCancelReturn.rawValue {
			cancel(aControl)
		}
		return true
	}
}
