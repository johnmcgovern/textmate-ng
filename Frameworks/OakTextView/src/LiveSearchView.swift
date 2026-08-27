import AppKit

// Ported from LiveSearchView.mm — the incremental-search bar that drops in above
// the editor. C++-free, so no boundary file; the only thing that could not come
// across verbatim is +initialize.
//
// The class's ObjC face is the hand declaration in LiveSearchView.h (rule 23).

private let kUserDefaultsIncrementalSearchIgnoreCaseKey = "incrementalSearchIgnoreCase"
private let kUserDefaultsIncrementalSearchWrapAroundKey = "incrementalSearchWrapAround"

@objc(LiveSearchView)
class LiveSearchView: OakBackgroundFillView {
	// +initialize has no Swift spelling (rule 20). Registering on first
	// construction is equivalent *here*, and that was checked rather than assumed:
	// these two keys are read only by the bindings set up below and by
	// t_live_search_view.mm, which constructs a view first. Nothing in the tree
	// reads them before a search bar exists.
	private static let registerDefaults: Void = {
		UserDefaults.standard.register(defaults: [
			kUserDefaultsIncrementalSearchIgnoreCaseKey: true,
			kUserDefaultsIncrementalSearchWrapAroundKey: false,
		])
	}()

	@objc var textField: NSTextField!
	@objc var ignoreCaseCheckBox: NSButton!
	@objc var wrapAroundCheckBox: NSButton!
	@objc var divider: NSView!

	override init(frame aRect: NSRect) {
		super.init(frame: aRect)

		_ = Self.registerDefaults

		style   = .header
		divider = OakCreateNSBoxSeparator()

		textField = NSTextField(frame: .zero)
		textField.focusRingType = .none

		ignoreCaseCheckBox = OakCreateCheckBox("Ignore Case")
		wrapAroundCheckBox = OakCreateCheckBox("Wrap Around")

		let views: [String: NSView] = [
			"divider":    divider,
			"textField":  textField,
			"ignoreCase": ignoreCaseCheckBox,
			"wrapAround": wrapAroundCheckBox,
		]

		OakAddAutoLayoutViewsToSuperview(Array(views.values), self)

		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[divider]|", options: [], metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(8)-[textField]-[ignoreCase]-[wrapAround]-(8)-|", options: .alignAllLastBaseline, metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[divider(==1)]-(8)-[textField]-(8)-|", options: [], metrics: nil, views: views))

		ignoreCaseCheckBox.bind(.value, to: NSUserDefaultsController.shared, withKeyPath: "values." + kUserDefaultsIncrementalSearchIgnoreCaseKey, options: nil)
		wrapAroundCheckBox.bind(.value, to: NSUserDefaultsController.shared, withKeyPath: "values." + kUserDefaultsIncrementalSearchWrapAroundKey, options: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
