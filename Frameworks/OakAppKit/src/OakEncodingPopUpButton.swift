import AppKit

// Ported from OakEncodingPopUpButton.mm once OakEncodingSupport had taken the
// C++ and the +initialize.
//
// Two things about this file are load-bearing and easy to tidy away:
//
//   * every initialiser calls OakEncodingSupport.registerDefaultEncodings()
//     *before* reading the enabled list. That was +initialize's job, and Swift
//     cannot define +initialize, so the ordering is now the caller's problem;
//   * -setEncoding: hand-rolls the push half of an NSBinding. AppKit does not do
//     this for a non-standard binding on a subclass, so removing it silently
//     stops the preference pane writing anything.

@objc(OakEncodingPopUpButton)
class OakEncodingPopUpButton: NSPopUpButton, @preconcurrency OakUserDefaultsObserver {
	private var _encoding: String?
	private var _availableEncodings: [String] = []
	private var firstMenuItem: NSMenuItem?

	@objc dynamic var encoding: String? {
		get { _encoding }
		set {
			// The ObjC++ compared pointers *and* -isEqualToString:; on Optional
			// <String> `==` is both, including the nil/nil case.
			guard _encoding != newValue else {
				return
			}

			_encoding = newValue
			if let encoding = _encoding, !_availableEncodings.contains(encoding) {
				updateAvailableEncodings()
			}
			updateMenu()

			pushThroughBinding()
		}
	}

	private var availableEncodings: [String] {
		get { _availableEncodings }
		set {
			guard _availableEncodings != newValue else {
				return
			}

			_availableEncodings = newValue
			updateMenu()
		}
	}

	// MARK: - Construction

