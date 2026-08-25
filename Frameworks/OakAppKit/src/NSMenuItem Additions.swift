import AppKit
import ObjectiveC

// Ported from "NSMenuItem Additions.mm". The three std::string-typed selectors
// stayed behind in NSMenuItemCxx.mm — Swift cannot declare a method taking a
// `std::string const&` at all (rule 17) — and they are now forwarders onto the
// ObjC-clean spellings below.
//
// The category's ObjC face is the hand declaration in "NSMenuItem Additions.h"
// (rule 23), which five frameworks' bridging headers import. Every method here
// carries an explicit @objc(selector) so that header stays true by construction.

// An NSAttributedString that lies about its height.
//
// -setActivationString:withFont: appends a newline to force the string to the
// menu's full width, and the menu then reserves a line's worth of height for it.
// Reporting the size *without* the newline is the whole reason this class exists.
private class MenuAttributedString: NSAttributedString {
	private let wrapped: NSAttributedString
	var desiredSize: CGSize = .zero

	init(wrapping attributedString: NSAttributedString?) {
		wrapped = (attributedString?.copy() as? NSAttributedString) ?? NSAttributedString()
		super.init()
	}

	required init?(coder: NSCoder) {
		wrapped = NSAttributedString()
		super.init(coder: coder)
	}

	required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
		wrapped = NSAttributedString()
		super.init(pasteboardPropertyList: propertyList, ofType: type)
	}

	override var string: String {
		wrapped.string
	}

	override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
		wrapped.attributes(at: location, effectiveRange: range)
	}

	override func copy(with zone: NSZone? = nil) -> Any {
		let copy = MenuAttributedString(wrapping: wrapped)
		copy.desiredSize = desiredSize
		return copy
	}

	// We overload this method to return a height without the newline that
	// is required to make the attributed string use the menu’s full width
	override func boundingRect(with size: NSSize, options: NSString.DrawingOptions = [], context: NSStringDrawingContext?) -> NSRect {
		NSRect(x: 0, y: 0, width: desiredSize.width, height: desiredSize.height)
	}
}

// Association keys are identities, not values — only their addresses matter.
// `nonisolated(unsafe)` because strict concurrency cannot know that, and the
// alternative (a global `let`) has no address to take.
private enum AssociatedKeys {
	nonisolated(unsafe) static var keyEquivalent = 0
	nonisolated(unsafe) static var tabTrigger    = 0
}

extension NSMenuItem {
	private var menuFont: NSFont {
		menu?.font ?? NSFont.menuFont(ofSize: 0)
	}

