import AppKit

// Ported from EncodingView.mm — the "Unknown Encoding" sheet OakDocument runs
// when a file's bytes decode as nothing it recognises: a preview of the bytes
// in the chosen encoding with the non-ASCII lines and characters marked, an
// encoding pop-up, and an Open button that is enabled only when every byte
// decoded. Pinned by t_encoding_view.mm, written first.
//
// EncodingView.h stays as the hand-written declaration (rule 23) for the one
// ObjC++ consumer, OakDocument.mm. The preview itself is EncodingViewSupport,
// the C++ transcode-and-highlight pass the previous commit put behind a
// boundary (rule 25).
//
// The three bound properties are `@objc dynamic` (rule 1): the pop-up, the
// check box and the Open button bind through an NSObjectController whose
// content is this controller, and the pop-up pushes its choice back the same
// way. The controls are `@objc` so the pins can reach them through
// EncodingViewTesting.h.

@MainActor private func MyCreateTextView() -> NSTextView {
	let res = NSTextView(frame: .zero)
	res.isVerticallyResizable   = true
	res.isHorizontallyResizable = true
	res.autoresizingMask        = [.width, .height]
	res.textContainer?.widthTracksTextView = false
	res.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
	return res
}

// The window's content view, which hands -updateConstraints to the controller
// that owns the constraints. `delegate` was an untyped `id`; it only ever held
// the controller.
class EncodingContentView: NSView {
	weak var delegate: EncodingWindowController?

	override var intrinsicContentSize: NSSize {
		return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
	}

	override func updateConstraints() {
		super.updateConstraints()
		delegate?.updateConstraints()
	}
}

