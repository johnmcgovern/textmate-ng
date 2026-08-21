import AppKit

// Ported from OakAbbreviations.mm (2026-08-20). A per-name store of "short → long"
// abbreviations the file and bundle-item choosers use to remember which expansion the
// user picked for a typed prefix. Persisted under its name in NSUserDefaults, capped at
// 50 entries, flushed on app terminate. FileChooser.mm and BundleItemChooser.mm still
// consume it as ObjC++ through the hand-declaration in OakAbbreviations.h; behaviour is
// pinned by t_abbreviations.mm (rule 18).
//
// Not @MainActor, matching the ObjC++ it replaces (the choosers touch it on the main
// thread but nothing enforces that). The +abbreviationsForName: cache is the original's
// static-local NSMutableDictionary; instances are never evicted, so like the ObjC++ they
// never deallocate and there is no deinit — the terminate observer does the one flush
// that matters, exactly as the (unreachable) dealloc did.
@objc(OakAbbreviations)
class OakAbbreviations: NSObject {
	private static let abbreviationKey   = "short"
	private static let expandedStringKey = "long"

	nonisolated(unsafe) private static var sharedInstances: [String: OakAbbreviations] = [:]

	@objc(abbreviationsForName:)
	static func abbreviations(forName name: String) -> OakAbbreviations {
		if let existing = sharedInstances[name] {
			return existing
		}
		let instance = OakAbbreviations(name: name)
		sharedInstances[name] = instance
		return instance
	}

	private let name: String
	private var bindings: [[String: String]]

	private init(name: String) {
		self.name = name
		self.bindings = (UserDefaults.standard.array(forKey: name) as? [[String: String]]) ?? []
		super.init()
		// object: nil, not NSApp — only NSApp posts this, and reading NSApp from this
		// nonisolated init would need a main-actor hop for no behavioural gain (same
		// reasoning as OakPasteboard's active-app observers).
		NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate(_:)), name: NSApplication.willTerminateNotification, object: nil)
	}

	@objc private func applicationWillTerminate(_ notification: Notification?) {
		if bindings.count > 50 {
			bindings = Array(bindings.prefix(50))
		}
		UserDefaults.standard.set(bindings, forKey: name)
	}

	@objc(stringsForAbbreviation:)
	func strings(forAbbreviation abbreviation: String?) -> [String] {
		var exactMatches: [String]  = []
		var prefixMatches: [String] = []

		if OakIsEmptyString(abbreviation) {
			return exactMatches
		}

		for binding in bindings {
			guard let abbr = binding[Self.abbreviationKey], let path = binding[Self.expandedStringKey] else {
				continue
			}

			if abbr == abbreviation {
				exactMatches.append(path)
			} else if let abbreviation, abbr.hasPrefix(abbreviation) {
				prefixMatches.append(path)
			}
		}

		exactMatches.append(contentsOf: prefixMatches)
		return exactMatches
	}

	@objc(learnAbbreviation:forString:)
	func learn(abbreviation: String?, forString string: String?) {
		if OakIsEmptyString(abbreviation) || OakIsEmptyString(string) {
			return
		}

		let dict = [Self.abbreviationKey: abbreviation!, Self.expandedStringKey: string!]
		bindings.removeAll { $0 == dict }
		bindings.insert(dict, at: 0)
	}
}
