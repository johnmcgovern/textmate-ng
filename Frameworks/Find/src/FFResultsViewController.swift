import AppKit

// The find results outline view: file rows over match rows, with an exclude
// checkbox per match and a live replacement preview.
//
// FFResultsViewController.h stays hand-written and is deliberately absent from
// Find-Bridging-Header.h, the TMFileReference arrangement. The four cell classes
// below were never in a header at all — they exist only here, as they did in the
// ObjC++.
//
// **Every `dynamic` in this file is load-bearing.** OakTableCellView observes key
// paths *on the view controller* and mirrors the values onto itself with
// `setValue:forKey:`, and Find.mm binds two of the controller's properties
// (Find.mm:194-195). A property that is `@objc` but not `dynamic` is called
// directly from Swift and never notifies — the defect that shipped in the
// FFResultNode port (9d560946). The names are load-bearing too: the bridge is
// KVC-by-string in both directions, so a rename that Swift accepts is a runtime
// failure the moment a cell scrolls into view. t_results_view_controller.mm
// guards both.

private let kUserDefaultsSearchResultsFontNameKey = "searchResultsFontName"
private let kUserDefaultsSearchResultsFontSizeKey = "searchResultsFontSize"

// Sibling traversal. Free functions in the ObjC++ and private here — a Swift
// global cannot be `@objc`, and nothing outside this file calls them.
private func NextNode(_ node: FFResultNode?) -> FFResultNode? {
	guard let node, let siblings = node.parent?.children else { return nil }
	let index = siblings.index(of: node) + 1
	return index < siblings.count ? siblings[index] as? FFResultNode : nil
}

private func PreviousNode(_ node: FFResultNode?) -> FFResultNode? {
	guard let node, let siblings = node.parent?.children else { return nil }
	let index = siblings.index(of: node)
	return index > 0 ? siblings[index - 1] as? FFResultNode : nil
}

// ================================
// = OakSearchResultsCheckboxView =
// ================================

final class OakSearchResultsCheckboxView: NSTableCellView {
	@objc var button: NSButton!

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)

		button = OakCreateCheckBox(nil)
		button.controlSize = .small

		button.translatesAutoresizingMaskIntoConstraints = false
		addSubview(button)

		button.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
		button.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true

		button.bind(.enabled, to: self, withKeyPath: "objectValue.readOnly", options: [ .valueTransformerName: NSValueTransformerName.negateBooleanTransformerName ])
		button.bind(.value, to: self, withKeyPath: "objectValue.excluded", options: [ .valueTransformerName: NSValueTransformerName.negateBooleanTransformerName ])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}

// ====================
// = OakTableCellView =
// ====================

// The observation bridge: a cell registers on its view controller for a list of
// key paths and mirrors each value onto itself under the *same* name. Both
// directions are strings, which is why the cells below spell their mirrored
// properties exactly as the controller does.
class OakTableCellView: NSTableCellView {
	private var observingKeyPaths = false

	@objc var viewController: FFResultsViewController?
	@objc var observeKeyPaths: [String] = []

	override func viewWillMove(toSuperview newSuperview: NSView?) {
		if newSuperview != nil, observingKeyPaths == false {
			for keyPath in observeKeyPaths {
				viewController?.addObserver(self, forKeyPath: keyPath, options: .initial, context: nil)
			}
			observingKeyPaths = true
		} else if newSuperview == nil, observingKeyPaths == true {
			for keyPath in observeKeyPaths {
				viewController?.removeObserver(self, forKeyPath: keyPath)
			}
			observingKeyPaths = false
		}
		super.viewWillMove(toSuperview: newSuperview)
	}

	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		if let keyPath, observeKeyPaths.contains(keyPath) {
			setValue((object as? NSObject)?.value(forKey: keyPath), forKey: keyPath)
		} else {
			super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
		}
	}
}

// =================================
// = OakSearchResultsMatchCellView =
// =================================

final class OakSearchResultsMatchCellView: OakTableCellView {
	// Mirrored onto this cell by the bridge above, so both the names and the KVO
	// compliance matter.
	@objc dynamic var replaceString: String?
	@objc dynamic var showReplacementPreviews = false

