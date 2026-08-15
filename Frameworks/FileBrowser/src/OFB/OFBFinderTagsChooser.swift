import AppKit

// The Finder-tags swatch row shown as a menu item's view in the file browser's
// action menu: one round swatch per favorite tag, a check when a tag is applied,
// an × on hover when it would be removed, and a caption that tracks the hover.
//
// Ported straight to Swift — no C++ was involved. The one shape change: the
// ObjC++ had a private OFBFinderTagImage : NSImage whose only method was a
// factory that returned a plain NSImage (via +imageWithSize:flipped:drawingHandler:),
// so the subclass carried nothing; it collapses to the private drawing function
// below. OFBFinderTagsChooser.h stays a hand-written ObjC declaration of the
// class, imported unchanged by FileBrowserViewController.mm.

private let SwatchButtonWidth: CGFloat = 24

// The swatch image: a filled ring in the tag's color, with a check (applied), an
// × (hover-to-remove) or a + (hover-to-add) drawn inside. A nil color is the
// "no color" tag — a hollow ring in the secondary label color.
private func finderTagSwatchImage(size: NSSize, labelColor: NSColor?, selected: Bool, removable: Bool, mouseOver: Bool) -> NSImage {
	return NSImage(size: size, flipped: false) { dstRect -> Bool in
		let outerSwatchRect = dstRect.insetBy(dx: 2.5, dy: 2.5)
		let innerSwatchRect = dstRect.insetBy(dx: 5.5, dy: 5.5)

		let borderColor: NSColor
		let fillColor: NSColor
		let markColor: NSColor

		if let labelColor = labelColor {
			let rgbColor = labelColor.usingColorSpace(.sRGB)!

			let factor: CGFloat = 0.8
			let r = 1 - factor*(1 - rgbColor.redComponent)
			let g = 1 - factor*(1 - rgbColor.greenComponent)
			let b = 1 - factor*(1 - rgbColor.blueComponent)

			borderColor = labelColor
			fillColor = NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
			markColor = NSColor.white
		} else {
			borderColor = NSColor.secondaryLabelColor
			fillColor = NSColor.clear
			markColor = borderColor
		}

		if mouseOver {
			let path = NSBezierPath(ovalIn: outerSwatchRect)
			fillColor.set()
			path.fill()
			borderColor.set()
			path.stroke()

			if removable {
				let r = innerSwatchRect.insetBy(dx: 3, dy: 3)
				let inscribedRectLength = r.size.width
				let line = NSBezierPath()
				line.move(to: r.origin)
				line.line(to: NSMakePoint(r.origin.x + inscribedRectLength, r.origin.y + inscribedRectLength))
				line.move(to: NSMakePoint(r.origin.x + inscribedRectLength, r.origin.y))
				line.line(to: NSMakePoint(r.origin.x, r.origin.y + inscribedRectLength))
				line.lineWidth = 1.5
				markColor.set()
				line.stroke()
			} else {
				let r = innerSwatchRect.insetBy(dx: 3, dy: 3)
				let line = NSBezierPath()
				line.move(to: NSMakePoint(r.origin.x + r.size.width/2, r.origin.y))
				line.line(to: NSMakePoint(r.origin.x + r.size.width/2, r.origin.y + r.size.height))
				line.move(to: NSMakePoint(r.origin.x, r.origin.y + r.size.height/2))
				line.line(to: NSMakePoint(r.origin.x + r.size.width, r.origin.y + r.size.height/2))
				line.lineWidth = 1.5
				markColor.set()
				line.stroke()
			}
		} else {
			let path = NSBezierPath(ovalIn: innerSwatchRect)
			fillColor.set()
			path.fill()
			borderColor.set()
			path.stroke()

			if selected {
				let r = innerSwatchRect.insetBy(dx: 3, dy: 3)
				let line = NSBezierPath()
				line.move(to: NSMakePoint(r.origin.x, r.origin.y + r.size.width * 0.5))
				line.line(to: NSMakePoint(r.origin.x + r.size.width/4, r.origin.y))
				line.line(to: NSMakePoint(r.origin.x + r.size.width, r.origin.y + r.size.height))
				line.lineWidth = 1.5
				markColor.set()
				line.stroke()
			}
		}

		return true
	}
}

@objc(OFBFinderTagsChooser)
final class OFBFinderTagsChooser: NSView {
	@objc weak var target: AnyObject?
	@objc var action: Selector?
	@objc var chosenTag: OakFinderTag?
	@objc private(set) var removeChosenTag: Bool = false

	private var favoriteFinderTags: [OakFinderTag] = []
	private var selectedTags: [OakFinderTag] = []
	private var selectedTagsToRemove: [OakFinderTag] = []
	private var hoverTag: OakFinderTag?
	private var tagTextField: NSTextField!

	@objc(finderTagsChooserWithSelectedTags:andSelectedTagsToRemove:forMenu:)
	class func finderTagsChooser(withSelectedTags selectedTags: [OakFinderTag], andSelectedTagsToRemove selectedTagsToRemove: [OakFinderTag], for menu: NSMenu) -> OFBFinderTagsChooser {
		return OFBFinderTagsChooser(selectedTags: selectedTags, andSelectedTagsToRemove: selectedTagsToRemove, for: menu)
	}

