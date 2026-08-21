import AppKit

// Ported from ui/SearchField.mm (2026-08-20). OakChooser's filter field. Its only job
// is to install OakLinkedSearchFieldCell, which works around rdar://16271507 by telling
// VoiceOver the field has one extra space before and after the actual search string, so
// the caret and selection read correctly at the ends. The ObjC++ installed the cell in
// +initialize via +setCellClass:; Swift has no +initialize (rule 20), so the class
// overrides the cellClass class property instead — t_searchfield.mm pins that this still
// registers the custom cell. OakChooser.mm consumes OakLinkedSearchField through the
// hand-declaration in ui/SearchField.h.
//
// The whole cell is the deprecated attribute-based NSAccessibility API (macOS 10.10),
// kept verbatim because the shifted-by-one range translation is exactly what the
// workaround needs and the modern protocol does not expose every parameterized attribute
// used here (RTF/style ranges). The behaviour is only observable through a live VoiceOver
// client, so there is no unit test beyond the cell-registration pin.

// See https://lists.apple.com/archives/accessibility-dev/2014/Feb/msg00019.html

private func spacedString(_ length: Int) -> String {
	String(repeating: " ", count: length)
}

// Maps an AX range/index expressed against the padded ( leftMargin + text + rightMargin )
// coordinate space back onto the real text, and hands the caller how much of the query
// fell in each margin so it can splice the fake spaces back into the result.
private func translateAXRange(_ range: NSRange, length: Int, leftMargin: Int = 1, rightMargin: Int = 1, process: (Int, NSRange, Int) -> Any?) -> Any? {
	if NSMaxRange(range) > leftMargin + length + rightMargin {
		NSException(name: NSExceptionName("NSAccessibilityException"),
		            reason: "TranslateAXRange: requested range \(NSStringFromRange(range)) out of bounds for (\(leftMargin),\(length),\(rightMargin))",
		            userInfo: nil).raise()
	}

	let leftMarginRange  = NSRange(location: 0, length: leftMargin)
	let rightMarginRange = NSRange(location: leftMargin + length, length: rightMargin)
	let middleRange      = NSRange(location: leftMargin, length: length)

	let leftRange  = NSIntersectionRange(range, leftMarginRange)
	let rightRange = NSIntersectionRange(range, rightMarginRange)
	var baseRange  = NSIntersectionRange(range, middleRange)
	if baseRange.length == 0 {
		if leftRange.length != 0 {
			baseRange.location = leftMargin
		} else if rightRange.length != 0 {
			baseRange.location = NSMaxRange(middleRange)
		} else {
			baseRange.location = range.location
		}
	}
	baseRange.location -= leftMargin
	return process(leftRange.length, baseRange, rightRange.length)
}

@objc(OakLinkedSearchFieldCell)
class OakLinkedSearchFieldCell: NSSearchFieldCell {
	// These three override the deprecated attribute-based AX informal protocol and must
	// call its equally-deprecated super methods; nothing invokes them directly (AppKit
	// dispatches through the runtime), so marking them deprecated only silences the
	// self-inflicted warnings while keeping the override in place.
	@available(macOS, deprecated: 10.10)
	override func accessibilityAttributeValue(_ attribute: NSAccessibility.Attribute) -> Any? {
		var value = super.accessibilityAttributeValue(attribute)
		if attribute == .value {
			value = " \(value.map { String(describing: $0) } ?? "") "
		} else if attribute == .numberOfCharacters {
			value = NSNumber(value: 1 + ((value as? NSNumber)?.intValue ?? 0) + 1)
		} else if attribute == .selectedTextRange || attribute == .visibleCharacterRange {
			if var range = (value as? NSValue)?.rangeValue {
				range.location += 1
				value = NSValue(range: range)
			}
		} else if attribute == .help {
			return "Type filter string, then hear search results using arrow up/down."
		}
		return value
	}

	@available(macOS, deprecated: 10.10)
	override func accessibilitySetValue(_ value: Any?, forAttribute attribute: NSAccessibility.Attribute) {
		if attribute == .selectedTextRange || attribute == .visibleCharacterRange {
			let length = (super.accessibilityAttributeValue(.numberOfCharacters) as? NSNumber)?.intValue ?? 0
			_ = translateAXRange((value as? NSValue)?.rangeValue ?? NSRange(), length: length) { _, range, _ in
				super.accessibilitySetValue(NSValue(range: range), forAttribute: attribute)
				return nil
			}
		}
	}

