import AppKit

// Ported from OakSyntaxFormatter.mm, once the C++ that blocked it had moved to
// OakSyntaxFormatterSupport. What is left is an NSFormatter and one AppKit pass:
// reset the attributes the styler is allowed to own, then put back whatever the
// styler asks for.
//
// Order matters twice in that pass and neither is obvious, so both are marked
// where they happen: the early return sits *before* the reset rather than after,
// and -fixFontAttributeInRange: runs last, unconditionally.

@objc(OakSyntaxFormatter)
class OakSyntaxFormatter: Formatter {
	// nil for a plain -init, which is a real case: -addStylesToString: returns
	// immediately without even resetting.
	private let grammarName: String?

	// Built on first use, not here: loading a grammar is the expensive part and a
	// formatter that is never enabled must never pay it.
	private var styler: OakSyntaxStyler?

	@objc dynamic var enabled: Bool = false

	@objc init(grammarName: String?) {
		self.grammarName = grammarName
		super.init()
	}

	override init() {
		self.grammarName = nil
		super.init()
	}

	required init?(coder: NSCoder) {
		self.grammarName = nil
		super.init(coder: coder)
	}

	// MARK: - The NSFormatter halves

	override func string(for value: Any?) -> String? {
		return value as? String
	}

	override func getObjectValue(_ valueRef: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription errorRef: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
		// We break NSContinuouslyUpdatesValueBindingOption unless a new instance is returned
		valueRef?.pointee = (string as NSString).copy() as AnyObject
		return true
	}

	override func attributedString(for value: Any, withDefaultAttributes attributes: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString? {
		let styled = NSMutableAttributedString(string: value as? String ?? "", attributes: attributes)
		addStyles(to: styled)
		return styled
	}

	// MARK: - The styling pass

	@objc(addStylesToString:)
	func addStyles(to styled: NSMutableAttributedString) {
		let plain = styled.string
		// Before the reset, not after. A formatter with no grammar name leaves the
		// string exactly as it found it — it does not fall back to plain styling.
		guard !plain.isEmpty, let grammarName else {
			return
		}

		let all = NSRange(location: 0, length: (plain as NSString).length)

		for attribute in [NSAttributedString.Key.backgroundColor, .underlineStyle, .strikethroughStyle] {
			styled.removeAttribute(attribute, range: all)
		}
		styled.addAttributes([.foregroundColor: NSColor.controlTextColor], range: all)
		styled.applyFontTraits([.unboldFontMask, .unitalicFontMask], range: all)

		if enabled {
			if styler == nil {
				styler = OakSyntaxStyler(grammarName: grammarName)
			}

			// nil when the grammar failed to load, and iterating nothing is the same
			// nothing the old `enabled && tryLoadGrammarAndTheme` guard did.
			for run in styler?.styleRuns(for: plain) ?? [] {
				if !run.fontTraits.isEmpty {
					styled.applyFontTraits(run.fontTraits, range: run.range)
				}

				var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: run.foregroundColor]
				if let backgroundColor = run.backgroundColor {
					attributes[.backgroundColor] = backgroundColor
				}
				if run.underlined {
					attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
				}
				if run.strikethrough {
					attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
				}
				styled.addAttributes(attributes, range: run.range)
			}
		}

		// Last, and outside the `enabled` branch: the reset pass alone can leave a
		// font the string cannot render, and this is what resolves it.
		styled.fixFontAttribute(in: all)
	}
}
