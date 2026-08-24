import AppKit

// Ported from OakChoiceMenu.mm — this framework's first Swift file, and a leaf
// rather than the editor. No boundary file was needed: the only C++ in the
// original was std::max/min/clamp and one `static std::map<SEL, NSUInteger>`.
//
// The five key-action codes did not come with it. Swift cannot export an
// `extern` constant (rule 19) and OakTextView.mm — the sole consumer — is not a
// porting candidate, so they stay in OakChoiceMenuConstants.mm permanently.
//
// `choices` is an NSArray rather than [String] deliberately. The caller hands
// over a CFArray bridged straight from a std::vector<std::string>, and the
// selection is kept across a new list with -indexOfObject:; keeping NSArray
// keeps -isEqualToArray: and -indexOfObject: exactly as they were rather than
// re-deriving them on a Swift collection.

private enum Action {
	case nop, tab, ret, cancel, moveUp, moveDown, pageUp, pageDown, moveToBeginning, moveToEnd
}

@objc(OakChoiceMenu)
class OakChoiceMenu: NSWindowController, @preconcurrency NSTableViewDataSource, @preconcurrency NSTableViewDelegate {
	private static let notFound = UInt(bitPattern: NSNotFound)

	private var tableView: NSTableView!
	private var keyAction: Action = .nop
	private var topLeftPosition: NSPoint = .zero

	@objc var font: NSFont = NSFont.controlContentFont(ofSize: 0)

	@objc var choices: NSArray = NSArray() {
		didSet {
			// The setter is not a plain store: it drops the selection, reloads, then
			// tries to find the *same string* again. Guarded on equality so that
			// re-supplying an identical list does not reset the user's place in it.
			if choices.isEqual(to: oldValue as! [Any]) {
				choices = oldValue
				return
			}

			let oldSelection = Self.selectedChoice(in: oldValue, at: _choiceIndex)
			choiceIndex = Self.notFound
			tableView.reloadData()

			let found = oldSelection.map { choices.index(of: $0) } ?? NSNotFound
			choiceIndex = UInt(bitPattern: found)

			sizeToFit()
		}
	}

	private var _choiceIndex: UInt = UInt(bitPattern: NSNotFound)

	@objc var choiceIndex: UInt {
		get { _choiceIndex }
		set {
			guard _choiceIndex != newValue else {
				return
			}

			_choiceIndex = newValue
			if _choiceIndex == Self.notFound {
				tableView.deselectAll(self)
			}
			else {
				tableView.selectRowIndexes(IndexSet(integer: Int(_choiceIndex)), byExtendingSelection: false)
				tableView.scrollToVisible(tableView.rect(ofRow: Int(_choiceIndex)))
			}
		}
	}

	@objc var selectedChoice: String? {
		Self.selectedChoice(in: choices, at: _choiceIndex) as? String
	}

	private static func selectedChoice(in array: NSArray, at index: UInt) -> Any? {
		index == notFound ? nil : array.object(at: Int(index))
	}

	// MARK: - Construction

	@objc init() {
		super.init(window: NSPanel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false))

		window?.hasShadow          = true
		window?.level              = .statusBar
		window?.ignoresMouseEvents = true

