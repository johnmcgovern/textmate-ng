import AppKit
import os

private let log = Logger(subsystem: "com.j23software.TextMate-NG", category: "Preferences")

// **Not `final`.** This class is a Cocoa Bindings target for its own properties
// (`bind(…, to: self, …)`), so AppKit registers KVO on it and Foundation builds
// an NSKVONotifying_ subclass of it at run time. That is the rule aaf4395586
// earned — a Swift class ObjC can see must not be `final` if anything subclasses
// it, and KVO counts — applied to the cases that commit's survey missed: it
// looked for *source* subclassing, and "binds to self" is the marker for the
// runtime kind. Symptom is not a clean trap but intermittent heap corruption
// surfacing later at unrelated allocations (2026-08-18).
@objc(ProjectsPreferences) class ProjectsPreferences: PreferencesPane {
	private var fileBrowserPathPopUp: NSPopUpButton?

	init() {
		super.init(nibName: nil, label: "Projects", image: NSImage(named: "Projects", inSameBundleAsClass: ProjectsPreferences.self))

		OakStringListTransformer.createTransformer(withName: "OakFileBrowserPlacementSettingsTransformer", andObjectsArray: ["left", "right"])
		OakStringListTransformer.createTransformer(withName: "OakHTMLOutputPlacementSettingsTransformer", andObjectsArray: ["bottom", "right", "window"])

		defaultsProperties = [
			"foldersOnTop":                 kUserDefaultsFoldersOnTopKey,
			"showFileExtensions":           kUserDefaultsShowFileExtensionsKey,
			"disableTabBarCollapsing":      kUserDefaultsDisableTabBarCollapsingKey,
			"disableAutoResize":            kUserDefaultsDisableFileBrowserWindowResizeKey,
			"autoRevealFile":               kUserDefaultsAutoRevealFileKey,
			"fileBrowserPlacement":         kUserDefaultsFileBrowserPlacementKey,
			"htmlOutputPlacement":          kUserDefaultsHTMLOutputPlacementKey,

			"allowExpandingLinks":          kUserDefaultsAllowExpandingLinksKey,
			"fileBrowserSingleClickToOpen": kUserDefaultsFileBrowserSingleClickToOpenKey,
			"disableTabReordering":         kUserDefaultsDisableTabReorderingKey,
			"disableTabAutoClose":          kUserDefaultsDisableTabAutoCloseKey,
		]

		tmProperties = [
			"excludePattern": PWSettingsExcludeKey(),
			"includePattern": PWSettingsIncludeKey(),
			"binaryPattern":  PWSettingsBinaryKey(),
		]
	}

	@objc private func selectOtherFileBrowserPath(_ sender: Any?) {
		let openPanel = NSOpenPanel()
		openPanel.canChooseFiles = false
		openPanel.canChooseDirectories = true
		guard let window = view.window else { return }
		openPanel.beginSheetModal(for: window) { result in
			if result == .OK, let url = openPanel.url {
				UserDefaults.standard.set(url.absoluteString, forKey: kUserDefaultsInitialFileBrowserURLKey)
			}
			self.updatePathPopUp()
		}
	}

	@objc private func takeFileBrowserPathFrom(_ sender: NSMenuItem) {
		guard let url = sender.representedObject as? URL else { return }
		UserDefaults.standard.set(url.absoluteString, forKey: kUserDefaultsInitialFileBrowserURLKey)
		updatePathPopUp()
	}