	init(selectedTags: [OakFinderTag], andSelectedTagsToRemove selectedTagsToRemove: [OakFinderTag], for menu: NSMenu) {
		super.init(frame: .zero)

		NotificationCenter.default.addObserver(self, selector: #selector(mouseDidEnterFinderTagButton(_:)), name: .OakRolloverButtonMouseDidEnter, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(mouseDidLeaveFinderTagButton(_:)), name: .OakRolloverButtonMouseDidLeave, object: nil)

		favoriteFinderTags = OakFinderTagManager.favoriteFinderTags()
		self.selectedTags = selectedTags
		self.selectedTagsToRemove = selectedTagsToRemove

		autoresizesSubviews = true
		autoresizingMask = [.width, .height]

		tagTextField = NSTextField(frame: .zero)
		tagTextField.cell?.setAccessibilityElement(false)
		tagTextField.font            = menu.font
		tagTextField.textColor       = NSColor.disabledControlTextColor
		tagTextField.isBezeled       = false
		tagTextField.isBordered      = false
		tagTextField.drawsBackground = false
		tagTextField.isEditable      = false
		tagTextField.isSelectable    = false
		tagTextField.stringValue     = "Tags…"

		tagTextField.translatesAutoresizingMaskIntoConstraints = false
		addSubview(tagTextField)

		var buttons: [NSView] = []
		for i in 0..<favoriteFinderTags.count {
			let tag = favoriteFinderTags[i]
			let isSelected  = selectedTags.contains(tag)
			let isRemovable = selectedTagsToRemove.contains(tag)

			let button = OakRolloverButton(frame: .zero)
			button.setAccessibilityLabel("\(isRemovable ? "Remove" : "Add") tag \(tag.displayName ?? "")")

			button.regularImage  = finderTagSwatchImage(size: NSMakeSize(SwatchButtonWidth, SwatchButtonWidth), labelColor: tag.labelColor, selected: isSelected, removable: isRemovable, mouseOver: false)
			button.pressedImage  = finderTagSwatchImage(size: NSMakeSize(SwatchButtonWidth, SwatchButtonWidth), labelColor: tag.labelColor, selected: isSelected, removable: isRemovable, mouseOver: true)
			button.rolloverImage = finderTagSwatchImage(size: NSMakeSize(SwatchButtonWidth, SwatchButtonWidth), labelColor: tag.labelColor, selected: isSelected, removable: isRemovable, mouseOver: true)
			button.target = self
			button.action = #selector(didClickFinderTag(_:))
			button.tag = i

			buttons.append(button)
		}

		if !buttons.isEmpty {
			let stackView = NSStackView(views: buttons)
			stackView.spacing = 0

			OakAddAutoLayoutViewsToSuperview([stackView], self)

			let views: [String: NSView] = ["tagButtons": stackView, "tagTextField": tagTextField]
			addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[tagButtons]-(5)-[tagTextField]|", options: [], metrics: nil, views: views))
			addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[tagTextField]|", options: [], metrics: nil, views: views))
			addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[tagButtons]-(>=20)-|", options: [], metrics: nil, views: views))
		} else {
			addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[tagTextField]|", options: [], metrics: nil, views: ["tagTextField": tagTextField]))
			addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[tagTextField]|", options: [], metrics: nil, views: ["tagTextField": tagTextField]))
		}

		setFrameSize(fittingSize)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	override var intrinsicContentSize: NSSize {
		return NSMakeSize(SwatchButtonWidth * CGFloat(favoriteFinderTags.count + 1), SwatchButtonWidth + tagTextField.intrinsicContentSize.height)
	}

	@objc func mouseDidEnterFinderTagButton(_ notification: Notification) {
		guard let button = notification.object as? NSButton, button.target === self else { return }
		let tag = favoriteFinderTags[button.tag]
		hoverTag = tag
		if selectedTagsToRemove.contains(tag) {
			tagTextField.stringValue = "Remove “\(tag.displayName ?? "")”"
		} else {
			tagTextField.stringValue = "Add “\(tag.displayName ?? "")”"
		}
	}

	@objc func mouseDidLeaveFinderTagButton(_ notification: Notification) {
		guard let button = notification.object as? NSButton, button.target === self else { return }
		hoverTag = nil
		tagTextField.stringValue = "Tags…"
		needsDisplay = true
	}

	@objc func didClickFinderTag(_ sender: Any?) {
		guard let button = sender as? NSView else { return }
		let tag = favoriteFinderTags[button.tag]

		if let action = action, target == nil || (target?.responds(to: action) ?? false) {
			chosenTag = tag
			removeChosenTag = selectedTagsToRemove.contains(tag)
			NSApp.sendAction(action, to: target, from: self)
			enclosingMenuItem?.menu?.cancelTracking()
		}
	}
}
