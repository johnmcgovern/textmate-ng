// The only nib-backed pane. Three things here are load-bearing for the xib and
// must not be "cleaned up":
//
//  * @objc(TerminalPreferences) — TerminalPreferences.xib names this as its
//    File's Owner custom class, by string. Renaming the Swift class is fine;
//    changing this is not.
//  * The five @IBOutlet names — installStatusText, installSummaryText,
//    installPathPopUp, installButton, rmateSummaryText — are the outlet keys
//    stored in the xib.
//  * `installIndicaitorImage` keeps its original misspelling: the xib binds to
//    that exact key path. Fixing the typo means editing the xib too.
//
// The xib also binds disableRMate / interface / port, which resolve through
// PreferencesPane's value(forUndefinedKey:) routing, and wires Help buttons to
// the base class's help: action.
import AppKit

@objc(TerminalPreferences) final class TerminalPreferences: PreferencesPane {
	@IBOutlet private var installStatusText: NSTextField!
	@IBOutlet private var installSummaryText: NSTextField!
	@IBOutlet private var installPathPopUp: NSPopUpButton!
	@IBOutlet private var installButton: NSButton!
	@IBOutlet private var rmateSummaryText: NSTextField!

	// The xib ships these fields pre-filled with ${variable} templates; they are
	// captured once at load and re-expanded on every UI update.
	private var statusTextFormat = ""
	private var summaryTextFormat = ""

	@objc dynamic var installIndicaitorImage: NSImage?

	init() {
		super.init(nibName: "TerminalPreferences", label: "Terminal", image: NSImage(named: "Terminal", inSameBundleAsClass: TerminalPreferences.self))

		OakStringListTransformer.createTransformer(withName: "OakRMateInterfaceTransformer", andObjectsArray: [kRMateServerListenLocalhost, kRMateServerListenRemote])

		defaultsProperties = [
			"path":         kUserDefaultsMateInstallPathKey,
			"disableRMate": kUserDefaultsDisableRMateServerKey,
			"interface":    kUserDefaultsRMateServerListenKey,
			"port":         kUserDefaultsRMateServerPortKey,
		]
	}

	@objc private func selectInstallPath(_ sender: Any?) {
		let savePanel = NSSavePanel()
		savePanel.nameFieldStringValue = "mate"
		guard let window = view.window else { return }
		savePanel.beginSheetModal(for: window) { result in
			if result == .OK, let path = savePanel.url?.standardizedFileURL.path {
				self.updatePopUp(path)
			} else {
				self.installPathPopUp.selectItem(at: 0)
			}
			self.updateUI(self)
		}
	}

