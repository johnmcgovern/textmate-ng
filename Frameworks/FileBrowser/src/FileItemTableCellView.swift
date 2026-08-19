import AppKit

// The file browser's row view: an open-in-place icon button, an editable name
// field, the Finder-tag crescents, and a close button — laid out in a stack and
// driven almost entirely by bindings.
//
// This is the framework's first bindings-heavy port, so rule 1 is the whole
// game: any property this view's own bindings observe and that Swift itself
// writes must be `@objc dynamic`, or the write bypasses the KVO swizzle and the
// binding never fires. Here that property is `fileReference` — the root of the
// "fileReference.icon" and "fileReference.closable" key paths — and it is set
// from -observeValue(forKeyPath:), i.e. from Swift. Everything else the bindings
// read hangs off `objectValue` (a FileItem, still ObjC and KVO-compliant) or off
// TMFileReference, so only `fileReference` needs `dynamic`.
//
// FileItemTableCellView.h stays a hand-written ObjC declaration of the class;
// the FileItem(EditingName) binding support stays ObjC++ in FileItemEditingName.

// A text-field cell that, when it begins editing a filename, selects the
// basename and leaves the extension unselected.
private final class FileItemSelectBasenameCell: NSTextFieldCell {
	override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
		var path = self.stringValue
		if let first = (self.objectValue as? NSArray)?.firstObject as? String {
			path = first
		}
		let basename = (path as NSString).deletingPathExtension
		let length = selStart == 0 ? min((basename as NSString).length, selLength) : selLength
		super.select(withFrame: rect, in: controlView, editor: textObj, delegate: delegate, start: selStart, length: length)
	}
}

// Bridges the cell's model (a FileItem, via editingAndDisplayName) to the text
// field: the display name for showing, the filename for editing.
private final class FileItemFormatter: Formatter {
	weak var tableCellView: NSTableCellView?

	init(tableCellView: NSTableCellView) {
		self.tableCellView = tableCellView
		super.init()
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func string(for obj: Any?) -> String? {
		return (tableCellView?.objectValue as? FileItem)?.editingAndDisplayName.last as? String
	}

	override func editingString(for obj: Any) -> String {
		return ((tableCellView?.objectValue as? FileItem)?.editingAndDisplayName.first as? String) ?? ""
	}

	override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
		obj?.pointee = string as NSString
		return true
	}
}

// Draws up to three overlapping Finder-tag color dots (crescents where they
// overlap). finderTags and rightPadding are binding targets (set via KVC), so
// both are @objc; backgroundStyle is set directly by the cell view.
class FileItemFinderTagsView: NSView {
	private var storedFinderTags: [OakFinderTag] = []
	@objc var finderTags: [OakFinderTag] {
		get { return storedFinderTags }
		set {
			if (storedFinderTags as NSArray).isEqual(to: newValue) {
				return
			}
			storedFinderTags = newValue
			isHidden = storedFinderTags.isEmpty
			needsDisplay = true
		}
	}

	var backgroundStyle: NSView.BackgroundStyle = .normal {
		didSet { needsDisplay = true }
	}

	@objc var rightPadding: Bool = false {
		didSet { invalidateIntrinsicContentSize() }
	}

	// tags reaching here have passed the hasLabelColor filter, so labelColor is a
	// real color — the ObjC++ also handled a nil color, but that branch was dead.
	private func fillAndStroke(_ path: NSBezierPath, tag: OakFinderTag) {
		let rgbColor = tag.labelColor.usingColorSpace(.sRGB)!
		let factor: CGFloat = 0.8
		let fillColor = NSColor(srgbRed: 1 - factor*(1 - rgbColor.redComponent), green: 1 - factor*(1 - rgbColor.greenComponent), blue: 1 - factor*(1 - rgbColor.blueComponent), alpha: 1.0)

		fillColor.set()
		path.fill()

		if backgroundStyle == .emphasized {
			NSColor.white.set()
		} else {
			tag.labelColor.set()
		}
		path.stroke()
	}

	private func drawCrescent(center1: NSPoint, center2: NSPoint, tag: OakFinderTag) {
		NSGraphicsContext.saveGraphicsState()

		let clippingPath = NSBezierPath()
		clippingPath.appendArc(withCenter: center2, radius: 5.0, startAngle: -100, endAngle: 100)
		clippingPath.appendArc(withCenter: center1, radius: 5.5, startAngle: 60, endAngle: 300, clockwise: true)
		clippingPath.addClip()

		let path = NSBezierPath()
		path.appendArc(withCenter: center2, radius: 4.0, startAngle: 0, endAngle: 360)
		path.close()

		fillAndStroke(path, tag: tag)

		NSGraphicsContext.restoreGraphicsState()
	}

