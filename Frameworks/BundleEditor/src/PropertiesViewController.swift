// One class, eight nibs: BundleProperties, CommandProperties, FileDropProperties,
// GrammarProperties, MacroProperties, SharedProperties, SnippetProperties and
// ThemeProperties all name `PropertiesViewController` as File's Owner and bind
// their fields through `objectController` (key paths `selection.<property>`).
//
// String contracts the xibs depend on — changing any of these silently breaks
// bindings at runtime, with no build error:
//   * the class name, hence @objc(PropertiesViewController)
//   * the outlet names objectController / alignmentView / keyEquivalentView
//   * the `properties` key path the object controller's content is bound to
import AppKit

@objc(PropertiesViewController) class PropertiesViewController: NSViewController {
	@IBOutlet private var objectController: NSObjectController!
	@IBOutlet private var alignmentView: NSView!
	@IBOutlet private var keyEquivalentView: OakKeyEquivalentView!

	private var _properties = NSMutableDictionary()

	@objc init?(name: String) {
		super.init(nibName: name, bundle: Bundle(for: PropertiesViewController.self))
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported — panes are created by nib name")
	}

	// Getter commits any in-flight field edit first, so reading properties
	// straight after typing sees the typed value rather than the previous one.
	@objc var properties: NSMutableDictionary {
		get {
			objectController?.commitEditing()
			return _properties
		}
		set { _properties = newValue }
	}

	@objc var labelWidth: CGFloat {
		alignmentView != nil ? alignmentView.frame.maxX + 5 : 20
	}

	override func loadView() {
		super.loadView()
		keyEquivalentView?.bind(.value, to: objectController as Any, withKeyPath: "selection.keyEquivalent", options: nil)
	}
}
