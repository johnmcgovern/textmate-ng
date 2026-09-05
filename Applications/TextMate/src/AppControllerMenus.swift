import AppKit
import os

// os_log(OS_LOG_DEFAULT, …) has no Swift spelling. A default-initialised Logger
// writes to the same default subsystem the two migration messages used.
private let log = Logger()

// Ported from `AppController Menus.mm`, which was already free of C++ before the
// flip. An extension rather than a category: Swift has no categories, and these
// methods read the four NSMenu properties declared on the class, which an
// extension in the same module can see.

// NSLocale rather than the original's CFLocale: -displayNameForKey:value: *is*
// CFLocaleCopyDisplayNameForPropertyValue and +systemLocale is CFLocaleGetSystem,
// toll-free bridged, so this is the same two calls in the same order. The CF
// spelling needs CFLocaleIdentifier, which is a CF_EXTENSIBLE_STRING_ENUM and so
// imports as a struct rather than a CFString — noise for no gain here.
private func NameForLocaleIdentifier(_ languageCode: String) -> String {
	let localLanguage = NSLocale(localeIdentifier: languageCode).displayName(forKey: .identifier, value: languageCode)?.capitalized
	let systemLanguage = (NSLocale.system as NSLocale).displayName(forKey: .identifier, value: languageCode)?.capitalized
	return localLanguage ?? systemLanguage ?? languageCode
}