	override init(frame frameRect: NSRect, pullsDown flag: Bool) {
		super.init(frame: frameRect, pullsDown: flag)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	// No `override`: NSPopUpButton's designated initialisers are
	// -initWithFrame:pullsDown: and -initWithCoder:, both overridden above, so
	// -init is not a designated initialiser to override. This is the one
	// FilesPreferences.swift calls, and the only one that sizes itself.
	convenience init() {
		self.init(frame: .zero, pullsDown: false)

		sizeToFit()
		if frame.width > 200 {
			setFrameSize(NSSize(width: 200, height: frame.height))
		}
	}

	private func commonInit() {
		// First, and not optional: this is what puts the eight defaults into the
		// registration domain that updateAvailableEncodings reads two lines down.
		OakEncodingSupport.registerDefaultEncodings()

		encoding = "UTF-8"
		updateAvailableEncodings()
		updateMenu()
		OakObserveUserDefaults(self)
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	// MARK: - The enabled list, and the menu built from it

	private func updateAvailableEncodings() {
		var encodings = UserDefaults.standard.stringArray(forKey: OakEncodingSupport.availableEncodingsKey) ?? []

		// A value the user has disabled still has to be displayable, or the button
		// would carry a selection with no item behind it.
		if let encoding, !encodings.contains(encoding) {
			encodings.append(encoding)
		}

		availableEncodings = encodings
	}

	private func updateMenu() {
		guard let menu else {
			return
		}

		var currentEncodingsTitle = encoding

		// Charsets.plist order, not the preference's — the filter runs over the
		// charset list. A charset whose name did not split into exactly two parts
		// has a nil group and is skipped, as text::split's size check did.
		var items: [OakCharset] = []
		for charset in OakEncodingSupport.charsets() {
			if availableEncodings.contains(charset.code), charset.group != nil {
				items.append(charset)
				if encoding == charset.code {
					currentEncodingsTitle = charset.name
				}
			}
		}

		menu.removeAllItems()
		firstMenuItem = nil

		if items.count < 10 {
			if let currentItem = populateFlat(menu, items) {
				select(currentItem)
			}
		}
		else {
			if let currentEncodingsTitle {
				// A header item with a NULL action and no represented object. It is
				// what -selectedItem returns in this shape, which is why nothing
				// should read the encoding back off the selection.
				firstMenuItem = menu.addItem(withTitle: currentEncodingsTitle, action: nil, keyEquivalent: "")
				menu.addItem(.separator())
				select(firstMenuItem)
			}
			populateHierarchical(menu, items)
		}

		menu.addItem(.separator())
		menu.addItem(withTitle: "Customize List…", action: #selector(customizeAvailableEncodings(_:)), keyEquivalent: "").target = self
	}

	private func populateFlat(_ menu: NSMenu, _ items: [OakCharset]) -> NSMenuItem? {
		var res: NSMenuItem?
		for item in items {
			let menuItem = menu.addItem(withTitle: "\(item.group ?? "") – \(item.title ?? "")", action: #selector(selectEncoding(_:)), keyEquivalent: "")
			menuItem.representedObject = item.code
			menuItem.target = self

			if item.code == encoding {
				res = menuItem
			}
		}
		return res
	}

	private func populateHierarchical(_ containingMenu: NSMenu, _ items: [OakCharset]) {
		var groupName: String?
		var menu: NSMenu?
		for item in items {
			// A new submenu per *contiguous run* of a group. A group that reappeared
			// later would get a second submenu rather than joining the first, which
			// the charset list's own ordering is what prevents.
			if groupName != item.group {
				groupName = item.group

				let submenu = NSMenu()
				submenu.autoenablesItems = false
				containingMenu.addItem(withTitle: groupName ?? "", action: nil, keyEquivalent: "").submenu = submenu
				menu = submenu
			}

			guard let menu else {
				continue
			}

			let menuItem = menu.addItem(withTitle: item.title ?? "", action: #selector(selectEncoding(_:)), keyEquivalent: "")
			menuItem.representedObject = item.code
			menuItem.target = self
			if encoding == item.code {
				menuItem.state = .on
			}
		}
	}

	// MARK: - Actions

	@objc func selectEncoding(_ sender: NSMenuItem) {
		encoding = sender.representedObject as? String
	}

	@objc func customizeAvailableEncodings(_ sender: Any?) {
		OakCustomizeEncodingsWindowController.sharedInstance.showWindow(self)
		updateMenu()
	}

	@objc func userDefaultsDidChange(_ notification: Notification!) {
		updateAvailableEncodings()
	}

	// MARK: - The binding push

	private func pushThroughBinding() {
		guard let info = infoForBinding(NSBindingName("encoding")) else {
			return
		}

		// The NSNull checks are the ObjC++'s, kept: an unbound key comes back as
		// NSNull rather than absent, and -setValue:forKeyPath: on it would throw.
		guard let controller = info[.observedObject], !(controller is NSNull) else {
			return
		}
		guard let keyPath = info[.observedKeyPath] as? String else {
			return
		}

		let oldValue = (controller as AnyObject).value(forKeyPath: keyPath) as? String
		if oldValue == nil || oldValue != _encoding {
			(controller as AnyObject).setValue(_encoding, forKeyPath: keyPath)
		}
	}
}

// =========================================
// = Customize Encodings Window Controller =
// =========================================

@objc(OakCustomizeEncodingsWindowController)
class OakCustomizeEncodingsWindowController: NSWindowController, @preconcurrency NSTableViewDataSource, @preconcurrency NSTableViewDelegate {
	@objc static let sharedInstance = OakCustomizeEncodingsWindowController()

	private var encodings: [NSMutableDictionary] = []

	init() {
		super.init(window: nil)

		OakEncodingSupport.registerDefaultEncodings()

		let enabledEncodings = Set(UserDefaults.standard.stringArray(forKey: OakEncodingSupport.availableEncodingsKey) ?? [])

		// Every charset, including the ones whose name does not split — this list
		// is not filtered the way the menu is.
		encodings = OakEncodingSupport.charsets().map { charset in
			NSMutableDictionary(dictionary: [
				"enabled": enabledEncodings.contains(charset.code),
				"name":    charset.name,
				"charset": charset.code,
			])
		}
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override var windowNibName: NSNib.Name? {
		"CustomizeEncodings"
	}

	// MARK: - NSTableView delegate

	func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
		return tableColumn?.identifier.rawValue == "enabled"
	}

	// MARK: - NSTableView data source

	func numberOfRows(in tableView: NSTableView) -> Int {
		return encodings.count
	}

	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
		guard let identifier = tableColumn?.identifier.rawValue else {
			return nil
		}
		return encodings[row][identifier]
	}

	func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
		guard let identifier = tableColumn?.identifier.rawValue else {
			return
		}
		encodings[row][identifier] = object

		let newEncodings = encodings.compactMap { encoding -> String? in
			guard (encoding["enabled"] as? NSNumber)?.boolValue ?? false else {
				return nil
			}
			return encoding["charset"] as? String
		}

		UserDefaults.standard.set(newEncodings, forKey: OakEncodingSupport.availableEncodingsKey)
	}
}