	@available(macOS, deprecated: 10.10)
	override func accessibilityAttributeValue(_ attribute: NSAccessibility.ParameterizedAttribute, forParameter parameter: Any?) -> Any? {
		let length = (super.accessibilityAttributeValue(.numberOfCharacters) as? NSNumber)?.intValue ?? 0

		if attribute == .attributedStringForRange {
			return translateAXRange((parameter as? NSValue)?.rangeValue ?? NSRange(), length: length) { left, range, right in
				let value = super.accessibilityAttributeValue(attribute, forParameter: NSValue(range: range))
				guard let attributed = value as? NSAttributedString else { return value }
				let string = NSMutableAttributedString(attributedString: attributed)
				if left != 0 {
					string.insert(NSAttributedString(string: spacedString(left)), at: 0)
				}
				if right != 0 {
					string.insert(NSAttributedString(string: spacedString(right)), at: string.length)
				}
				return string
			}
		} else if attribute == .boundsForRange {
			return translateAXRange((parameter as? NSValue)?.rangeValue ?? NSRange(), length: length) { _, range, _ in
				super.accessibilityAttributeValue(attribute, forParameter: NSValue(range: range))
			}
		} else if attribute == .lineForIndex {
			return translateAXRange(NSRange(location: (parameter as? NSNumber)?.intValue ?? 0, length: 0), length: length) { _, range, _ in
				super.accessibilityAttributeValue(attribute, forParameter: NSNumber(value: range.location))
			}
		} else if attribute == .rangeForIndex {
			return translateAXRange(NSRange(location: (parameter as? NSNumber)?.intValue ?? 0, length: 0), length: length) { left, range, right in
				if left != 0 {
					return NSValue(range: NSRange(location: 0, length: 1))
				}
				if right != 0 {
					return NSValue(range: NSRange(location: NSMaxRange(range), length: 1))
				}
				var ret = (super.accessibilityAttributeValue(attribute, forParameter: NSNumber(value: range.location)) as? NSValue)?.rangeValue ?? NSRange()
				ret.location += 1
				return NSValue(range: ret)
			}
		} else if attribute == .rangeForLine || attribute == .rangeForPosition {
			var ret = (super.accessibilityAttributeValue(attribute, forParameter: parameter) as? NSValue)?.rangeValue ?? NSRange()
			ret.location += 1
			return NSValue(range: ret)
		} else if attribute == .rtfForRange {
			return translateAXRange((parameter as? NSValue)?.rangeValue ?? NSRange(), length: length) { left, range, right in
				guard let data = super.accessibilityAttributeValue(attribute, forParameter: NSValue(range: range)) as? Data else { return nil }
				var documentAttributes: NSDictionary?
				guard let string = NSMutableAttributedString(rtf: data, documentAttributes: &documentAttributes) else { return nil }
				if left != 0 {
					string.insert(NSAttributedString(string: spacedString(left)), at: 0)
				}
				if right != 0 {
					string.insert(NSAttributedString(string: spacedString(right)), at: string.length)
				}
				let attrs = (documentAttributes as? [NSAttributedString.DocumentAttributeKey: Any]) ?? [:]
				return string.rtf(from: NSRange(location: 0, length: string.length), documentAttributes: attrs)
			}
		} else if attribute == .stringForRange {
			return translateAXRange((parameter as? NSValue)?.rangeValue ?? NSRange(), length: length) { left, range, right in
				let value = super.accessibilityAttributeValue(attribute, forParameter: NSValue(range: range))
				let leftPad = String(describing: NSAttributedString(string: spacedString(left != 0 ? 1 : 0)))
				let rightPad = String(describing: NSAttributedString(string: spacedString(right != 0 ? 1 : 0)))
				return "\(leftPad)\(value.map { String(describing: $0) } ?? "")\(rightPad)"
			}
		} else if attribute == .styleRangeForIndex {
			return translateAXRange(NSRange(location: (parameter as? NSNumber)?.intValue ?? 0, length: 0), length: length) { left, range, right in
				if left != 0 {
					return NSValue(range: NSRange(location: 0, length: 1))
				}
				if right != 0 {
					return NSValue(range: NSRange(location: NSMaxRange(range), length: 1))
				}
				var ret = (super.accessibilityAttributeValue(attribute, forParameter: NSNumber(value: range.location)) as? NSValue)?.rangeValue ?? NSRange()
				ret.location += 1
				return NSValue(range: ret)
			}
		} else {
			return super.accessibilityAttributeValue(attribute, forParameter: parameter)
		}
	}
}

@objc(OakLinkedSearchField)
class OakLinkedSearchField: NSSearchField {
	override class var cellClass: AnyClass? {
		get { OakLinkedSearchFieldCell.self }
		set {}
	}
}
