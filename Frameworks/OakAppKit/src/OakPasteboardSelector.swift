import AppKit

// Ported from OakPasteboardSelector.mm (2026-08-20). The pop-up list OakPasteboard
// shows for ⌥⌘V-style history selection: a borderless child window with a table of
// multi-line cells, driven by a modal event loop. Its C++ was only std::count /
// std::clamp / std::set / to_s for layout and event classification, so this is a
// straight translation, no boundary extraction.
//
// @objc(OakPasteboardSelector) and the tableView outlet are load-bearing: the window
// is loaded from "Pasteboard Selector.xib", which names the class and connects the
// outlet. The public selectors are pinned by t_pasteboard.mm (rule 18) and called
// from OakPasteboard and FFTextFieldViewController.

private func rawLineCount(_ text: String) -> Int {
	var count = text.reduce(0) { $1 == "\n" ? $0 + 1 : $0 } + 1
	if text.hasSuffix("\n") {
		count -= 1
	}
	return count
}

private class OakPasteboardSelectorMultiLineCell: NSCell {
	var maxLines: Int = 1

	convenience init(maxLines: Int) {
		self.init(textCell: "")
		self.maxLines = maxLines
	}

	required init(coder: NSCoder) { super.init(coder: coder) }
	override init(textCell string: String) { super.init(textCell: string) }

	private var textAttributes: [NSAttributedString.Key: Any] {
		let style = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
		style.lineBreakMode = .byTruncatingTail
		return [
			.foregroundColor: isHighlighted ? NSColor.alternateSelectedControlTextColor : NSColor.controlTextColor,
			.paragraphStyle: style,
			.font: NSFont.controlContentFont(ofSize: 0),
		]
	}

	// The ObjC++ overrode the deprecated attribute-based accessibility API to report
	// the cell as static text with its value; the modern role/value overrides are the
	// same behaviour.
	override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
	override func accessibilityValue() -> Any? { objectValue }

	func lineCount(forText text: String) -> Int {
		min(max(rawLineCount(text), 1), maxLines)
	}

	override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
		let value = (objectValue as? String) ?? ""
		let lines = value.components(separatedBy: "\n")
		let clippedLines = Array(lines.prefix(lineCount(forText: value)))
		var rowFrame = cellFrame.insetBy(dx: 2, dy: 1)
		rowFrame.size.height = (lines.first ?? "").size(withAttributes: textAttributes).height
		for index in 0..<clippedLines.count {
			if index == clippedLines.count - 1, clippedLines.count < lines.count {
				let remaining = lines.count - clippedLines.count
				let moreLinesText = "\(remaining) more line\(remaining != 1 ? "s" : "")"
				let moreLinesAttributes: [NSAttributedString.Key: Any] = [
					.foregroundColor: isHighlighted ? NSColor.alternateSelectedControlTextColor : NSColor.secondaryLabelColor,
					.font: NSFont.controlContentFont(ofSize: NSFont.systemFontSize(for: .small)),
				]
				let moreLines = NSAttributedString(string: moreLinesText, attributes: moreLinesAttributes)
				let size = moreLines.size()
				var moreLinesRect = rowFrame
				moreLinesRect.origin.x += cellFrame.size.width - size.width - 4
				moreLinesRect.size = size
				rowFrame.size.width -= size.width + 9
				moreLines.draw(in: moreLinesRect)
			}
			(clippedLines[index] as NSString).draw(in: rowFrame, withAttributes: textAttributes)
			rowFrame.origin.y += rowFrame.size.height
		}
	}

	func rowHeight(forText text: String) -> CGFloat {
		2 + CGFloat(lineCount(forText: text)) * ("n" as NSString).size(withAttributes: textAttributes).height
	}
}

private class OakPasteboardSelectorTableViewHelper: NSResponder, NSTableViewDataSource, NSTableViewDelegate {
	private weak var tableView: NSTableView?
	private var entries: [OakPasteboardEntry]
	var shouldClose = false
	var shouldCancel = false