	@objc class func keyPathsForValuesAffectingExcerptString() -> Set<String> {
		return [ "objectValue", "objectValue.readOnly", "objectValue.excluded", "objectValue.replaceString", "replaceString", "showReplacementPreviews", "backgroundStyle" ]
	}

	init(viewController: FFResultsViewController, font: NSFont?) {
		super.init(frame: .zero)

		self.viewController  = viewController
		self.observeKeyPaths = [ "replaceString", "showReplacementPreviews" ]

		let textField = OakCreateLabel("", font)!
		textField.setContentHuggingPriority(.required, for: .horizontal)
		textField.setContentCompressionResistancePriority(.required, for: .horizontal)

		let views: [String: Any] = [ "textField": textField ]
		OakAddAutoLayoutViewsToSuperview(views.values.compactMap { $0 as? NSView }, self)
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[textField]", options: [], metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[textField]|", options: [], metrics: nil, views: views))

		textField.bind(.value, to: self, withKeyPath: "excerptString", options: nil)

		self.textField = textField
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	@objc var excerptString: NSAttributedString? {
		guard let item = objectValue as? FFResultNode else { return nil }

		let replacement = (item.readOnly || item.excluded || !showReplacementPreviews) ? item.replaceString : (replaceString ?? "")
		var res = item.excerpt(withReplacement: replacement, font: textField?.font)

		if backgroundStyle == .dark, let current = res {
			let str = NSMutableAttributedString(attributedString: current)
			str.enumerateAttributes(in: NSRange(location: 0, length: str.length), options: NSAttributedString.EnumerationOptions.longestEffectiveRangeNotRequired) { (attrs: [NSAttributedString.Key: Any], range: NSRange, _) in
				if attrs[.backgroundColor] != nil {
					str.addAttribute(.backgroundColor, value: NSColor.tmMatchedTextSelectedBackground(), range: range)
				}
				if attrs[.underlineColor] != nil {
					str.addAttribute(.underlineColor, value: NSColor.tmMatchedTextSelectedUnderline(), range: range)
				}
			}
			str.addAttribute(.foregroundColor, value: NSColor.alternateSelectedControlTextColor, range: NSRange(location: 0, length: str.length))
			res = str
		}

		return res
	}
}

// ==================================
// = OakSearchResultsHeaderCellView =
// ==================================

final class OakSearchResultsHeaderCellView: OakTableCellView {
	@objc var countOfLeafsButton: NSButton!
	@objc var removeButton: NSButton!

	// Mirrored by the bridge; see OakSearchResultsMatchCellView.
	@objc dynamic var showKeyEquivalent = false {
		didSet { showKeyEquivalentDidChange(from: oldValue) }
	}

