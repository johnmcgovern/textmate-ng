import AppKit

// The file browser's bottom action strip: a create button, the gear actions
// pop-up, and reload / search / favorites / SCM buttons, with a divider above.
// The twin of OFBHeaderView — another code-built NSVisualEffectView with no
// logic — ported now that OFBHeaderView established the framework's Swift wiring.
//
// OFBActionsView.h stays as a hand-written ObjC declaration of this class (the
// DocumentWindowController.h arrangement); FileBrowserView.mm builds one and
// FileBrowserViewController.mm reaches all six controls by name to set
// targets/actions and the actions-menu delegate.

private func OakCreateImageButton(_ image: NSImage?) -> NSButton {
	let res = NSButton()
	res.setButtonType(.momentaryChange)
	res.isBordered = false
	res.image = image
	res.imagePosition = .imageOnly
	return res
}

@objc(OFBActionsView)
final class OFBActionsView: NSVisualEffectView {
	@objc var createButton: NSButton!
	@objc var actionsPopUpButton: NSPopUpButton!
	@objc var reloadButton: NSButton!
	@objc var searchButton: NSButton!
	@objc var favoritesButton: NSButton!
	@objc var scmButton: NSButton!

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)

		wantsLayer   = true
		material     = .titlebar
		blendingMode = .withinWindow
		state        = .followsWindowActiveState

		createButton       = OakCreateImageButton(NSImage(named: NSImage.addTemplateName))
		actionsPopUpButton = OakCreateActionPopUpButton(false)
		reloadButton       = OakCreateImageButton(NSImage(named: NSImage.refreshTemplateName))
		searchButton       = OakCreateImageButton(NSImage(named: "SearchTemplate", inSameBundleAsClass: OFBActionsView.self))
		favoritesButton    = OakCreateImageButton(NSImage(named: "FavoritesTemplate", inSameBundleAsClass: OFBActionsView.self))
		scmButton          = OakCreateImageButton(NSImage(named: "SCMTemplate", inSameBundleAsClass: OFBActionsView.self))

		createButton.toolTip    = "Create new file"
		reloadButton.toolTip    = "Reload file browser"
		searchButton.toolTip    = "Search current folder"
		favoritesButton.toolTip = "Show favorites"
		scmButton.toolTip       = "Show source control management status"

		reloadButton.image?.accessibilityDescription    = reloadButton.toolTip
		createButton.image?.accessibilityDescription    = createButton.toolTip
		searchButton.image?.accessibilityDescription    = searchButton.toolTip
		favoritesButton.image?.accessibilityDescription = favoritesButton.toolTip
		scmButton.image?.accessibilityDescription       = scmButton.toolTip

		let wrappedActionsPopUpButton = NSView()
		OakAddAutoLayoutViewsToSuperview([actionsPopUpButton], wrappedActionsPopUpButton)
		wrappedActionsPopUpButton.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:[popup]|", options: [], metrics: nil, views: ["popup": actionsPopUpButton!]))
		wrappedActionsPopUpButton.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[popup]|", options: [], metrics: nil, views: ["popup": actionsPopUpButton!]))

		let topDivider = OakCreateNSBoxSeparator()!

		let views: [String: NSView] = [
			"topDivider": topDivider,
			"create":     createButton,
			"divider":    OakCreateNSBoxSeparator()!,
			"actions":    wrappedActionsPopUpButton,
			"reload":     reloadButton,
			"search":     searchButton,
			"favorites":  favoritesButton,
			"scm":        scmButton,
		]

		OakAddAutoLayoutViewsToSuperview(Array(views.values), self)
		OakSetupKeyViewLoop([self, createButton, actionsPopUpButton, reloadButton, searchButton, favoritesButton, scmButton])

		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-8-[create]-8-[divider(==1)]-8-[actions(==31)]-(>=8)-[reload]-4-[search]-4-[favorites]-4-[scm]-(12)-|", options: .alignAllCenterY, metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[topDivider]|", options: [], metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[topDivider(==1)]-4-[divider(==15)]-5-|", options: [], metrics: nil, views: views))
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