extension AppController {
	func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>, action: UnsafeMutablePointer<Selector?>) -> Bool {
		return false
	}

	@objc func bundlesMenuNeedsUpdate(_ aMenu: NSMenu) {
		for i in stride(from: aMenu.numberOfItems - 1, through: 0, by: -1) {
			if aMenu.item(at: i)?.isSeparatorItem == true {
				break
			}
			aMenu.removeItem(at: i)
		}

		// -sortedByName: is stable_sort over text::less_t, which is exactly what the
		// std::multimap keyed on the name gave: equal names keep insertion order.
		let ordered = TMBundleItem.sortedByName(TMBundleItem.items(ofKinds: .bundle, inScope: nil))

		for item in ordered {
			if item.menu.isEmpty {
				continue
			}

			let menuItem = aMenu.addItem(withTitle: item.name ?? "", action: nil, keyEquivalent: "")
			let submenu = NSMenu(title: item.uuidString ?? "")
			submenu.delegate = BundleMenuDelegate.sharedInstance
			menuItem.submenu = submenu
		}

		if ordered.isEmpty {
			aMenu.addItem(withTitle: "No Bundles Loaded", action: Selector(("nop:")), keyEquivalent: "")
		}
	}

	// Was +initialize, converted to explicit registration (rule 24).
	//
	// A Swift class cannot provide +initialize, so this had to move before the class
	// could be ported — and it is a behaviour-preserving step on its own, which is
	// why it was its own commit.
	//
	// Timing is the whole risk in the move. +initialize ran when MainMenu.xib
	// instantiated AppController; this runs at the top of
	// -applicationWillFinishLaunching:, the first of the app's own code after the
	// nib is loaded. Nothing reads these defaults in between — the only in-process
	// reader is -[OakTextView effectiveThemeUUID], and the earliest an OakTextView
	// exists is session restore, at the *end* of that same method. The three
	// observers still register before NSApplicationDidFinishLaunchingNotification
	// is posted, which is what they wait for.
	//
	// A `static let` is the dispatch_once: +initialize ran once and these are
	// notification registrations, so running it twice would apply the theme
	// appearance twice per defaults change and re-arm a migration meant to happen
	// once. Swift guarantees a static's initialiser runs exactly once, lazily.
	//
	// MainActor.assumeIsolated because the body reads NSApp and installs
	// main-queue observers, and a `static let` initialiser is nonisolated. The
	// assumption is sound: the only two callers are
	// -applicationWillFinishLaunching: and t_app_controller.mm, both on the main
	// thread. Same discipline as OakPasteboard's NSApp guard.
	private static let themeDefaultsAndObservers: Void = MainActor.assumeIsolated {
		UserDefaults.standard.register(defaults: [
			"universalThemeUUID": String(cString: kMacClassicThemeUUID),
			"darkModeThemeUUID":  String(cString: kTwilightThemeUUID),
		])

		// MIGRATION from 2.0.12 and earlier
		nonisolated(unsafe) var token: NSObjectProtocol?
		token = NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: NSApp, queue: nil) { _ in
			if let token { NotificationCenter.default.removeObserver(token) }

			if let savedThemeUUID = AppControllerSupport.globalThemeSetting() {
				log.log("Remove old theme setting from Global.tmProperties: \(savedThemeUUID, privacy: .public)")
				AppControllerSupport.clearGlobalThemeSetting()

				if let themeItem = TMBundleItem.item(uuidString: savedThemeUUID) {
					// -hasPrefix: on a nil semanticClass is NO, which is what
					// std::string::find(…) == 0 answered for NULL_STR.
					let darkTheme   = themeItem.semanticClass?.hasPrefix("theme.dark") ?? false
					let mode        = darkTheme ? "dark"              : "light"
					let defaultsKey = darkTheme ? "darkModeThemeUUID" : "universalThemeUUID"

					log.log("Set preferred appearance to \(mode, privacy: .public)")
					UserDefaults.standard.set(savedThemeUUID, forKey: defaultsKey)
					UserDefaults.standard.set(mode, forKey: "themeAppearance")
				}
			}

			UserDefaults.standard.removeObject(forKey: "changeThemeBasedOnAppearance")
		}

		// Apply the theme appearance to the *application*, not just the editor. See
		// +applyThemeAppearance. Both on the main queue deliberately: user-defaults
		// change notifications are delivered on whichever thread made the change —
		// including another process — and NSApp.appearance is main-thread-only. That
		// is the same hazard that shipped as the alpha.13 Software Update crash.
		NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: NSApp, queue: .main) { _ in
			MainActor.assumeIsolated { AppController.applyThemeAppearance() }
		}

		NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main) { _ in
			MainActor.assumeIsolated { AppController.applyThemeAppearance() }
		}
	}

	@objc class func setupThemeDefaultsAndObservers() {
		_ = themeDefaultsAndObservers
	}

	// Make the window chrome follow the chosen theme appearance.
	//
	// **This diverges from upstream on purpose.** Upstream treats `themeAppearance`
	// as picking an editor *theme* and lets AppKit chrome follow the system, so on a
	// light-appearance Mac choosing Dark gives a black editor inside a white window
	// with a white file browser. Nothing in this project's history ever set
	// NSApp.appearance — checked with `git log -S` across all branches — so this is
	// new behaviour rather than a restored regression. Reported 2026-08-18 as
	// "the sidebar stays light in dark mode", which is a fair reading of it.
	//
	// `nil` is the important case: Auto must leave NSApp.appearance unset so the app
	// follows the system, which is what makes -viewDidChangeEffectiveAppearance fire
	// and OakTextView re-resolve its theme. Setting an explicit appearance instead
	// would pin it and break Auto.
	//
	// No feedback loop, and the reason is worth stating: -effectiveThemeUUID only
	// consults -effectiveAppearance when the setting is Auto, and Auto is exactly
	// the case where this sets nothing. An explicit Light/Dark never round-trips
	// through the appearance it just set.
	//
	// The guard is not an optimisation. Assigning NSApp.appearance re-broadcasts
	// -viewDidChangeEffectiveAppearance to every view in the app, and this runs on
	// every user-defaults change — which is frequent.
	@objc class func applyThemeAppearance() {
		let setting = UserDefaults.standard.string(forKey: "themeAppearance")

		var name: NSAppearance.Name? = nil
		if setting == "dark" {
			name = .darkAqua
		} else if setting == "light" {
			name = .aqua
		}

		let currentName = NSApp.appearance?.name // nil when never set
		// Covers both halves of the original `currentName == name || [currentName
		// isEqualToString:name]`: Optional's == is true for nil == nil and string
		// equality otherwise.
		if currentName == name {
			return
		}

		NSApp.appearance = name.flatMap { NSAppearance(named: $0) }
	}

	@objc func takeThemeAppearanceFrom(_ sender: Any?) {
		UserDefaults.standard.set((sender as? NSMenuItem)?.representedObject, forKey: "themeAppearance")
		// The defaults notification would reach +applyThemeAppearance anyway; calling
		// it here makes the menu feel synchronous. Idempotent, so the later
		// notification is a no-op.
		AppController.applyThemeAppearance()
	}

	@objc func takeUniversalThemeUUIDFrom(_ sender: Any?) {
		UserDefaults.standard.set((sender as? NSMenuItem)?.representedObject, forKey: "universalThemeUUID")
	}

	@objc func takeDarkThemeUUIDFrom(_ sender: Any?) {
		UserDefaults.standard.set((sender as? NSMenuItem)?.representedObject, forKey: "darkModeThemeUUID")
	}

	@objc func validateThemeMenuItem(_ item: NSMenuItem) -> Bool {
		if item.action == #selector(takeThemeAppearanceFrom(_:)) {
			let representedObject = item.representedObject as? String
			let savedValue = UserDefaults.standard.string(forKey: "themeAppearance")
			// `!ro && !saved || [ro isEqualToString:saved]` — messaging a nil
			// representedObject answered NO, and so does the second clause here.
			item.state = (representedObject == nil && savedValue == nil) || (representedObject != nil && representedObject == savedValue) ? .on : .off

			var label: String? = nil
			var defaultsKey: String? = nil
			if representedObject == "light" {
				label = "Light Theme"
				defaultsKey = "universalThemeUUID"
			} else if representedObject == "dark" {
				label = "Dark Theme"
				defaultsKey = "darkModeThemeUUID"
			}

			if let defaultsKey, let label {
				let themeUUID = UserDefaults.standard.string(forKey: defaultsKey)
				if let themeItem = TMBundleItem.item(uuidString: themeUUID) {
					item.title = "\(label) (\(themeItem.name ?? ""))"
				}
			}
		} else if item.action == #selector(takeUniversalThemeUUIDFrom(_:)) {
			item.state = (item.representedObject as? String) == UserDefaults.standard.string(forKey: "universalThemeUUID") ? .on : .off
		} else if item.action == #selector(takeDarkThemeUUIDFrom(_:)) {
			item.state = (item.representedObject as? String) == UserDefaults.standard.string(forKey: "darkModeThemeUUID") ? .on : .off
		}
		return true
	}

	@objc func themesMenuNeedsUpdate(_ aMenu: NSMenu) {
		aMenu.removeAllItems()

		var ordered: [String: [TMBundleItem]] = [:]
		for item in TMBundleItem.items(ofKinds: .theme, inScope: nil) {
			if item.isHiddenFromUser {
				continue
			}

			// A nil semanticClass splits to an empty array, so it falls to
			// "unspecified" — which is what text::split(NULL_STR, ".") did, since the
			// sentinel is one component and the test is `> 2`.
			let semanticClass = item.semanticClass?.components(separatedBy: ".") ?? []
			let themeClass = semanticClass.count > 2 && semanticClass.first == "theme" ? semanticClass[1] : "unspecified"

			ordered[themeClass, default: []].append(item)
		}

		if ordered.isEmpty {
			aMenu.addItem(withTitle: "No Themes Loaded", action: Selector(("nop:")), keyEquivalent: "")
			return
		}

		let refs = TMMenus.buildThemeMenu(into: aMenu, target: self)
		let lightMenu = refs.lightMenu
		let darkMenu  = refs.darkMenu

		// std::map iterated its keys in byte order; -compare: is the same ordering for
		// these ("dark", "light", "unspecified"), and the group order is what puts the
		// separators in the right places.
		let themeClasses = ordered.keys.sorted { $0.compare($1) == .orderedAscending }

		// A C++ initializer_list tolerated a nil menu and messaging nil is a no-op; an
		// NSArray literal would throw instead, so build the list rather than assume
		// both submenus came back.
		var submenus: [NSMenu] = []
		if let lightMenu { submenus.append(lightMenu) }
		if let darkMenu  { submenus.append(darkMenu) }

		for submenu in submenus {
			let isLight = submenu === lightMenu
			let skipThemeClass = isLight ? "dark" : "light"
			let action = isLight ? #selector(takeUniversalThemeUUIDFrom(_:)) : #selector(takeDarkThemeUUIDFrom(_:))

			for themeClass in themeClasses {
				if themeClass == skipThemeClass {
					continue
				}

				if submenu.numberOfItems != 0 {
					submenu.addItem(NSMenuItem.separator())
				}

				for item in TMBundleItem.sortedByName(ordered[themeClass] ?? []) {
					let menuItem = submenu.addItem(withTitle: item.name ?? "", action: action, keyEquivalent: "")
					menuItem.setKeyEquivalentString(item.keyEquivalent)
					menuItem.representedObject = item.uuidString
				}
			}
		}
	}

	@objc func spellingMenuNeedsUpdate(_ aMenu: NSMenu) {
		for i in stride(from: aMenu.numberOfItems - 1, through: 0, by: -1) {
			if aMenu.item(at: i)?.action == Selector(("takeSpellingLanguageFrom:")) {
				aMenu.removeItem(at: i)
			}
		}

		let spellChecker = NSSpellChecker.shared

		// The display name is computed once per language, as the multimap key was —
		// NameForLocaleIdentifier builds a CFLocale each call, and a comparator would
		// invoke it O(n log n) times.
		var displayNames: [String: String] = [:]
		for lang in spellChecker.availableLanguages {
			displayNames[lang] = NameForLocaleIdentifier(lang)
		}

		// Sorting -availableLanguages rather than the dictionary's keys: NSSortStable
		// keeps equal display names in *that* order, which is the insertion order the
		// std::multimap preserved. allKeys has no defined order to be stable about.
		let ordered = (spellChecker.availableLanguages as NSArray).sortedArray(options: .stable) { lhs, rhs in
			AppControllerSupport.compare(forMenuOrder: displayNames[lhs as! String], to: displayNames[rhs as! String])
		} as! [String]

		let systemSpellingLanguage = spellChecker.automaticallyIdentifiesLanguages ? "Automatic by Language" : NameForLocaleIdentifier(spellChecker.language())
		let menuItem = aMenu.addItem(withTitle: "System (\(systemSpellingLanguage))", action: Selector(("takeSpellingLanguageFrom:")), keyEquivalent: "")
		menuItem.representedObject = ""

		for lang in ordered {
			let menuItem = aMenu.addItem(withTitle: displayNames[lang] ?? "", action: Selector(("takeSpellingLanguageFrom:")), keyEquivalent: "")
			menuItem.representedObject = lang
		}
	}

	@objc func wrapColumnMenuNeedsUpdate(_ aMenu: NSMenu) {
		aMenu.removeAllItems()

		let action = Selector(("takeWrapColumnFrom:"))
		var menuItem: NSMenuItem

		menuItem = aMenu.addItem(withTitle: "Use Window Frame", action: action, keyEquivalent: "")
		menuItem.tag = Int(NSWrapColumnWindowWidth)
		aMenu.addItem(NSMenuItem.separator())

		let presets = (UserDefaults.standard.array(forKey: kUserDefaultsWrapColumnPresetsKey) as? [NSNumber]) ?? []
		for preset in presets.sorted(by: { $0.compare($1) == .orderedAscending }) {
			menuItem = aMenu.addItem(withTitle: "\(preset)", action: action, keyEquivalent: "")
			menuItem.tag = preset.intValue
		}

		aMenu.addItem(NSMenuItem.separator())
		menuItem = aMenu.addItem(withTitle: "Other…", action: action, keyEquivalent: "")
		menuItem.tag = Int(NSWrapColumnAskUser)
	}

	func menuNeedsUpdate(_ aMenu: NSMenu) {
		// Identity, not equality: these four are dispatched on by pointer, exactly as
		// the ObjC `aMenu == bundlesMenu` did.
		if aMenu === bundlesMenu {
			bundlesMenuNeedsUpdate(aMenu)
		} else if aMenu === themesMenu {
			themesMenuNeedsUpdate(aMenu)
		} else if aMenu === spellingMenu {
			spellingMenuNeedsUpdate(aMenu)
		} else if aMenu === wrapColumnMenu {
			wrapColumnMenuNeedsUpdate(aMenu)
		}
	}
}