	init(viewController: FFResultsViewController) {
		super.init(frame: .zero)

		self.viewController  = viewController
		self.observeKeyPaths = [ "showKeyEquivalent" ]

		let imageView = NSImageView()
		let textField = OakCreateLabel("", NSFont.controlContentFont(ofSize: 0))!

		let countOfLeafs = NSButton()
		(countOfLeafs.cell as? NSButtonCell)?.highlightsBy = []
		countOfLeafs.alignment  = .center
		countOfLeafs.bezelStyle = .inline
		countOfLeafs.font       = NSFont.labelFont(ofSize: 0)
		countOfLeafs.identifier = NSUserInterfaceItemIdentifier("countOfLeafs")

		let removeTemplateImage = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { dstRect in
			NSColor.black.set()
			NSRect(x: dstRect.minX, y: dstRect.minY, width: dstRect.width, height: dstRect.height).insetBy(dx: 0, dy: (dstRect.height / 2).rounded(.down) - 1).fill()
			return true
		}
		removeTemplateImage.isTemplate = true

		let remove = NSButton()
		remove.controlSize = .small
		remove.bezelStyle  = .roundRect
		remove.setButtonType(.momentaryPushIn)
		remove.image       = removeTemplateImage

		let views: [String: Any] = [ "icon": imageView, "text": textField, "count": countOfLeafs, "remove": remove ]
		OakAddAutoLayoutViewsToSuperview(views.values.compactMap { $0 as? NSView }, self)

		textField.setContentHuggingPriority(.required, for: .horizontal)
		countOfLeafs.setContentCompressionResistancePriority(.required, for: .horizontal)

		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(9)-[remove(==16)]-(6)-[icon(==16)]-(3)-[text]", options: .alignAllCenterY, metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:[text]-(4)-[count]-(>=8@750)-|", options: .alignAllLastBaseline, metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[icon(==16,==remove)]-(3)-|", options: [], metrics: nil, views: views))

		imageView.bind(.value, to: self, withKeyPath: "objectValue.document.icon", options: nil)
		textField.bind(.value, to: self, withKeyPath: "objectValue.displayPath", options: nil)

		NotificationCenter.default.addObserver(self, selector: #selector(outlineViewItemDidExpandCollapse(_:)), name: NSOutlineView.itemDidExpandNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(outlineViewItemDidExpandCollapse(_:)), name: NSOutlineView.itemDidCollapseNotification, object: nil)

		self.imageView          = imageView
		self.textField          = textField
		self.countOfLeafsButton = countOfLeafs
		self.removeButton       = remove
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	// The key-equivalent overlay: a dashed rounded rect with the row's 1-based
	// index in it, for the first nine matches only, shown while ⌘ is held.
	private func showKeyEquivalentDidChange(from oldValue: Bool) {
		guard showKeyEquivalent != oldValue else { return }

		let item = objectValue as? FFResultNode
		guard showKeyEquivalent else {
			imageView?.image = item?.document?.icon
			return
		}

		guard let item, let siblings = item.parent?.children else { return }
		let index = siblings.index(of: item)
		if index > 8 {
			return
		}

		let bounds = imageView?.bounds ?? .zero
		let rect = bounds.union(NSRect(x: 0, y: 0, width: 16, height: 16))
		let image = NSImage(size: rect.size, flipped: false) { dstRect in
			var dstRect = dstRect
			let color = NSColor.secondaryLabelColor

			let ptrn: [CGFloat] = [ 2, 1 ]
			let path = NSBezierPath(roundedRect: dstRect.insetBy(dx: 1, dy: 1).integral, xRadius: 2, yRadius: 2)
			path.setLineDash(ptrn, count: ptrn.count, phase: 0)
			path.lineWidth = 1

			color.set()
			path.stroke()

			let pStyle = NSMutableParagraphStyle()
			pStyle.alignment = .center
			let attributes: [NSAttributedString.Key: Any] = [
				.font:            NSFont.boldSystemFont(ofSize: 0),
				.foregroundColor: color,
				.paragraphStyle:  pStyle,
			]

			let str = NSAttributedString(string: "\((index + 1) % 10)", attributes: attributes)
			let size = str.size()
			dstRect.origin.y = 0.5 * (dstRect.height - size.height)
			dstRect.size.height = size.height
			str.draw(in: dstRect.integral)

			return true
		}

		imageView?.image = image
	}

	@objc private func outlineViewItemDidExpandCollapse(_ notification: Notification) {
		guard let item = objectValue as? FFResultNode, let changed = notification.userInfo?["NSObject"] as? FFResultNode, item === changed else { return }
		countOfLeafsButton.isHidden = (notification.object as? NSOutlineView)?.isItemExpanded(item) ?? false
	}
}

// ===========================
// = FFResultsViewController =
// ===========================

@objc(FFResultsViewController)
final class FFResultsViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuItemValidation {

	private var scrollView: NSScrollView?

	// Optional, not implicitly-unwrapped, and that is a behaviour requirement
	// rather than style. In the ObjC++ this was a plain ivar, so every use before
	// -loadView ran was a message to nil: harmless, returning 0/nil/NO. Swift traps
	// instead. -selectedResults is reachable that early (Find.mm reads it, and
	// t_results_view_controller.mm caught it), so each use below reproduces what
	// nil-messaging returned.
	private var outlineView: NSOutlineView?
	private var searchResultsFont: NSFont?

	private weak var eventMonitor: AnyObject?
	private var longPressedCommandModifier = false
	private var pendingColumnWidth: CGFloat = 0

	private var lastSelectedResult: FFResultNode?

	@objc var selectResultAction: Selector?
	@objc var removeResultAction: Selector?
	@objc var doubleClickResultAction: Selector?
	@objc weak var target: AnyObject?

	// Observed by the header cells through OakTableCellView's bridge; not in the
	// public header, which is why the test reaches it by name.
	@objc dynamic var showKeyEquivalent = false

	// Bound by Find.mm:194-195 and named in
	// +keyPathsForValuesAffectingExcerptString.
	@objc dynamic var replaceString: String?
	@objc dynamic var showReplacementPreviews = false

	@objc var results: FFResultNode? {
		didSet {
			outlineView?.sizeLastColumnToFit()
			outlineView?.reloadData()
		}
	}

	@objc var hideCheckBoxes = false {
		didSet {
			guard hideCheckBoxes != oldValue else { return }
			outlineView?.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("checkbox"))?.isHidden = hideCheckBoxes
			outlineView?.outlineTableColumn = outlineView?.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(hideCheckBoxes ? "match" : "checkbox"))
		}
	}

