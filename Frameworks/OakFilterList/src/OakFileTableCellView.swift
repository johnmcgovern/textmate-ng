import AppKit

// Ported from the OakFileTableCellView in OakChooser.mm (2026-08-20). The row view the
// file and bundle-item choosers show: an icon and two labels (name over folder) plus a
// close button, each label bound to a key of the row's objectValue dictionary. No C++ in
// the original, so a straight translation; behaviour is pinned by t_file_table_cell_view.mm
// (rule 18). FileChooser.mm still constructs it as ObjC++ through the hand-declaration in
// OakFileTableCellView.h.
//
// -setBackgroundStyle: recolours the matched-text runs when the row is drawn emphasised
// (NSBackgroundStyleDark is the same value as NSBackgroundStyleEmphasized), and the legacy
// accessibility-children override reports the four cells; both are kept as they were.
@objc(OakFileTableCellView)
class OakFileTableCellView: NSTableCellView {
	private var folderTextField: NSTextField!
	private var closeButton: NSButton!

	@objc init(closeButton: NSButton) {
		super.init(frame: .zero)

		let imageView = NSImageView()
		imageView.setContentHuggingPriority(.required, for: .horizontal)
		imageView.setContentCompressionResistancePriority(.required, for: .horizontal)

		let fileTextField = OakCreateLabel("", NSFont.systemFont(ofSize: 13), .left, .byTruncatingMiddle)!
		let folderTextField = OakCreateLabel("", NSFont.controlContentFont(ofSize: 10), .left, .byTruncatingMiddle)!

		fileTextField.lineBreakMode        = .byTruncatingTail
		fileTextField.cell?.lineBreakMode   = .byTruncatingTail
		folderTextField.lineBreakMode      = .byTruncatingHead
		folderTextField.cell?.lineBreakMode = .byTruncatingHead

		let views: [String: NSView] = ["icon": imageView, "file": fileTextField, "folder": folderTextField, "close": closeButton]
		OakAddAutoLayoutViewsToSuperview(Array(views.values), self)

		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(4)-[icon]-(4)-[file]-(4)-[close(==16)]-(8)-|", options: [], metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[file]-(2)-[folder]-(5)-|", options: [.alignAllLeading, .alignAllTrailing], metrics: nil, views: views))
		imageView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive   = true
		closeButton.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true

		imageView.bind(.value, to: self, withKeyPath: "objectValue.icon", options: nil)
		fileTextField.bind(.value, to: self, withKeyPath: "objectValue.name", options: nil)
		folderTextField.bind(.value, to: self, withKeyPath: "objectValue.folder", options: nil)

		self.imageView       = imageView
		self.textField       = fileTextField
		self.folderTextField = folderTextField
		self.closeButton     = closeButton
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private func selectedString(for value: Any?) -> NSAttributedString? {
		let str: NSMutableAttributedString
		if let string = value as? String {
			str = NSMutableAttributedString(string: string)
		} else if let attributed = value as? NSAttributedString, let copy = attributed.mutableCopy() as? NSMutableAttributedString {
			str = copy
		} else {
			return nil
		}

		str.enumerateAttributes(in: NSRange(location: 0, length: str.length), options: .longestEffectiveRangeNotRequired) { attrs, range, _ in
			if attrs[.backgroundColor] != nil {
				str.addAttribute(.backgroundColor, value: NSColor.tmMatchedTextSelectedBackground()!, range: range)
			}
			if attrs[.underlineColor] != nil {
				str.addAttribute(.underlineColor, value: NSColor.tmMatchedTextSelectedUnderline()!, range: range)
			}
		}
		return str
	}

	override var backgroundStyle: NSView.BackgroundStyle {
		didSet {
			if backgroundStyle == .emphasized {
				textField?.objectValue       = selectedString(for: value(forKeyPath: "objectValue.name"))
				folderTextField.textColor     = NSColor(calibratedWhite: 0.9, alpha: 1)
				folderTextField.objectValue   = selectedString(for: value(forKeyPath: "objectValue.folder"))
			} else {
				textField?.objectValue       = value(forKeyPath: "objectValue.name")
				folderTextField.textColor     = NSColor(calibratedWhite: 0.5, alpha: 1)
				folderTextField.objectValue   = value(forKeyPath: "objectValue.folder")
			}
		}
	}

	// The deprecated attribute-based accessibility override the ObjC++ used to expose the
	// four cells as this view's children; nothing calls it directly, so it is marked
	// deprecated to keep its super call from warning (same as OakLinkedSearchFieldCell).
	@available(macOS, deprecated: 10.10)
	override func accessibilityAttributeValue(_ attribute: NSAccessibility.Attribute) -> Any? {
		if attribute == .children {
			// AX queries arrive on the main thread; this override is forced nonisolated
			// because it overrides a nonisolated NSObject method, so reach the main-actor
			// cell properties through assumeIsolated (as OakPasteboard does for NSApp).
			return MainActor.assumeIsolated {
				[textField?.cell, folderTextField.cell, closeButton.cell, imageView?.cell].compactMap { $0 }
			}
		}
		return super.accessibilityAttributeValue(attribute)
	}
}