	private func menuItem(for url: URL) -> NSMenuItem {
		let item = NSMenuItem(title: FileManager.default.displayName(atPath: url.path), action: #selector(takeFileBrowserPathFrom(_:)), keyEquivalent: "")
		item.target = self
		item.representedObject = url

		do {
			let values = try (url as NSURL).resourceValues(forKeys: [.effectiveIconKey])
			if let image = (values[.effectiveIconKey] as? NSImage)?.copy() as? NSImage {
				image.size = NSSize(width: 16, height: 16)
				item.image = image
			}
		} catch {
			log.error("No NSURLEffectiveIconKey for \(url, privacy: .public): \(error, privacy: .public)")
		}

		return item
	}

	private func updatePathPopUp() {
		guard let menu = fileBrowserPathPopUp?.menu else { return }
		menu.removeAllItems()

		let defaultURLs: [URL] = [
			(try? FileManager.default.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false)) ?? FileManager.default.homeDirectoryForCurrentUser,
			FileManager.default.homeDirectoryForCurrentUser,
			URL(fileURLWithPath: "/", isDirectory: true),
		]

		var url = defaultURLs[1]
		if let urlString = UserDefaults.standard.string(forKey: kUserDefaultsInitialFileBrowserURLKey), let stored = URL(string: urlString) {
			url = stored
		}

		if !defaultURLs.contains(url) {
			menu.addItem(menuItem(for: url))
			menu.addItem(.separator())
		}

		for defaultURL in defaultURLs {
			menu.addItem(menuItem(for: defaultURL))
			if defaultURL == url {
				fileBrowserPathPopUp?.selectItem(at: menu.numberOfItems - 1)
			}
		}

		menu.addItem(.separator())
		menu.addItem(withTitle: "Other…", action: #selector(selectOtherFileBrowserPath(_:)), keyEquivalent: "")
	}

	override func loadView() {
		// Explicit types: see the note in FilesPreferences.loadView().
		let fileBrowserLocationPopUp: NSPopUpButton        = OakCreatePopUpButton(false, nil, nil)
		let foldersOnTopCheckBox: NSButton                 = OakCreateCheckBox("Folders on top")
		let showLinksAsExpandableCheckBox: NSButton        = OakCreateCheckBox("Show links as expandable")
		let openFilesOnSingleClickCheckBox: NSButton       = OakCreateCheckBox("Open files on single click")
		let keepCurrentDocumentSelectedCheckBox: NSButton  = OakCreateCheckBox("Keep current document selected")

		let fileBrowserPositionPopUp: NSPopUpButton        = OakCreatePopUpButton(false, nil, nil)
		let adjustWindowCheckBox: NSButton                 = OakCreateCheckBox("Adjust window when toggleing display")

		let showForSingleDocumentCheckBox: NSButton        = OakCreateCheckBox("Show for single document")
		let reOrderWhenOpeningAFileCheckBox: NSButton      = OakCreateCheckBox("Re-order when opening a file")
		let automaticallyCloseUnusedTabsCheckBox: NSButton = OakCreateCheckBox("Automatically close unused tabs")

		let excludeFilesTextField               = NSTextField(string: "")
		let includeFilesTextField               = NSTextField(string: "")
		let nonTextFilesTextField               = NSTextField(string: "")

		let showCommandOutputPopUp: NSPopUpButton          = OakCreatePopUpButton(false, nil, nil)

		// MBMenu (a C++ aggregate) in the original — see FilesPreferences.swift.
		for (index, title) in ["Left side", "Right side"].enumerated() {
			fileBrowserPositionPopUp.menu?.addItem(withTitle: title, action: nil, keyEquivalent: "").tag = index
		}
		for (index, title) in ["Below text view", "Right of text view", "New window"].enumerated() {
			showCommandOutputPopUp.menu?.addItem(withTitle: title, action: nil, keyEquivalent: "").tag = index
		}

		func label(_ text: String) -> NSTextField {
			OakCreateLabel(text, nil, .left, .byTruncatingMiddle)
		}

		let gridView = NSGridView(views: [
			[label("File browser location:"),  fileBrowserLocationPopUp],
			[NSGridCell.emptyContentView,      foldersOnTopCheckBox],
			[NSGridCell.emptyContentView,      showLinksAsExpandableCheckBox],
			[NSGridCell.emptyContentView,      openFilesOnSingleClickCheckBox],
			[NSGridCell.emptyContentView,      keepCurrentDocumentSelectedCheckBox],
			[],
			[label("Show file browser on:"),   fileBrowserPositionPopUp],
			[NSGridCell.emptyContentView,      adjustWindowCheckBox],
			[],
			[label("Document tabs:"),          showForSingleDocumentCheckBox],
			[NSGridCell.emptyContentView,      reOrderWhenOpeningAFileCheckBox],
			[NSGridCell.emptyContentView,      automaticallyCloseUnusedTabsCheckBox],
			[],
			[label("Exclude files matching:"), excludeFilesTextField],
			[label("Include files matching:"), includeFilesTextField],
			[label("Non-text files:"),         nonTextFilesTextField],
			[],
			[label("Show command output:"),    showCommandOutputPopUp],
		])

		for popUpButton in [fileBrowserPositionPopUp, showCommandOutputPopUp] as [NSView] {
			popUpButton.widthAnchor.constraint(equalTo: fileBrowserLocationPopUp.widthAnchor).isActive = true
		}

		excludeFilesTextField.widthAnchor.constraint(equalToConstant: 360).isActive = true
		for textField in [includeFilesTextField, nonTextFilesTextField] as [NSView] {
			textField.widthAnchor.constraint(equalTo: excludeFilesTextField.widthAnchor).isActive = true
		}

		view = PWSetupGridView(gridView, [5, 8, 12, 16])

		fileBrowserPathPopUp = fileBrowserLocationPopUp
		updatePathPopUp()

		let negate = NSValueTransformerName.negateBooleanTransformerName

		foldersOnTopCheckBox.bind(.value,                to: self, withKeyPath: "foldersOnTop",                 options: nil)
		showLinksAsExpandableCheckBox.bind(.value,       to: self, withKeyPath: "allowExpandingLinks",          options: nil)
		openFilesOnSingleClickCheckBox.bind(.value,      to: self, withKeyPath: "fileBrowserSingleClickToOpen", options: nil)
		keepCurrentDocumentSelectedCheckBox.bind(.value, to: self, withKeyPath: "autoRevealFile",               options: nil)
		fileBrowserPositionPopUp.bind(.selectedTag,      to: self, withKeyPath: "fileBrowserPlacement",         options: [.valueTransformerName: NSValueTransformerName("OakFileBrowserPlacementSettingsTransformer")])
		adjustWindowCheckBox.bind(.value,                to: self, withKeyPath: "disableAutoResize",            options: [.valueTransformerName: negate])
		showForSingleDocumentCheckBox.bind(.value,       to: self, withKeyPath: "disableTabBarCollapsing",      options: nil)
		reOrderWhenOpeningAFileCheckBox.bind(.value,     to: self, withKeyPath: "disableTabReordering",         options: [.valueTransformerName: negate])
		automaticallyCloseUnusedTabsCheckBox.bind(.value, to: self, withKeyPath: "disableTabAutoClose",         options: [.valueTransformerName: negate])
		excludeFilesTextField.bind(.value,               to: self, withKeyPath: "excludePattern",               options: nil)
		includeFilesTextField.bind(.value,               to: self, withKeyPath: "includePattern",               options: nil)
		nonTextFilesTextField.bind(.value,               to: self, withKeyPath: "binaryPattern",                options: nil)
		showCommandOutputPopUp.bind(.selectedTag,        to: self, withKeyPath: "htmlOutputPlacement",          options: [.valueTransformerName: NSValueTransformerName("OakHTMLOutputPlacementSettingsTransformer")])
	}
}
