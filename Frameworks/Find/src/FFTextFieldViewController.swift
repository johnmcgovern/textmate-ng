import AppKit

// Ported from FFTextFieldViewController.mm — the find and replace fields, with
// syntax highlighting, history, and the auto-sizing that lets them grow to a few
// lines.
//
// No hand-written header: Find.swift is the only consumer and it is in this
// module, so FFTextFieldViewController.h is gone along with its line in
// Find-Bridging-Header.h (rule 43). The tests reach it through FindTesting.h.
//
// **`stringValue` and `hasFocus` are `@objc dynamic` and must stay that way.**
// Find.swift binds its results controller to both:
//
//     resultsViewController.bind("replaceString",           to: …, withKeyPath: "stringValue")
//     resultsViewController.bind("showReplacementPreviews", to: …, withKeyPath: "hasFocus")
//
// Without `dynamic` there is no KVO, nothing fails to compile, and the replace
// preview silently stops following the field — rule 64. Pinned in
// t_find_view_controllers.mm through Cocoa Bindings, which is the mechanism in
// use.

// ==========================
// = OakAutoSizingTextField =
// ==========================

private class OakAutoSizingTextField: NSTextField {
	var myIntrinsicContentSize: NSSize = .zero

	override var intrinsicContentSize: NSSize {
		return NSEqualSizes(myIntrinsicContentSize, .zero) ? super.intrinsicContentSize : myIntrinsicContentSize
	}

	// Grows with the string, between one line and about ten. The clamp is the
	// behaviour: an unbounded field swallows the window on a long regexp.
	func updateIntrinsicContentSize(toEncompass aString: String?) {
		guard let cell = self.cell?.copy() as? NSTextFieldCell else { return }
		cell.stringValue = aString ?? ""

		let height = cell.cellSize(forBounds: NSMakeRect(0, 0, NSWidth(bounds), .greatestFiniteMagnitude)).height
		myIntrinsicContentSize = NSMakeSize(NSView.noIntrinsicMetric, max(22, min(height, 225)))
		invalidateIntrinsicContentSize()
	}
}

// =============================
// = FFTextFieldViewController =
// =============================

@objc(FFTextFieldViewController)
@MainActor
class FFTextFieldViewController: NSViewController, NSTextFieldDelegate, NSTextStorageDelegate, NSPopoverDelegate {
	// Same shape as BundleItemChooser's observer context: a unique address, and
	// nonisolated(unsafe) because a KVO context is a bare pointer with no
	// isolation of its own.
	nonisolated(unsafe) private static let firstResponderContext = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

	private var _textField: OakAutoSizingTextField?
	private var _syntaxFormatter: OakSyntaxFormatter?
	private let pasteboard: OakPasteboard?
	private let grammarName: String?
	private var popover: NSPopover?

