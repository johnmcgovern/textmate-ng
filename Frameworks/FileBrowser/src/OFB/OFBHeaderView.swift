import AppKit

// The file browser's header strip: a folder pop-up on the left, back/forward on
// the right, a divider above the content. This framework's first Swift file, and
// deliberately one of its simplest — a code-built NSVisualEffectView with no
// logic, so the port that proves the Swift build wiring risks nothing else.
//
// OFBHeaderView.h stays as a hand-written ObjC declaration of this class, the
// DocumentWindowController.h arrangement: the framework's own ObjC++
// (FileBrowserView, FileBrowserViewController) keeps importing that header
// unchanged, and it must NOT reach the Swift bridging header or the class would
// be declared twice. Nothing checks the .h against this file at build time — the
// selector-surface test does, at runtime.

private func OakCreateImageButton(_ imageName: NSImage.Name) -> NSButton {
	let res = NSButton(frame: .zero)
	res.setButtonType(.momentaryChange)
	res.isBordered = false
	res.image = NSImage(named: imageName)
	res.imagePosition = .imageOnly
	return res
}

private func OakCreateFolderPopUpButton() -> NSPopUpButton {
	let res = NSPopUpButton(frame: .zero, pullsDown: true)
	res.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
	res.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
	res.setContentHuggingPriority(.defaultLow, for: .vertical)
	res.isBordered = false
	return res
}

@objc(OFBHeaderView)
class OFBHeaderView: NSVisualEffectView {
	@objc var folderPopUpButton: NSPopUpButton!
	@objc var goBackButton: NSButton!
	@objc var goForwardButton: NSButton!

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)

		wantsLayer   = true
		blendingMode = .withinWindow
		material     = .titlebar

		folderPopUpButton       = OakCreateFolderPopUpButton()
		goBackButton            = OakCreateImageButton(NSImage.goLeftTemplateName)
		goBackButton.toolTip    = "Go Back"
		goForwardButton         = OakCreateImageButton(NSImage.goRightTemplateName)
		goForwardButton.toolTip = "Go Forward"

		folderPopUpButton.setAccessibilityLabel("Current folder")
		goBackButton.image?.accessibilityDescription    = goBackButton.toolTip
		goForwardButton.image?.accessibilityDescription = goForwardButton.toolTip

		let bottomDivider = OakCreateNSBoxSeparator()!

		let views: [String: NSView] = [
			"folder":        folderPopUpButton,
			"divider":       OakCreateNSBoxSeparator()!,
			"back":          goBackButton,
			"forward":       goForwardButton,
			"bottomDivider": bottomDivider,
		]

		OakAddAutoLayoutViewsToSuperview(Array(views.values), self)
		OakSetupKeyViewLoop([self, folderPopUpButton, goBackButton, goForwardButton])

		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(3)-[folder(>=75)]-(3)-[divider(==1)]-(2)-[back(==22)]-(2)-[forward(==back)]-(3)-|", options: .alignAllCenterY, metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[bottomDivider]|", options: [], metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-(4)-[divider(==15)]-(4)-[bottomDivider(==1)]|", options: [], metrics: nil, views: views))
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