@objc(EncodingWindowController)
class EncodingWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
	private let data: Data

	@objc private(set) var objectController: NSObjectController!
	@objc private(set) var title: NSTextField!
	@objc private(set) var explanation: NSTextField!
	@objc private(set) var label: NSTextField!
	@objc private(set) var popUpButton: OakEncodingPopUpButton!
	@objc private(set) var scrollView: NSScrollView!
	@objc private(set) var textView: NSTextView!
	@objc private(set) var learnCheckBox: NSButton!
	@objc private(set) var openButton: NSButton!
	@objc private(set) var cancelButton: NSButton!
	private var contentView: EncodingContentView!
	private var myConstraints: [NSLayoutConstraint]?

	// The setter re-renders the preview, unless nothing changed.
	private var encodingStorage: String?
	@objc dynamic var encoding: String? {
		get { encodingStorage }
		set {
			if encodingStorage == newValue {
				return
			}
			encodingStorage = newValue
			updateTextView()
		}
	}

	// Same as encoding except there will never be a //BOM modifier
	@objc var encodingNoBOM: String? {
		return encodingStorage?.replacingOccurrences(of: "//BOM", with: "")
	}

	// The setter writes the explanation; the initial "untitled" was assigned to
	// the ivar and never reached the label, which is kept: the label is empty
	// until OakDocument names the file.
	private var displayNameStorage: String?
	@objc dynamic var displayName: String? {
		get { displayNameStorage }
		set {
			displayNameStorage = newValue
			explanation.stringValue = "The file “\(newValue ?? "")” contains characters with unknown encoding.\nPlease select the encoding which should be used to open the file.\nThe contents of the file is shown below with the relevant lines highlighted.\nBefore proceeding, check that the chosen encoding makes the preview look correct."
		}
	}

	@objc dynamic var acceptableEncoding: Bool = false
	@objc dynamic var trainClassifier: Bool = false

	@objc(initWithData:)
	init(data: Data) {
		self.data = data
		super.init(window: NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false))

		encodingStorage    = "ISO-8859-1"
		displayNameStorage = "untitled"
		trainClassifier    = true

		objectController = NSObjectController(content: self)

		title         = OakCreateLabel("Unknown Encoding", NSFont.boldSystemFont(ofSize: 0), .left, .byTruncatingMiddle)
		explanation   = OakCreateLabel("", nil, .left, .byTruncatingMiddle)
		label         = OakCreateLabel("Encoding:", nil, .left, .byTruncatingMiddle)
		popUpButton   = OakEncodingPopUpButton(frame: .zero, pullsDown: false)
		scrollView    = NSScrollView(frame: .zero)
		textView      = MyCreateTextView()
		learnCheckBox = OakCreateCheckBox("Use document for training encoding classifier")
		openButton    = OakCreateButton("Open", .rounded)
		cancelButton  = OakCreateButton("Cancel", .rounded)

		label.setContentHuggingPriority(.required, for: .horizontal)
		popUpButton.setContentHuggingPriority(.defaultLow, for: .horizontal)

		scrollView.hasVerticalScroller   = true
		scrollView.hasHorizontalScroller = true
		scrollView.autohidesScrollers    = true
		scrollView.borderType            = .bezelBorder
		scrollView.documentView          = textView

		textView.isEditable         = false
		textView.delegate           = self
		openButton.action           = #selector(performOpenDocument(_:))
		cancelButton.action         = #selector(performCancelOperation(_:))
		cancelButton.keyEquivalent  = "\u{1B}"

		let contentView = EncodingContentView(frame: .zero)
		contentView.delegate = self
		contentView.autoresizingMask = [.width, .height]
		self.contentView = contentView

		OakAddAutoLayoutViewsToSuperview(Array(allViews.values), contentView)

		window?.contentView?.addSubview(contentView)
		window?.defaultButtonCell = openButton.cell as? NSButtonCell
		window?.delegate = self

		popUpButton.bind(NSBindingName("encoding"), to: objectController!, withKeyPath: "content.encoding", options: nil)
		learnCheckBox.bind(.value,   to: objectController!, withKeyPath: "content.trainClassifier",    options: nil)
		openButton.bind(.enabled,    to: objectController!, withKeyPath: "content.acceptableEncoding", options: nil)

		updateTextView()
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	@objc(beginSheetModalForWindow:completionHandler:)
	func beginSheetModal(for aWindow: NSWindow, completionHandler callback: @escaping (NSApplication.ModalResponse) -> Void) {
		window?.layoutIfNeeded()
		if let window {
			aWindow.beginSheet(window, completionHandler: callback)
		}
	}

	func textView(_ aTextView: NSTextView, doCommandBy aSelector: Selector) -> Bool {
		let res = aSelector == #selector(NSResponder.insertNewline(_:)) && !aTextView.isEditable && window?.defaultButtonCell != nil
		if res {
			window?.defaultButtonCell?.performClick(self)
		}
		return res
	}

	private var allViews: [String: NSView] {
		return [
			"title":       title,
			"explanation": explanation,
			"label":       label,
			"popUp":       popUpButton,
			"textView":    scrollView,
			"learn":       learnCheckBox,
			"open":        openButton,
			"cancel":      cancelButton,
		]
	}

	@objc func updateConstraints() {
		if let myConstraints {
			contentView.removeConstraints(myConstraints)
		}
		var constraints: [NSLayoutConstraint] = []

		let views = allViews
		func constraint(_ str: String, _ align: NSLayoutConstraint.FormatOptions) {
			constraints += NSLayoutConstraint.constraints(withVisualFormat: str, options: align, metrics: nil, views: views)
		}

		constraint("H:|-[title]-|",                          .alignAllLastBaseline)
		constraint("H:|-[explanation]-|",                    .alignAllLastBaseline)
		constraint("H:|-[label]-[popUp]-|",                  .alignAllLastBaseline)
		constraint("H:|-[textView(>=100)]-|",                [])
		constraint("H:|-[learn]-|",                          [])
		constraint("H:[cancel]-[open]-|",                    .alignAllLastBaseline)
		constraint("V:|-[title]-[explanation]-[popUp]-[textView(>=100)]-[learn]-[open]-|", .alignAllRight)

		contentView.addConstraints(constraints)
		myConstraints = constraints
	}

	private func updateTextView() {
		var couldConvert: ObjCBool = true
		if let preview = EncodingViewSupport.preview(for: data, length: 256*1024, encoding: encodingNoBOM ?? "", couldConvert: &couldConvert) {
			textView.textStorage?.setAttributedString(preview)
		}
		acceptableEncoding = couldConvert.boolValue
	}

	private func cleanup() {
		contentView.delegate     = nil
		objectController.content = nil
	}

	@objc func performOpenDocument(_ sender: Any?) {
		window?.sheetParent?.endSheet(window!, returnCode: .OK)
		cleanup()
	}

	@objc func performCancelOperation(_ sender: Any?) {
		window?.sheetParent?.endSheet(window!, returnCode: .cancel)
		cleanup()
	}
}