	override func loadView() {
		guard scrollView == nil else { return }

		let fontName = UserDefaults.standard.string(forKey: kUserDefaultsSearchResultsFontNameKey)
		let fontSize = CGFloat(UserDefaults.standard.float(forKey: kUserDefaultsSearchResultsFontSizeKey)) != 0 ? CGFloat(UserDefaults.standard.float(forKey: kUserDefaultsSearchResultsFontSizeKey)) : 11.0
		searchResultsFont = fontName != nil ? NSFont(name: fontName!, size: fontSize) : NSFont.controlContentFont(ofSize: fontSize)

		let label = OakCreateLabel("m", searchResultsFont)!
		label.sizeToFit()
		let lineHeight = max(label.frame.height, ceil(searchResultsFont?.ascender ?? 0) + ceil(abs(searchResultsFont?.descender ?? 0)) + ceil(searchResultsFont?.leading ?? 0))

		let outlineView = NSOutlineView(frame: .zero)
		self.outlineView = outlineView
		outlineView.setAccessibilityLabel("Results")
		outlineView.focusRingType                      = .none
		outlineView.allowsMultipleSelection            = true
		outlineView.autoresizesOutlineColumn           = false
		outlineView.usesAlternatingRowBackgroundColors = true
		outlineView.headerView                         = nil
		outlineView.rowHeight                          = max(lineHeight, 14.0)
		outlineView.columnAutoresizingStyle            = .noColumnAutoresizing

		outlineView.style = .plain
		outlineView.floatsGroupRows = false

		var tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("checkbox"))
		tableColumn.width = 50
		outlineView.addTableColumn(tableColumn)
		outlineView.outlineTableColumn = tableColumn

		tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("match"))
		tableColumn.isEditable = false
		outlineView.addTableColumn(tableColumn)

		let scroll = NSScrollView(frame: .zero)
		scroll.hasVerticalScroller   = true
		scroll.hasHorizontalScroller = true
		scroll.autohidesScrollers    = true
		scroll.borderType            = .noBorder
		scroll.documentView          = outlineView
		scrollView = scroll

		let contentView = NSView(frame: .zero)

		let views: [String: Any] = [
			"topDivider":     OakCreateNSBoxSeparator(),
			"scrollView":     scroll,
			"bottomDividier": OakCreateNSBoxSeparator(),
		]

		OakAddAutoLayoutViewsToSuperview(views.values.compactMap { $0 as? NSView }, contentView)
		OakSetupKeyViewLoop([ contentView, outlineView ])

		NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: "H:|[scrollView]|", options: [], metrics: nil, views: views))
		NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: "V:|[topDivider(==1)][scrollView(>=50)][bottomDividier(==1)]|", options: [ .alignAllLeading, .alignAllTrailing ], metrics: nil, views: views))

		view = contentView

		outlineView.dataSource   = self
		outlineView.delegate     = self
		outlineView.target       = self
		outlineView.action       = #selector(didSingleClick(_:))
		outlineView.doubleAction = #selector(didDoubleClick(_:))
	}

	@objc private func delayedLongPressedCommandModifier(_ sender: Any?) {
		longPressedCommandModifier = true
		showKeyEquivalent = true
	}

	override func viewDidAppear() {
		eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
			guard let self else { return event }
			let modifierFlags: NSEvent.ModifierFlags = (self.outlineView?.window?.isKeyWindow ?? false) ? event.modifierFlags.intersection([ .shift, .control, .option, .command ]) : []
			if self.longPressedCommandModifier {
				self.showKeyEquivalent = modifierFlags == .command
				if modifierFlags.isEmpty {
					self.longPressedCommandModifier = false
				}
			} else {
				if modifierFlags == .command {
					self.perform(#selector(FFResultsViewController.delayedLongPressedCommandModifier(_:)), with: self, afterDelay: 0.2)
				} else {
					NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(FFResultsViewController.delayedLongPressedCommandModifier(_:)), object: self)
				}
			}
			return event
		} as AnyObject
	}

	override func viewWillDisappear() {
		if let eventMonitor {
			NSEvent.removeMonitor(eventMonitor)
		}
		eventMonitor = nil
	}

	@objc var selectedResults: [FFResultNode] {
		guard let outlineView else { return [] }

		var res: [FFResultNode] = []

		let selectedRows = outlineView.numberOfSelectedRows == 0 ? IndexSet(integersIn: 0..<max(0, outlineView.numberOfRows)) : outlineView.selectedRowIndexes
		for index in selectedRows {
			if let item = outlineView.item(atRow: index) as? FFResultNode, (item.children?.count ?? 0) == 0 {
				res.append(item)
			}
		}

		return res
	}

	@objc(insertItemsAtIndexes:)
	func insertItems(at anIndexSet: IndexSet) {
		guard let outlineView else { return }
		outlineView.beginUpdates()
		outlineView.insertItems(at: anIndexSet, inParent: nil, withAnimation: [])
		if let children = results?.children {
			for item in children.objects(at: anIndexSet) {
				outlineView.expandItem(item)
			}
		}
		outlineView.endUpdates()
	}

	@objc(showResultNode:)
	func showResultNode(_ aResultNode: FFResultNode?) {
		guard let outlineView else { return }
		guard let aResultNode else { return }

		if !outlineView.isItemExpanded(aResultNode.parent) {
			outlineView.expandItem(aResultNode.parent)
		}
		outlineView.scrollRowToVisible(outlineView.row(forItem: aResultNode.parent))

		let row = outlineView.row(forItem: aResultNode)
		if row != -1 {
			outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
			outlineView.scrollRowToVisible(row)
			outlineView.window?.makeFirstResponder(outlineView)
		}
	}

	// ==================
	// = Action Methods =
	// ==================

	@objc(selectNextResultWrapAround:)
	func selectNextResult(wrapAround: Bool) {
		guard let outlineView else { return }
		let row = outlineView.selectedRow
		var item = row == -1 ? nil : outlineView.item(atRow: row) as? FFResultNode

		item = item != nil ? (NextNode(item) ?? NextNode(item?.parent)?.firstResultNode) : results?.firstResultNode?.firstResultNode
		if item == nil, wrapAround {
			item = results?.firstResultNode?.firstResultNode
		}

		showResultNode(item)
	}

	@objc(selectPreviousResultWrapAround:)
	func selectPreviousResult(wrapAround: Bool) {
		guard let outlineView else { return }
		let row = outlineView.selectedRow
		var item = row == -1 ? nil : outlineView.item(atRow: row) as? FFResultNode

		item = item != nil ? (PreviousNode(item) ?? PreviousNode(item?.parent)?.lastResultNode) : results?.lastResultNode?.lastResultNode
		if item == nil, wrapAround {
			item = results?.lastResultNode?.lastResultNode
		}

		showResultNode(item)
	}

	@IBAction @objc func toggleCollapsedState(_ anArgument: Any?) {
		guard let outlineView else { return }
		if isCollapsed {
			outlineView.expandItem(nil, expandChildren: true)
		} else {
			outlineView.collapseItem(nil, collapseChildren: true)
		}
	}

	@IBAction @objc func selectNextDocument(_ sender: Any?) {
		guard let outlineView else { return }
		let row = outlineView.selectedRow
		let item = row == -1 ? nil : outlineView.item(atRow: row) as? FFResultNode
		showResultNode(NextNode(item?.parent)?.firstResultNode ?? results?.firstResultNode?.firstResultNode)
	}

	@IBAction @objc func selectPreviousDocument(_ sender: Any?) {
		guard let outlineView else { return }
		let row = outlineView.selectedRow
		let item = row == -1 ? nil : outlineView.item(atRow: row) as? FFResultNode
		showResultNode(PreviousNode(item?.parent)?.firstResultNode ?? results?.lastResultNode?.firstResultNode)
	}

	// ==================
	// = Helper Methods =
	// ==================

	@objc var isCollapsed: Bool {
		var expanded = 0
		if let children = results?.children {
			for parent in children {
				expanded += (outlineView?.isItemExpanded(parent) ?? false) ? 1 : 0
			}
			return children.count != 0 && 2 * expanded <= children.count
		}
		return false
	}

	// ========================
	// = Table (Cell) Actions =
	// ========================

	@objc private func toggleExcludedCheckbox(_ sender: NSButton) {
		guard let outlineView else { return }
		let row = outlineView.row(for: sender)
		guard row != -1, let item = outlineView.item(atRow: row) as? FFResultNode else { return }

		let toggleAllInGroup = OakIsAlternateKeyOrMouseEvent(NSEvent.ModifierFlags.option.rawValue, NSApp.currentEvent)
		if toggleAllInGroup {
			item.parent?.excluded = item.excluded
		}

		if showReplacementPreviews {
			var range = NSRange(location: row, length: 1)
			if toggleAllInGroup, let parent = item.parent, let first = parent.firstResultNode {
				range = NSRange(location: outlineView.row(forItem: first), length: Int(parent.countOfLeafs))
			}
			outlineView.reloadData(forRowIndexes: IndexSet(integersIn: range.location..<(range.location + range.length)), columnIndexes: IndexSet(integer: 1))
		}
	}

	@objc private func takeSearchResultToRemoveFrom(_ sender: NSButton) {
		guard let outlineView else { return }
		let row = outlineView.row(for: sender)
		guard row != -1, let item = outlineView.item(atRow: row) as? FFResultNode else { return }

		if let siblings = item.parent?.children {
			let index = siblings.index(of: item)
			if index != NSNotFound {
				outlineView.removeItems(at: IndexSet(integer: index), inParent: nil, withAnimation: [ .effectFade, .slideDown ])
			}
		}

		item.removeFromParent()
		if let removeResultAction {
			NSApp.sendAction(removeResultAction, to: target, from: item)
		}
	}

	private func didSelectResult(_ resultNode: FFResultNode?) {
		guard lastSelectedResult !== resultNode else { return }

		// Prevent sending selectResultAction twice since mouse clicks sends both
		// didSingleClick: and outlineViewSelectionDidChange:
		lastSelectedResult = resultNode
		DispatchQueue.main.async { [weak self] in
			self?.lastSelectedResult = nil
		}

		if let selectResultAction {
			NSApp.sendAction(selectResultAction, to: target, from: resultNode)
		}
	}

	@objc private func didSingleClick(_ sender: Any?) {
		guard let outlineView else { return }
		if outlineView.clickedRow != -1, outlineView.numberOfSelectedRows == 1 {
			didSelectResult(outlineView.item(atRow: outlineView.clickedRow) as? FFResultNode)
		}
	}

	@objc private func didDoubleClick(_ sender: Any?) {
		guard let outlineView else { return }
		if outlineView.clickedRow != -1, let doubleClickResultAction {
			let item = outlineView.item(atRow: outlineView.clickedRow) as? FFResultNode
			didSelectResult(item)
			NSApp.sendAction(doubleClickResultAction, to: target, from: item)
		}
	}

	func outlineViewSelectionDidChange(_ notification: Notification) {
		guard let outlineView else { return }
		if outlineView.numberOfSelectedRows == 1, let first = outlineView.selectedRowIndexes.first {
			didSelectResult(outlineView.item(atRow: first) as? FFResultNode)
		}
	}

	func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
		return !self.outlineView(outlineView, isGroupItem: item)
	}

	// ============================
	// = Outline view data source =
	// ============================

	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		return ((item as? FFResultNode) ?? results)?.children?.count ?? 0
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		return self.outlineView(outlineView, isGroupItem: item)
	}

	func outlineView(_ outlineView: NSOutlineView, child childIndex: Int, ofItem item: Any?) -> Any {
		return ((item as? FFResultNode) ?? results)!.children!.object(at: childIndex)
	}

	func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
		return outlineView.level(forItem: item) == 0
	}

	func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
		if self.outlineView(outlineView, isGroupItem: item) {
			return 22
		}
		return CGFloat((item as? FFResultNode)?.lineSpan ?? 1) * outlineView.rowHeight
	}

	@objc private func commitPendingColumnWidth(_ tableColumn: NSTableColumn) {
		guard pendingColumnWidth != 0 else { return }
		tableColumn.minWidth = min(pendingColumnWidth, tableColumn.minWidth)
		tableColumn.maxWidth = max(pendingColumnWidth, tableColumn.maxWidth)
		tableColumn.width    = pendingColumnWidth

		pendingColumnWidth = 0
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("group")
		var res = outlineView.makeView(withIdentifier: identifier, owner: self)
		let node = item as? FFResultNode

		if identifier.rawValue == "checkbox" {
			var cellView = res as? OakSearchResultsCheckboxView
			if cellView == nil {
				cellView = OakSearchResultsCheckboxView(frame: .zero)
				cellView!.identifier = identifier
				cellView!.button.action = #selector(toggleExcludedCheckbox(_:))
				cellView!.button.target = self
				res = cellView
			}
			cellView!.objectValue = node
		} else if identifier.rawValue == "match" {
			var cellView = res as? OakSearchResultsMatchCellView
			if cellView == nil {
				cellView = OakSearchResultsMatchCellView(viewController: self, font: searchResultsFont)
				cellView!.identifier = identifier
				res = cellView
			}

			cellView!.objectValue = node
			cellView!.layoutSubtreeIfNeeded()
			let width = (cellView!.textField?.frame.maxX ?? 0) + 32

			if let tableColumn, tableColumn.width < width, pendingColumnWidth < width {
				if pendingColumnWidth == 0 {
					perform(#selector(commitPendingColumnWidth(_:)), with: tableColumn, afterDelay: 0)
				}
				pendingColumnWidth = width
			}
		} else {
			var cellView = res as? OakSearchResultsHeaderCellView
			if cellView == nil {
				cellView = OakSearchResultsHeaderCellView(viewController: self)
				cellView!.identifier = identifier
				cellView!.removeButton.action = #selector(takeSearchResultToRemoveFrom(_:))
				cellView!.removeButton.target = self
				res = cellView
			}

			cellView!.objectValue = node
			cellView!.countOfLeafsButton.title = NumberFormatter.localizedString(from: NSNumber(value: node?.countOfLeafs ?? 0), number: .decimal)
			cellView!.countOfLeafsButton.isHidden = outlineView.isItemExpanded(node)
		}
		return res
	}

	// ===================
	// = Menu Validation =
	// ===================

	func validateMenuItem(_ aMenuItem: NSMenuItem) -> Bool {
		var res = true
		if aMenuItem.action == #selector(toggleCollapsedState(_:)) {
			aMenuItem.title = isCollapsed ? "Expand Results" : "Collapse Results"
			res = (results?.countOfLeafs ?? 0) != 0
		}
		return res
	}
}