	@objc(setIconForFile:)
	func setIconForFile(_ path: String) {
		let icon: NSImage?
		if FileManager.default.fileExists(atPath: path) {
			icon = NSWorkspace.shared.icon(forFile: path)
		}
		else if OakNotEmptyString((path as NSString).pathExtension) {
			icon = NSWorkspace.shared.icon(forFileType: (path as NSString).pathExtension)
		}
		else {
			icon = NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kUnknownFSObjectIcon)))
		}

		if let icon {
			icon.size = NSSize(width: 16, height: 16)
			image = icon
		}
	}

	@objc(setActivationString:withFont:)
	func setActivationString(_ activationString: String, withFont font: NSFont?) {
		let menuFont = self.menuFont

		var leftString = title
		let rightString = activationString

		let leftSize  = (leftString as NSString).size(withAttributes: [.font: menuFont])
		let rightSize = (rightString as NSString).size(withAttributes: [.font: font ?? menuFont])

		let table = NSTextTable()
		table.numberOfColumns = 2

		let leftBlock  = NSTextTableBlock(table: table, startingRow: 0, rowSpan: 1, startingColumn: 0, columnSpan: 1)
		let rightBlock = NSTextTableBlock(table: table, startingRow: 0, rowSpan: 1, startingColumn: 1, columnSpan: 1)

		leftBlock.verticalAlignment  = .middleAlignment
		rightBlock.verticalAlignment = (font?.pointSize ?? 0) >= 13 ? .bottomAlignment : .middleAlignment

		rightBlock.setContentWidth(rightSize.width, type: .absoluteValueType)

		let leftPStyle = NSMutableParagraphStyle()
		leftPStyle.textBlocks    = [leftBlock]
		leftPStyle.alignment     = .left
		leftPStyle.lineBreakMode = .byClipping

		let rightPStyle = NSMutableParagraphStyle()
		rightPStyle.textBlocks    = [rightBlock]
		rightPStyle.alignment     = .right
		rightPStyle.lineBreakMode = .byClipping

		// This is required to make the attributed string use the menu’s full width
		leftString += "\n"

		let attributedString = NSMutableAttributedString()

		attributedString.append(NSAttributedString(string: leftString, attributes: [
			.paragraphStyle: leftPStyle,
			.font:           menuFont,
		]))

		let shortcutTextColor = NSColor.tertiaryLabelColor

		attributedString.append(NSAttributedString(string: rightString, attributes: [
			.paragraphStyle:  rightPStyle,
			.font:            font ?? menuFont,
			.foregroundColor: shortcutTextColor,
		]))

		let attributedTitle = MenuAttributedString(wrapping: attributedString)
		// Set the string’s bounding box to the height *excluding* the newline appended above
		attributedTitle.desiredSize = NSSize(width: leftSize.width + rightSize.width, height: max(leftSize.height, rightSize.height))

		// The title goes back afterwards, and that is not tidying: the title is the
		// item's identity. User key equivalents are keyed by it and -itemWithTitle:
		// finds items by it, so leaving the two-column string in place would make
		// the item unfindable.
		let plainTitle = title
		self.attributedTitle = attributedTitle
		title = plainTitle
	}

	@objc(updateTitle:)
	func updateTitle(_ newTitle: String) {
		guard title != newTitle else {
			return
		}

		title = newTitle
		// Setting the title throws the attributed title away, which is the entire
		// reason these two are kept as associations: they have to be redrawn onto
		// whatever the title just became.
		if let keyEquivalent = objc_getAssociatedObject(self, &AssociatedKeys.keyEquivalent) as? String {
			setInactiveKeyEquivalent(keyEquivalent)
		}
		if let tabTrigger = objc_getAssociatedObject(self, &AssociatedKeys.tabTrigger) as? String {
			setTabTrigger(tabTrigger)
		}
	}

	// The ObjC-clean spelling of -setKeyEquivalentCxxString:. It cannot be called
	// -setKeyEquivalent:, which AppKit already owns and which takes the key on its
	// own; this one takes the modifier prefix with it.
	//
	// The parser lives here rather than in NSMenuItemCxx.mm so that Swift callers
	// can reach it — OTVStatusBar sets a key equivalent per grammar. The std::string
	// selector is now a forwarder onto this.
	@objc(setKeyEquivalentString:)
	func setKeyEquivalentString(_ keyEquivalent: String?) {
		// nil is NULL_STR; both it and an empty string clear the item.
		guard let keyEquivalent, !keyEquivalent.isEmpty else {
			self.keyEquivalent = ""
			keyEquivalentModifierMask = []
			return
		}

		var modifiers: NSEvent.ModifierFlags = []

		// Byte-at-a-time over UTF-8, as the ObjC++ was over the std::string. Only
		// ASCII can be a modifier, so the scan never stops mid-character and the
		// tail always decodes cleanly. The ObjC++ tested membership of "$^~@#" and
		// then switched on the same five characters; one switch does both.
		let bytes = Array(keyEquivalent.utf8)
		var i = 0
		scan: while true {
			// `i+1 >= count` and not `i >= count`: the final character is never a
			// modifier, which is what makes "⌘@" expressible as "@@" and "@" on its
			// own the unmodified character.
			if i + 1 >= bytes.count {
				break
			}

			switch bytes[i] {
				case UInt8(ascii: "$"): modifiers.insert(.shift)
				case UInt8(ascii: "^"): modifiers.insert(.control)
				case UInt8(ascii: "~"): modifiers.insert(.option)
				case UInt8(ascii: "@"): modifiers.insert(.command)
				case UInt8(ascii: "#"): modifiers.insert(.numericPad)
				default: break scan
			}

			i += 1
		}

		self.keyEquivalent = String(decoding: bytes[i...], as: UTF8.self)
		keyEquivalentModifierMask = modifiers
	}

	@objc(setInactiveKeyEquivalent:)
	func setInactiveKeyEquivalent(_ keyEquivalent: String?) {
		objc_setAssociatedObject(self, &AssociatedKeys.keyEquivalent, keyEquivalent, .OBJC_ASSOCIATION_RETAIN)
		// nil is NULL_STR, and an empty string draws nothing either — an item that
		// may gain a shortcut later is initialised without flashing one.
		if let keyEquivalent, !keyEquivalent.isEmpty {
			setActivationString(" " + OakGlyphsForEventString(keyEquivalent), withFont: nil)
		}
	}

	@objc(setTabTrigger:)
	func setTabTrigger(_ tabTrigger: String?) {
		objc_setAssociatedObject(self, &AssociatedKeys.tabTrigger, tabTrigger, .OBJC_ASSOCIATION_RETAIN)
		// Note the asymmetry with the method above: an *empty* tab trigger still
		// draws (as a bare ⇥), only nil does not. That is what the ObjC++ did.
		if let tabTrigger {
			setActivationString(" " + tabTrigger + "⇥", withFont: NSFont.menuBarFont(ofSize: floor(menuFont.pointSize * 0.85)))
		}
	}

	@objc(setModifiedState:)
	func setModifiedState(_ flag: Bool) {
		if let image = NSImage(named: "NSMenuItemBullet") {
			mixedStateImage = image
		}
		state = flag ? .mixed : .off
	}

	@objc(setDynamicTitle:)
	func setDynamicTitle(_ title: String) {
		var plainTitle = title

		if OakNotEmptyString(userKeyEquivalent) {
			// The title is deliberately *not* changed here. A user key equivalent is
			// bound to the item by its title, so renaming the item would drop the
			// shortcut; the requested text goes into the attributed title instead.
			let requestedTitle = title
			plainTitle = self.title

			if requestedTitle == plainTitle {
				attributedTitle = nil
			}
			else {
				attributedTitle = NSAttributedString(string: requestedTitle, attributes: [.font: menuFont])
			}
		}

		self.title = plainTitle
	}
}