	override func draw(_ dirtyRect: NSRect) {
		let tagsWithLabelColor = finderTags.filter { $0.hasLabelColor() }

		var r = bounds
		r.size.width -= rightPadding ? 16 : 0

		switch tagsWithLabelColor.count {
		case 0:
			return
		case 1:
			let path = NSBezierPath()
			path.appendArc(withCenter: NSMakePoint(NSMidX(r), NSMidY(r)), radius: 4.0, startAngle: 0, endAngle: 360)
			fillAndStroke(path, tag: tagsWithLabelColor[0])
		case 2:
			let center = NSMakePoint(NSMidX(r), NSMidY(r))
			let center1 = NSMakePoint(center.x - 2.0, center.y)
			let center2 = NSMakePoint(center.x + 2.0, center.y)

			drawCrescent(center1: center1, center2: center2, tag: tagsWithLabelColor[0])

			let path = NSBezierPath()
			path.appendArc(withCenter: center1, radius: 4.0, startAngle: 0, endAngle: 360)
			fillAndStroke(path, tag: tagsWithLabelColor[1])
		default:
			let center = NSMakePoint(NSMidX(r), NSMidY(r))
			let center1 = NSMakePoint(center.x - 4.0, center.y)
			let center2 = NSMakePoint(center.x, center.y)
			let center3 = NSMakePoint(center.x + 4.0, center.y)

			let lastIndex = tagsWithLabelColor.count - 1
			drawCrescent(center1: center2, center2: center3, tag: tagsWithLabelColor[lastIndex - 2])
			drawCrescent(center1: center1, center2: center2, tag: tagsWithLabelColor[lastIndex - 1])

			let path = NSBezierPath()
			path.appendArc(withCenter: center1, radius: 4.0, startAngle: 0, endAngle: 360)
			fillAndStroke(path, tag: tagsWithLabelColor[lastIndex])
		}
	}

	override var intrinsicContentSize: NSSize {
		return NSMakeSize((rightPadding ? 16 : 0) + 20, 10)
	}
}

@objc(FileItemTableCellView)
class FileItemTableCellView: NSTableCellView, NSTextFieldDelegate {
	@objc var openButton: NSButton!
	@objc var closeButton: NSButton!

	private var finderTagsView: FileItemFinderTagsView!
	@objc dynamic var fileReference: TMFileReference?

	@objc override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		commonInit()
	}

	@objc convenience init() {
		self.init(frame: .zero)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private func commonInit() {
		openButton = NSButton(frame: .zero)
		openButton.refusesFirstResponder = true
		openButton.setButtonType(.momentaryChange)
		openButton.isBordered = false
		openButton.imagePosition = .imageOnly
		openButton.imageScaling = .scaleProportionallyUpOrDown

		openButton.widthAnchor.constraint(equalToConstant: 16).isActive = true
		openButton.heightAnchor.constraint(equalToConstant: 16).isActive = true

		let textField = OakCreateLabel("", NSFont.controlContentFont(ofSize: 0), .left, .byTruncatingMiddle)!
		let cell = FileItemSelectBasenameCell(textCell: "")
		cell.wraps = false
		cell.lineBreakMode = .byTruncatingMiddle
		textField.cell = cell
		textField.formatter = FileItemFormatter(tableCellView: self)

		finderTagsView = FileItemFinderTagsView(frame: .zero)

		closeButton = OakCreateCloseButton("Close document")
		closeButton.refusesFirstResponder = true

		let stackView = NSStackView(views: [openButton, textField, finderTagsView, closeButton])
		stackView.spacing = 4

		addSubview(stackView)

		textField.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: NSLayoutConstraint.Priority.defaultLow.rawValue - 1), for: .horizontal)

		stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4).isActive = true
		stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8).isActive = true
		stackView.topAnchor.constraint(equalTo: topAnchor, constant: 0).isActive = true
		stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0).isActive = true

		openButton.bind(.image, to: self, withKeyPath: "fileReference.icon", options: nil)
		textField.bind(.value, to: self, withKeyPath: "objectValue.editingAndDisplayName", options: nil)
		textField.bind(.editable, to: self, withKeyPath: "objectValue.canRename", options: nil)
		textField.bind(.toolTip, to: self, withKeyPath: "objectValue.toolTip", options: nil)
		finderTagsView.bind(NSBindingName("finderTags"), to: self, withKeyPath: "objectValue.finderTags", options: nil)
		finderTagsView.bind(NSBindingName("rightPadding"), to: self, withKeyPath: "fileReference.closable", options: [.valueTransformerName: NSValueTransformerName.negateBooleanTransformerName])
		closeButton.bind(.hidden, to: self, withKeyPath: "fileReference.closable", options: [.valueTransformerName: NSValueTransformerName.negateBooleanTransformerName])

		self.textField = textField

		addObserver(self, forKeyPath: "objectValue.URL", options: [.new], context: nil)
	}

	override var backgroundStyle: NSView.BackgroundStyle {
		get { return super.backgroundStyle }
		set {
			finderTagsView.backgroundStyle = newValue
			super.backgroundStyle = newValue
		}
	}

	deinit {
		// The ObjC++ did this teardown in -dealloc: drop the URL observation and
		// the bindings, so the observed FileItem/TMFileReference are not left with
		// a dangling observer when this cell (which the outline view reuses) goes
		// away. A @MainActor class cannot touch its own state from a nonisolated
		// deinit under Swift 6, but an NSView is always deallocated on the main
		// thread, so assumeIsolated is the sanctioned way to say so.
		MainActor.assumeIsolated {
			removeObserver(self, forKeyPath: "objectValue.URL")

			openButton?.unbind(.image)
			textField?.unbind(.value)
			textField?.unbind(.editable)
			textField?.unbind(.toolTip)
			finderTagsView?.unbind(NSBindingName("finderTags"))
			closeButton?.unbind(.hidden)
		}
	}

	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		if keyPath == "objectValue.URL" {
			if let url = change?[.newKey] as? NSURL {
				fileReference = TMFileReference(url: url as URL)
			} else {
				fileReference = nil
			}
		} else {
			super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
		}
	}

	override func resetCursorRects() {
		addCursorRect(openButton.frame, cursor: .pointingHand)
	}
}
