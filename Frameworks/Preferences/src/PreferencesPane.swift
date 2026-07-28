// Base class for every preferences pane.
//
// The interesting part is the KVC routing: panes declare `defaultsProperties`
// and `tmProperties` maps, and their controls bind to key paths that do not
// exist as properties on the class. KVC funnels those through
// value(forUndefinedKey:) / setValue(_:forUndefinedKey:), which redirect to
// NSUserDefaults or to the C++ `settings` layer (via PWSupport). This works
// unchanged in Swift because NSViewController is an ObjC class and the panes
// are @objc — the ObjC KVC machinery is what does the dispatch either way.
//
// Note the original did NOT emit willChange/didChange around these writes, so a
// change made through one binding does not refresh others. Preserved: making
// them observable is a behavior change, not a port.
import AppKit

// Was declared in Preferences.h; framework-internal, so it lives here now (see
// the note in that header). The toolbar reads toolbarItemImage reflectively via
// responds(to:), which is why it stays @objc optional rather than becoming a
// plain Swift protocol requirement.
@MainActor @objc protocol PreferencesPaneProtocol: NSObjectProtocol {
	@objc optional var toolbarItemImage: NSImage? { get }
}

class PreferencesPane: NSViewController, PreferencesPaneProtocol {
	@objc private(set) var toolbarItemImage: NSImage?

	/// binding key → NSUserDefaults key
	var defaultsProperties: [String: String] = [:]
	/// binding key → `settings` (.tm_properties) key
	var tmProperties: [String: String] = [:]

	init(nibName: NSNib.Name?, label: String, image: NSImage?) {
		toolbarItemImage = image
		super.init(nibName: nibName, bundle: Bundle(for: PreferencesPane.self))
		identifier = NSUserInterfaceItemIdentifier(label)
		title = label
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported — panes are created programmatically")
	}

	override func setValue(_ value: Any?, forUndefinedKey key: String) {
		if let defaultsKey = defaultsProperties[key] {
			UserDefaults.standard.set(value, forKey: defaultsKey)
		} else if let settingsKey = tmProperties[key] {
			if let string = (value ?? "") as? String {
				PWSettingsSet(settingsKey, string, nil)
			} else {
				NSLog("setValue:forUndefinedKey: wrong type for %@: ‘%@’", key, String(describing: value))
			}
		} else {
			super.setValue(value, forUndefinedKey: key)
		}
	}

	override func value(forUndefinedKey key: String) -> Any? {
		if let defaultsKey = defaultsProperties[key] {
			return UserDefaults.standard.object(forKey: defaultsKey)
		} else if let settingsKey = tmProperties[key] {
			return PWSettingsRawGet(settingsKey, nil)
		}
		return super.value(forUndefinedKey: key)
	}

	// Wired to the Help buttons in TerminalPreferences.xib; the anchor rides in
	// the button's alternate title.
	@IBAction func help(_ sender: Any?) {
		guard let button = sender as? NSButton, let anchor = button.alternateTitle as String?, !anchor.isEmpty else { return }
		let book = Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") as? String
		NSHelpManager.shared.openHelpAnchor(NSHelpManager.AnchorName(anchor), inBook: book.map { NSHelpManager.BookName($0) })
	}
}