		let tableView = NSTableView(frame: .zero)
		tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("mainColumn")))
		tableView.style                   = .plain
		tableView.headerView              = nil
		tableView.focusRingType           = .none
		tableView.autoresizingMask        = [.width, .height]
		tableView.allowsMultipleSelection = true
		tableView.dataSource              = self
		tableView.delegate                = self
		tableView.backgroundColor         = .clear
		tableView.reloadData()
		self.tableView = tableView

		let scrollView = NSScrollView(frame: .zero)
		scrollView.hasVerticalScroller   = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers    = true
		scrollView.borderType            = .noBorder
		scrollView.documentView          = tableView
		scrollView.autoresizingMask      = [.width, .height]
		scrollView.drawsBackground       = false

		let effectView = NSVisualEffectView(frame: .zero)
		effectView.autoresizingMask = [.width, .height]
		effectView.material         = .menu
		effectView.blendingMode     = .behindWindow

		effectView.addSubview(scrollView, positioned: .below, relativeTo: nil)

		window?.contentView = effectView
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
		// A window controller is deallocated on the main thread; -close is
		// MainActor-isolated and deinit is not.
		MainActor.assumeIsolated {
			close()
		}
	}

	// MARK: - Sizing

	private func sizeToFit() {
		let kTableViewPadding: CGFloat = 4
		let kScrollBarWidth: CGFloat   = 15

		guard let textField = OakCreateLabel("", font, .left, .byTruncatingTail) else {
			return
		}
		if choices.count == 0 {
			textField.sizeToFit()
		}

		var width: CGFloat = 60
		for i in 0..<min(choices.count, 256) {
			textField.stringValue = choices.object(at: i) as? String ?? ""
			textField.sizeToFit()
			width = max(width, kTableViewPadding + textField.frame.width)
		}

		tableView.rowHeight = textField.frame.height

		if choices.count > 10 {
			width += kScrollBarWidth
		}

		let height = CGFloat(min(choices.count, 10)) * (tableView.rowHeight + tableView.intercellSpacing.height)
		guard let window else {
			return
		}
		window.setFrame(NSRect(x: window.frame.minX, y: window.frame.maxY - height, width: min(ceil(width), 400), height: height), display: true)
	}

	@objc private dynamic func viewBoundsDidChange(_ notification: Notification) {
		guard let clipView = notification.object as? NSClipView, let view = clipView.documentView else {
			return
		}
		window?.setFrameTopLeftPoint(view.window?.convertToScreen(view.convert(NSRect(origin: topLeftPosition, size: .zero), to: nil)).origin ?? .zero)
	}

	// MARK: - Showing

	@objc(showAtTopLeftPoint:forView:)
	func show(atTopLeftPoint point: NSPoint, for view: NSView) {
		window?.setFrameTopLeftPoint(point)

		if _choiceIndex != Self.notFound {
			tableView.selectRowIndexes(IndexSet(integer: Int(_choiceIndex)), byExtendingSelection: false)
		}

		sizeToFit()

		topLeftPosition = view.convert(view.window?.convertFromScreen(NSRect(origin: point, size: .zero)) ?? .zero, from: nil).origin
		NotificationCenter.default.addObserver(self, selector: #selector(viewBoundsDidChange(_:)), name: NSView.boundsDidChangeNotification, object: view.enclosingScrollView?.contentView)
		if let window {
			view.window?.addChildWindow(window, ordered: .above)
			window.orderFront(self)
		}
	}

	@objc var isVisible: Bool {
		window?.isVisible ?? false
	}

	// MARK: - NSTableView data source and delegate

	func numberOfRows(in tableView: NSTableView) -> Int {
		choices.count
	}

	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
		choices.object(at: row)
	}

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard let identifier = tableColumn?.identifier else {
			return nil
		}
		if let res = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
			return res
		}
		let res = OakCreateLabel("", font, .left, .byTruncatingTail)
		res?.identifier = identifier
		return res
	}

	// MARK: - The keyboard contract

	@objc(didHandleKeyEvent:)
	func didHandleKeyEvent(_ event: NSEvent) -> UInt {
		var res = OakChoiceMenuKeyUnused
		guard window != nil else {
			return res
		}

		// Reset *before* interpreting, which is what makes -doCommandBySelector:
		// do nothing observable on its own — a command primed by an earlier call is
		// discarded here rather than fired late.
		keyAction = .nop
		interpretKeyEvents([event])
		if case .nop = keyAction {
			return res
		}

		var offset = 0
		let visibleRows = Int(floor(tableView.visibleRect.height / (tableView.rowHeight + tableView.intercellSpacing.height))) - 1
		res = OakChoiceMenuKeyMovement
		switch keyAction {
			case .moveUp:          offset = -1
			case .moveDown:        offset = +1
			case .pageUp:          offset = -visibleRows
			case .pageDown:        offset = +visibleRows
			case .moveToBeginning: offset = -(Int(Int32.max) >> 1)
			case .moveToEnd:       offset = +(Int(Int32.max) >> 1)
			case .ret:             res = OakChoiceMenuKeyReturn
			case .tab:             res = OakChoiceMenuKeyTab
			case .cancel:          res = OakChoiceMenuKeyCancel
			case .nop:             break
		}

		if res == OakChoiceMenuKeyMovement {
			// The seed when nothing is selected is a conditional, not a constant:
			// -1 going down and `count` going up, so the first arrow lands on the
			// first or last row rather than skipping one.
			let current = _choiceIndex == Self.notFound ? (offset > 0 ? -1 : choices.count) : Int(_choiceIndex)
			choiceIndex = UInt(bitPattern: min(max(current + offset, 0), choices.count - 1))
		}

		return res
	}

	// Twenty selectors into ten actions, including every AndModifySelection and
	// scroll* twin — shift-arrow arrives as -moveDownAndModifySelection: because
	// the text view still owns the selection while this menu is up.
	private static let actions: [Selector: Action] = [
		#selector(NSResponder.insertNewline(_:)):                               .ret,
		#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):            .ret,
		#selector(NSResponder.insertTab(_:)):                                   .tab,
		#selector(NSResponder.cancelOperation(_:)):                             .cancel,
		#selector(NSResponder.moveUp(_:)):                                      .moveUp,
		#selector(NSResponder.moveDown(_:)):                                    .moveDown,
		#selector(NSResponder.moveUpAndModifySelection(_:)):                    .moveUp,
		#selector(NSResponder.moveDownAndModifySelection(_:)):                  .moveDown,
		#selector(NSResponder.pageUp(_:)):                                      .pageUp,
		#selector(NSResponder.pageDown(_:)):                                    .pageDown,
		#selector(NSResponder.pageUpAndModifySelection(_:)):                    .pageUp,
		#selector(NSResponder.pageDownAndModifySelection(_:)):                  .pageDown,
		#selector(NSResponder.moveToBeginningOfDocument(_:)):                   .moveToBeginning,
		#selector(NSResponder.moveToEndOfDocument(_:)):                         .moveToEnd,
		#selector(NSResponder.moveToBeginningOfDocumentAndModifySelection(_:)): .moveToBeginning,
		#selector(NSResponder.moveToEndOfDocumentAndModifySelection(_:)):       .moveToEnd,
		#selector(NSResponder.scrollPageUp(_:)):                                .pageUp,
		#selector(NSResponder.scrollPageDown(_:)):                              .pageDown,
		#selector(NSResponder.scrollToBeginningOfDocument(_:)):                 .moveToBeginning,
		#selector(NSResponder.scrollToEndOfDocument(_:)):                       .moveToEnd,
	]

	override func doCommand(by selector: Selector) {
		if let action = Self.actions[selector] {
			keyAction = action
		}
	}

	// Swallows text so a keystroke the menu does not act on is not inserted twice.
	override func insertText(_ insertString: Any) {
	}
}