	init(entries someEntries: [OakPasteboardEntry]) {
		self.entries = someEntries
		super.init()
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	deinit {
		setTableView(nil)
	}

	func numberOfRows(in aTableView: NSTableView) -> Int {
		entries.count
	}

	func tableView(_ aTableView: NSTableView, objectValueFor aTableColumn: NSTableColumn?, row rowIndex: Int) -> Any? {
		entries[rowIndex].string.trimmingCharacters(in: .newlines)
	}

	func tableView(_ aTableView: NSTableView, heightOfRow rowIndex: Int) -> CGFloat {
		let text = (self.tableView(aTableView, objectValueFor: nil, row: rowIndex) as? String) ?? ""
		return ((aTableView.tableColumns.first?.dataCell as? OakPasteboardSelectorMultiLineCell)?.rowHeight(forText: text)) ?? 0
	}

	func setTableView(_ aTableView: NSTableView?) {
		if let tableView = tableView, tableView == aTableView {
			return
		}

		if let tableView = tableView {
			tableView.delegate = nil
			tableView.target = nil
			tableView.dataSource = nil
			tableView.nextResponder = nextResponder
		}

		tableView = aTableView
		if let tableView = tableView {
			tableView.dataSource = self
			tableView.delegate = self
			tableView.reloadData()
			tableView.usesAlternatingRowBackgroundColors = true
			tableView.tableColumns.first?.dataCell = OakPasteboardSelectorMultiLineCell(maxLines: 3)

			let nextResponder = tableView.nextResponder
			tableView.nextResponder = self
			self.nextResponder = nextResponder

			tableView.target = self
			tableView.doubleAction = #selector(didDoubleClickInTableView(_:))
			tableView.action = nil
		}
	}

	func setPerformsActionOnSingleClick() {
		tableView?.action = #selector(didDoubleClickInTableView(_:))
	}

	override func deleteBackward(_ sender: Any?) {
		guard let tableView = tableView else { return }
		let selectedRow = tableView.selectedRow
		if selectedRow == -1 || entries.count <= 1 {
			NSSound.beep()
			return
		}
		entries.remove(at: selectedRow)
		tableView.reloadData()
		if !entries.isEmpty {
			tableView.selectRowIndexes(IndexSet(integer: min(max(selectedRow - 1, 0), entries.count - 1)), byExtendingSelection: false)
		}
	}

	override func deleteForward(_ sender: Any?) {
		guard let tableView = tableView else { return }
		let selectedRow = tableView.selectedRow
		if selectedRow == -1 || entries.count <= 1 {
			NSSound.beep()
			return
		}
		entries.remove(at: selectedRow)
		tableView.reloadData()
		if !entries.isEmpty {
			tableView.selectRowIndexes(IndexSet(integer: min(selectedRow, entries.count - 1)), byExtendingSelection: false)
		}
	}

	@objc func accept(_ sender: Any?) {
		shouldClose = true
	}

	@objc func cancel(_ sender: Any?) {
		shouldCancel = true
		shouldClose = true
	}

	override func doCommand(by aSelector: Selector) {
		if responds(to: aSelector) {
			super.doCommand(by: aSelector)
		} else if let tableView = tableView {
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

	@objc func didDoubleClickInTableView(_ aTableView: Any?) {
		shouldClose = true
	}

	func currentEntries() -> [OakPasteboardEntry] {
		entries
	}
}

@objc(OakPasteboardSelector)
class OakPasteboardSelector: NSWindowController {
	@objc static let sharedInstance = OakPasteboardSelector()

	@IBOutlet private var tableView: NSTableView!
	private var tableViewHelper: OakPasteboardSelectorTableViewHelper?

	override var windowNibName: NSNib.Name? { "Pasteboard Selector" }

	init() {
		super.init(window: nil)
		shouldCascadeWindows = false
		_ = window // force the nib to load
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	@objc(setIndex:)
	func setIndex(_ index: UInt) {
		tableView.selectRowIndexes(IndexSet(integer: Int(index)), byExtendingSelection: false)
	}

	@objc(setEntries:)
	func setEntries(_ entries: [OakPasteboardEntry]) {
		setIndex(0)
		let helper = OakPasteboardSelectorTableViewHelper(entries: entries)
		tableViewHelper = helper
		helper.setTableView(tableView)
	}

	@objc(entries)
	func entries() -> [OakPasteboardEntry] {
		tableViewHelper?.currentEntries() ?? []
	}

	@objc(showAtLocation:)
	func show(atLocation aLocation: NSPoint) -> Int {
		let parentWindow = NSApp.keyWindow
		guard let window = window else { return -1 }
		window.setFrameTopLeftPoint(aLocation)
		parentWindow?.addChildWindow(window, ordered: .above)
		window.orderFront(self)
		tableView.scrollRowToVisible(tableView.selectedRow)

		let keyEvents: Set<NSEvent.EventType> = [.keyDown, .keyUp]
		let mouseEvents: Set<NSEvent.EventType> = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]

		while let event = NSApp.nextEvent(matching: .any, until: .distantFuture, inMode: .default, dequeue: true) {
			let orderOutEvent = (keyEvents.contains(event.type) && event.window != parentWindow) || (mouseEvents.contains(event.type) && event.window != window)
			if !orderOutEvent, keyEvents.contains(event.type), !event.modifierFlags.contains(.command) {
				window.sendEvent(event)
			} else {
				NSApp.sendEvent(event)
			}

			if orderOutEvent || tableViewHelper?.shouldClose == true {
				break
			}
		}

		parentWindow?.removeChildWindow(window)
		window.orderOut(self)

		return tableViewHelper?.shouldCancel == true ? -1 : tableView.selectedRow
	}

	@objc(setWidth:)
	func setWidth(_ width: CGFloat) {
		guard let window = window else { return }
		var frame = window.frame
		frame.size.width = width
		window.setFrame(frame, display: false)
	}

	@objc(setPerformsActionOnSingleClick)
	func setPerformsActionOnSingleClick() {
		tableViewHelper?.setPerformsActionOnSingleClick()
	}
}
