// The programmatic table cell: [✓] [status badge] [path]        [Diff]
// Built with OakAppKit's construction functions (imported through the bridging
// header) so fonts and styles stay identical to the rest of the app.
import AppKit

final class CWTableCellView: NSTableCellView {
	let commitCheckBox: NSButton
	let diffButton: NSButton
	let statusTextField: NSTextField

	init() {
		commitCheckBox = OakCreateCheckBox("")
		commitCheckBox.controlSize = .small

		statusTextField = OakCreateLabel("", nil, .left, .byTruncatingMiddle)

		diffButton = OakCreateButton("Diff", .rounded)
		diffButton.font = NSFont.messageFont(ofSize: NSFont.systemFontSize(for: .mini))
		diffButton.controlSize = .mini

		super.init(frame: .zero)

		let textField: NSTextField = OakCreateLabel("", NSFont.controlContentFont(ofSize: 0), .left, .byTruncatingMiddle)
		self.textField = textField

		textField.bind(.value, to: self, withKeyPath: "objectValue.path", options: nil)
		commitCheckBox.bind(.value, to: self, withKeyPath: "objectValue.commit", options: nil)
		statusTextField.bind(.value, to: self, withKeyPath: "objectValue.scmStatus", options: [.valueTransformerName: "CWStatusStringTransformer"])

		let views: [String: NSView] = ["commit": commitCheckBox, "status": statusTextField, "textField": textField, "diff": diffButton]
		OakAddAutoLayoutViewsToSuperview(Array(views.values), self)

		commitCheckBox.setContentCompressionResistancePriority(.required, for: .horizontal)
		statusTextField.setContentCompressionResistancePriority(.required, for: .horizontal)

		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(5)-[commit]-(5)-[status]-(5)-[textField]-(>=5)-[diff(==40)]-(5)-|", options: .alignAllCenterY, metrics: nil, views: views))
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported — CWTableCellView is built programmatically")
	}
}