	@objc init(pasteboard: OakPasteboard?, grammarName: String?) {
		self.pasteboard  = pasteboard
		self.grammarName = grammarName
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private var _syntaxHighlightEnabled = false
	@objc var syntaxHighlightEnabled: Bool {
		get { _syntaxHighlightEnabled }
		set {
			guard _syntaxHighlightEnabled != newValue else { return }

			_syntaxHighlightEnabled = newValue
			// The *ivar*, not the lazy accessor: if no formatter has been created yet
			// this is a no-op, exactly as messaging a nil ivar was (rule 33). Creating
			// one here would change when the grammar is first parsed.
			_syntaxFormatter?.enabled = newValue

			// Re-format current value
			if _textField?.currentEditor() == nil {
				let currentString = _textField?.stringValue
				_textField?.objectValue = nil
				_textField?.objectValue = currentString
			}

			addStylesToFieldEditor()
		}
	}

	private var _hasFocus = false
	@objc dynamic var hasFocus: Bool {
		get { _hasFocus }
		set {
			_hasFocus = newValue
			if newValue, let textView = _textField?.currentEditor() as? NSTextView {
				textView.textStorage?.delegate = self
				addStylesToFieldEditor()
			}
		}
	}

	private var _stringValue: String?
	@objc dynamic var stringValue: String? {
		get { _stringValue }
		set {
			// `[_stringValue isEqualToString:newStringValue]` — messaging a nil
			// _stringValue answered NO and fell through, so the early return only
			// applies when there *is* a current value and it matches.
			if let current = _stringValue, current == newValue {
				return
			}
			_stringValue = newValue
			showPopover(with: nil)
			_textField?.updateIntrinsicContentSize(toEncompass: newValue)

			// Pushes the new value back out through this object's own `stringValue`
			// binding. Bindings do not do this for a plain property, and it is why
			// typing in the field updates the window's model. Pinned.
			if let info = infoForBinding(NSBindingName("stringValue")) {
				let controller = info[.observedObject]
				let keyPath = info[.observedKeyPath] as? String
				if let controller, !(controller is NSNull), let keyPath {
					let oldValue = (controller as AnyObject).value(forKeyPath: keyPath)
					if oldValue == nil || !((oldValue as AnyObject).isEqual(newValue)) {
						(controller as AnyObject).setValue(newValue, forKeyPath: keyPath)
					}
				}
			}
		}
	}

	@objc func showHistory(_ sender: Any?) {
		if OakPasteboardSelector.sharedInstance.window?.isVisible != true {
			if let textField = _textField {
				pasteboard?.selectItem(forControl: textField)
			}
		}
	}

	@objc(showPopoverWithString:)
	func showPopover(with aString: String?) {
		guard let aString else {
			popover?.close()
			popover = nil
			return
		}

		if popover == nil {
			let viewController = NSViewController()
			viewController.view = OakCreateLabel()

			let newPopover = NSPopover()
			newPopover.behavior = .transient
			newPopover.contentViewController = viewController
			newPopover.delegate = self
			popover = newPopover
		}

		if let textField = popover?.contentViewController?.view as? NSTextField {
			textField.stringValue = aString
			textField.sizeToFit()
		}

		if let textField = _textField {
			popover?.show(relativeTo: .zero, of: textField, preferredEdge: .maxY)
		}
	}

	func popoverDidClose(_ notification: Notification) {
		popover = nil
	}

	// Optional because -initWithGrammarName: carries no nullability annotation and
	// so imports as failable (rule 44). The ObjC assigned the result straight to a
	// nil-tolerant ivar and to NSTextField.formatter, both of which take nil.
	private var syntaxFormatter: OakSyntaxFormatter? {
		if let _syntaxFormatter {
			return _syntaxFormatter
		}
		let formatter = OakSyntaxFormatter(grammarName: grammarName)
		_syntaxFormatter = formatter
		return formatter
	}

	private var textField: OakAutoSizingTextField {
		if let _textField {
			return _textField
		}
		let field = OakAutoSizingTextField(frame: .zero)
		field.font      = OakControlFont()
		field.formatter = syntaxFormatter
		field.delegate  = self
		field.cell?.wraps = true
		_textField = field
		return field
	}

	override func loadView() {
		self.view = textField
	}

	override func viewDidAppear() {
		view.window?.addObserver(self, forKeyPath: "firstResponder", options: [], context: Self.firstResponderContext)
		textField.bind(NSBindingName.value, to: self, withKeyPath: "stringValue", options: [.continuouslyUpdatesValue: true])
	}

	override func viewWillDisappear() {
		textField.unbind(NSBindingName.value)
		view.window?.removeObserver(self, forKeyPath: "firstResponder", context: Self.firstResponderContext)
	}

	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		if context == Self.firstResponderContext {
			let firstResponder = view.window?.firstResponder
			hasFocus = firstResponder === _textField || (firstResponder != nil && firstResponder === _textField?.currentEditor())
		}
	}

	func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
		if commandSelector == #selector(NSResponder.moveDown(_:)) {
			let lastNewline    = (textView.string as NSString).range(of: "\n", options: .backwards)
			let insertionPoint = (textView.selectedRanges.last as? NSRange) ?? textView.selectedRange()

			if lastNewline.location == NSNotFound || lastNewline.location < NSMaxRange(insertionPoint) {
				showHistory(self)
				return true
			}
		}
		return false
	}

	// The notification-shaped delegate method, kept at exactly the selector the
	// ObjC++ used. Deliberately *not* swapped for the modern
	// -textStorage:didProcessEditing:range:changeInLength:: whichever of the two
	// AppKit actually calls here, it called that one before and calls the same one
	// now. Changing which callback fires is a behaviour change, not a translation.
	//
	// `override` because AppKit declares this on NSObject itself, as part of the
	// informal notification-shaped delegate protocol — which also settles the
	// question above: this is the callback that fires, and it fired before.
	override func textStorageDidProcessEditing(_ aNotification: Notification) {
		addStylesToFieldEditor()
	}

	private func addStylesToFieldEditor() {
		// The ivar again, and every link in the chain was nil-tolerant in ObjC: no
		// formatter, no editor, or no text storage each meant "do nothing".
		if let textStorage = (_textField?.currentEditor() as? NSTextView)?.textStorage {
			_syntaxFormatter?.addStyles(to: textStorage)
		}
	}
}