	private func updatePopUp(_ path: String?) {
		guard let menu = installPathPopUp.menu else { return }
		menu.removeAllItems()

		let abbreviated = path.map { ($0 as NSString).abbreviatingWithTildeInPath }
		if let abbreviated, abbreviated != "~/bin/mate", abbreviated != "/usr/local/bin/mate" {
			menu.addItem(withTitle: abbreviated, action: #selector(updateUI(_:)), keyEquivalent: "")
		}
		menu.addItem(withTitle: "/usr/local/bin/mate", action: #selector(updateUI(_:)), keyEquivalent: "")
		menu.addItem(withTitle: "~/bin/mate", action: #selector(updateUI(_:)), keyEquivalent: "")
		menu.addItem(.separator())
		menu.addItem(withTitle: "Other…", action: #selector(selectInstallPath(_:)), keyEquivalent: "")

		for menuItem in menu.items {
			menuItem.target = self
		}

		if let abbreviated {
			installPathPopUp.selectItem(withTitle: abbreviated)
		}
	}

	@objc private func updateUI(_ sender: Any?) {
		let isInstalled = mateInstallPath != nil

		var variables: [String: String] = [:]
		if isInstalled {
			variables["installed"] = "installed"
		}
		variables["mate_path"] = mateInstallPath.map { ($0 as NSString).abbreviatingWithTildeInPath }
			?? installPathPopUp.titleOfSelectedItem
			?? ""

		installStatusText.stringValue = PWExpandFormatString(statusTextFormat, variables)
		installSummaryText.stringValue = PWExpandFormatString(summaryTextFormat, variables)
		installIndicaitorImage = NSImage(named: isInstalled ? NSImage.statusAvailableName : NSImage.statusUnavailableName)

		installPathPopUp.isEnabled = !isInstalled
		installButton.action = isInstalled ? #selector(performUninstallMate(_:)) : #selector(performInstallMate(_:))
		installButton.state = isInstalled ? .on : .off
	}

	override func loadView() {
		super.loadView()

		// A recorded install path that no longer exists means the tool was removed
		// behind our back; forget it so the UI offers to install again.
		if let path = mateInstallPath, access((path as NSString).fileSystemRepresentation, F_OK) != 0 {
			UserDefaults.standard.removeObject(forKey: kUserDefaultsMateInstallPathKey)
			UserDefaults.standard.removeObject(forKey: kUserDefaultsMateInstallVersionKey)
		}

		installPathPopUp.target = self
		installButton.target = self
		statusTextFormat = installStatusText.stringValue
		summaryTextFormat = installSummaryText.stringValue
		updatePopUp(mateInstallPath)
		updateUI(self)

		createHyperLink(rmateSummaryText, text: "rmate", url: "https://github.com/textmate/rmate/")
		LSSetDefaultHandlerForURLScheme("txmt" as CFString, CFBundleGetIdentifier(CFBundleGetMainBundle()))
	}

	override var preferredContentSize: NSSize {
		get { view.frame.size }
		set { super.preferredContentSize = newValue }
	}

	private func createHyperLink(_ textField: NSTextField, text: String, url: String) {
		textField.allowsEditingTextAttributes = true
		textField.isSelectable = true

		let attrString = NSMutableAttributedString(attributedString: textField.attributedStringValue)
		let range = (attrString.string as NSString).range(of: text)
		guard range.location != NSNotFound else { return }

		attrString.beginEditing()
		attrString.addAttribute(.link, value: url, range: range)
		attrString.addAttribute(.foregroundColor, value: NSColor.blue, range: range)
		attrString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
		attrString.endEditing()

		textField.attributedStringValue = attrString
	}

	@objc var mateInstallPath: String? {
		get {
			guard let path = UserDefaults.standard.string(forKey: kUserDefaultsMateInstallPathKey) else { return nil }
			return (path as NSString).expandingTildeInPath
		}
		set {
			if let newValue {
				UserDefaults.standard.set(newValue, forKey: kUserDefaultsMateInstallPathKey)
			} else {
				UserDefaults.standard.removeObject(forKey: kUserDefaultsMateInstallPathKey)
			}
		}
	}

	private func installMate(as dstPath: String) {
		guard let srcPath = Foundation.Bundle.main.path(forAuxiliaryExecutable: "mate") else {
			let alert = NSAlert()
			alert.messageText = "Unable to find ‘mate’"
			alert.informativeText = "The ‘mate’ binary is missing from the application bundle. We recommend that you re-download the application."
			alert.addButton(withTitle: "OK")
			alert.runModal()
			updateUI(self)
			return
		}

		if PWInstallMate(srcPath, dstPath) {
			mateInstallPath = dstPath
			if let version = PWMateVersion(srcPath) {
				UserDefaults.standard.set(version, forKey: kUserDefaultsMateInstallVersionKey)
			}
		}
		updateUI(self)
	}

	@IBAction func performInstallMate(_ sender: Any?) {
		guard let selectedTitle = installPathPopUp.titleOfSelectedItem else { return }
		let dstObjPath = (selectedTitle as NSString).expandingTildeInPath

		var buf = stat()
		if lstat((dstObjPath as NSString).fileSystemRepresentation, &buf) == 0 {
			let itemType: String
			switch buf.st_mode & S_IFMT {
				case S_IFREG: itemType = "A file"
				case S_IFDIR: itemType = "A folder"
				case S_IFLNK: itemType = "A link"
				default:      itemType = "An item"
			}

			let parent = ((dstObjPath as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
			let alert = NSAlert()
			alert.alertStyle = .warning
			alert.messageText = "File Already Exists"
			alert.informativeText = "\(itemType) with the name “mate” already exists in the folder \(parent). Do you want to replace it?"
			alert.addButton(withTitle: "Replace")
			alert.addButton(withTitle: "Cancel")
			guard let window = view.window else { return }
			alert.beginSheetModal(for: window) { returnCode in
				if returnCode == .alertFirstButtonReturn, let title = self.installPathPopUp.titleOfSelectedItem {
					self.installMate(as: (title as NSString).expandingTildeInPath)
				}
			}
		} else {
			installMate(as: dstObjPath)
		}
		updateUI(self)
	}

	@IBAction func performUninstallMate(_ sender: Any?) {
		if let path = mateInstallPath, PWUninstallMate(path) {
			mateInstallPath = nil
		}
		updateUI(self)
	}

	@objc class func updateMateIfRequired() {
		let oldMate = UserDefaults.standard.string(forKey: kUserDefaultsMateInstallPathKey).map { ($0 as NSString).expandingTildeInPath }
		let oldVersion = UserDefaults.standard.string(forKey: kUserDefaultsMateInstallVersionKey)
		let newMate = Foundation.Bundle.main.path(forAuxiliaryExecutable: "mate")

		guard let oldMate, let newMate else { return }

		DispatchQueue.global(qos: .utility).async {
			guard let newVersion = PWMateVersion(newMate),
			      OakCompareVersionStrings(oldVersion, newVersion) == .orderedAscending
			else { return }

			if PWCopyRequiresAdmin(oldMate) {
				DispatchQueue.main.async {
					let alert = NSAlert()
					alert.messageText = "Update Shell Support"
					alert.informativeText = "Would you like to update the installed version of mate to version \(newVersion)?"
					alert.addButton(withTitle: "Update")
					alert.addButton(withTitle: "Cancel")
					if alert.runModal() == .alertFirstButtonReturn {
						if !PWInstallMate(newMate, oldMate) {
							return
						}
					}
					// Avoid asking again by storing the new version number
					UserDefaults.standard.set(newVersion, forKey: kUserDefaultsMateInstallVersionKey)
				}
			} else if PWInstallMate(newMate, oldMate) {
				UserDefaults.standard.set(newVersion, forKey: kUserDefaultsMateInstallVersionKey)
			}
		}
	}
}
