// Renders an SCM status string ("M", "A", "D"…) as colored badge characters.
// Registered by name — the table cell binds with
// NSValueTransformerNameBindingOption: "CWStatusStringTransformer".
//
// Ported from Chris Thomas's 2005 ObjC original (MIT license).
import AppKit

final class CWStatusStringTransformer: ValueTransformer {
	static func register() {
		ValueTransformer.setValueTransformer(CWStatusStringTransformer(), forName: NSValueTransformerName("CWStatusStringTransformer"))
	}

	override class func transformedValueClass() -> AnyClass { NSAttributedString.self }
	override class func allowsReverseTransformation() -> Bool { true }

	override func transformedValue(_ value: Any?) -> Any? {
		guard let status = value as? String else { return nil }
		return Self.attributedStatusString(status)
	}

	override func reverseTransformedValue(_ value: Any?) -> Any? {
		(value as? NSAttributedString)?.string
	}

	private static func color(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
		NSColor(deviceRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
	}

	private static let colors: [String: (fore: NSColor, back: NSColor)] = [
		"M": (color(0xEB, 0x64, 0x00), color(0xF7, 0xE1, 0xAD)), // modified
		"G": (color(0xEB, 0x64, 0x00), color(0xF7, 0xE1, 0xAD)),
		"X": (color(0xFF, 0xFF, 0xFF), color(0x00, 0x00, 0x00)), // external
		"A": (color(0x00, 0xAA, 0x00), color(0xBB, 0xFF, 0xB3)), // added
		"D": (color(0xFF, 0x00, 0x00), color(0xF5, 0xBD, 0xBD)), // deleted
		"R": (color(0xFF, 0x00, 0x00), color(0xF5, 0xBD, 0xBD)),
		"C": (color(0x00, 0x80, 0x80), color(0xA3, 0xCE, 0xD0)), // conflict
		"?": (color(0x00, 0x80, 0x80), color(0xA3, 0xCE, 0xD0)),
		"I": (color(0x80, 0x00, 0x80), color(0xED, 0xAE, 0xF5)), // ignored
	]

	private static func attributedStatusString(_ string: String) -> NSAttributedString {
		let result = NSMutableAttributedString()
		let space = NSAttributedString(string: " ")
		let emSpace: Character = "\u{2003}"
		let hairSpace = "\u{200A}"

		for var character in string {
			// underscores stand in for empty multi-column attributes
			if character == "_" {
				character = emSpace
			}
			let charString = String(character)

			let (fore, back) = Self.colors[charString] ?? (NSColor.controlTextColor, NSColor.controlBackgroundColor)
			let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: fore, .backgroundColor: back]

			let attributedChar = NSMutableAttributedString(string: hairSpace + charString + hairSpace, attributes: attributes)

			let width = attributedChar.size().width
			let desiredWidth: CGFloat = 13
			if width < desiredWidth {
				let hairSpaceWidth = NSAttributedString(string: hairSpace, attributes: attributes).size().width
				let extraWidth = 0.5 * (desiredWidth - width) + hairSpaceWidth
				let scale = log(Float(extraWidth - (hairSpaceWidth - 1)))
				let expansion: [NSAttributedString.Key: Any] = [.expansion: NSNumber(value: scale)]
				attributedChar.addAttributes(expansion, range: NSRange(location: 0, length: 1))
				attributedChar.addAttributes(expansion, range: NSRange(location: 2, length: 1))
			}

			result.append(attributedChar)
			result.append(space)
		}
		return result
	}
}
