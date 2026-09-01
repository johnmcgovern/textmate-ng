import AppKit

// Ported from TMPlugInController.mm (2026-09-01). Loads and installs .tmplugin
// bundles. The C++ it used to hold is in TMPlugInSupport; the class itself is
// NSBundle, NSUserDefaults, NSAlert and four POSIX calls.
//
// The hand declaration in TMPlugInController.h is what AppController.mm and
// plug-ins see (rule 23); the two protocols live in TMPlugInAPI.h so the
// bridging header can take them without also re-declaring this class (rule 43).
//
// Three details carry the port:
//
// - The NSAlert convenience methods are ObjC variadics, which Swift cannot call.
//   Each one is inlined the way DocumentWindowController and OakHTMLOutputView
//   already do it: +tmAlertWithMessageText:informativeText:buttons: sets two
//   strings and adds buttons, and -addButtons: is a loop over
//   -addButtonWithTitle:. Nothing else about the alerts changed.
//
// - loadedPlugIns stays an NSMutableDictionary rather than becoming
//   [String: Any]. It is the class's memory of what is loaded, keyed by bundle
//   identifier, and the test seeds it through the getter.
//
// - The crash-marker file keeps its POSIX calls verbatim — path::exists *is*
//   access(F_OK), and open/close/unlink are the same three syscalls. Note that
//   the original opens with O_CREAT and no mode argument, which is undefined in
//   C and left as-is here: the file is created and unlinked within the same
//   call, and nothing ever reads it.
@objc(TMPlugInController)
class TMPlugInController: NSObject, TMPlugInControllerProtocol {
	private static let kPlugInAPIVersion = 2
	private static let kUserDefaultsDisabledPlugInsKey = "disabledPlugIns"

	// Was +initialize. Emmet crashes this fork, so the default is load-bearing;
	// -init touches it, and -init is the only way to reach an instance.
	private static let registerDefaults: Void = {
		UserDefaults.standard.register(defaults: [
			kUserDefaultsDisabledPlugInsKey: [ "io.emmet.EmmetTextmate" ]
		])
	}()

	// The original was a function-local `static` in +sharedInstance: thread-safe
	// initialisation and no isolation of the value itself. nonisolated(unsafe) is
	// that, and the class deliberately stays off @MainActor — a plug-in may ask
	// the controller for its -version from wherever it likes.
	@objc nonisolated(unsafe) static let sharedInstance = TMPlugInController()

	private let plugIns = NSMutableDictionary()
	// Get-only: an @objc stored property would export a setter the original
	// never had outside its own class extension.
	@objc var loadedPlugIns: NSMutableDictionary { plugIns }

	override init() {
		super.init()
		_ = TMPlugInController.registerDefaults
	}

	// A method, not a property: both TMPlugInController.h and the protocol declare
	// it as -version, and a Swift `var` would not satisfy the requirement.
	@objc func version() -> CGFloat {
		return 2.0
	}

	@objc(loadPlugInAtPath:)
	func loadPlugIn(atPath aPath: String) {
		guard let bundle = Bundle(path: aPath) else {
			NSLog("Failed to create NSBundle for path: %@", aPath)
			return
		}

		let identifier = bundle.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String
		let name       = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String

		let blacklist = UserDefaults.standard.stringArray(forKey: TMPlugInController.kUserDefaultsDisabledPlugInsKey)
		if let identifier = identifier, blacklist?.contains(identifier) == true {
			return
		}

		// The original keys the dictionary with whatever -objectForInfoDictionaryKey:
		// returned, nil included, and -objectForKey:nil is nil — so a bundle with no
		// identifier always looks unloaded and is always re-loaded. Kept.
		guard let identifier = identifier else {
			return
		}

		if plugIns.object(forKey: identifier) != nil {
			NSLog("Skip plug-in at path: %@ (already loaded %@)", identifier, Bundle(for: type(of: plugIns.object(forKey: identifier)! as AnyObject)).bundlePath)
			return
		}

		guard (bundle.object(forInfoDictionaryKey: "TMPlugInAPIVersion") as? NSNumber)?.intValue == TMPlugInController.kPlugInAPIVersion else {
			NSLog("Skip incompatible plug-in: %@, path %@", name ?? identifier, aPath)
			return
		}

		let crashedDuringPlugInLoad = TMPlugInSupport.crashMarkerPath(forIdentifier: identifier)
		if access(crashedDuringPlugInLoad, F_OK) == 0 {
			let alert = NSAlert()
			alert.messageText     = "Move “\(name ?? identifier)” plug-in to Trash?"
			alert.informativeText = "Previous attempt of loading the plug-in caused abnormal exit. Would you like to move it to trash?"
			for title in [ "Move to Trash", "Cancel", "Skip Loading" ] {
				alert.addButton(withTitle: title)
			}

			let choice = alert.runModal()
			if choice == .alertFirstButtonReturn { // "Move to Trash"
				try? FileManager.default.trashItem(at: URL(fileURLWithPath: aPath), resultingItemURL: nil)
			}

			if choice != .alertThirdButtonReturn { // "Skip Loading"
				unlink(crashedDuringPlugInLoad)
			}

			if choice != .alertSecondButtonReturn { // "Cancel"
				return
			}
		}

		close(open(crashedDuringPlugInLoad, O_CREAT|O_TRUNC|O_WRONLY|O_CLOEXEC))

		do {
			try bundle.loadAndReturnError()
			if let instance = TMPlugInSupport.instantiatePlugIn(bundle.principalClass, controller: self, identifier: identifier) {
				plugIns[identifier] = instance
			} else {
				NSLog("Failed to instantiate plug-in class: %@, path %@", String(describing: bundle.principalClass), aPath)
			}
		} catch let loadError {
			NSLog("Failed to load ‘%@’ (%@): %@", name ?? identifier, (aPath as NSString).abbreviatingWithTildeInPath, loadError.localizedDescription)
		}

		unlink(crashedDuringPlugInLoad)
	}

	@objc func loadAllPlugIns(_ sender: Any?) {
		var paths: [String] = []
		for path in NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .allDomainsMask, true) {
			paths.append(NSString.path(withComponents: [ path, "TextMate", "PlugIns" ]))
		}
		if let builtIn = Bundle.main.builtInPlugInsPath {
			paths.append(builtIn)
		}

		for path in paths {
			for plugInName in (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [] {
				if (plugInName as NSString).pathExtension.lowercased() == "tmplugin" {
					loadPlugIn(atPath: (path as NSString).appendingPathComponent(plugInName))
				}
			}
		}
	}

	@objc(installPlugInAtPath:)
	func installPlugIn(atPath src: String) {
		let fm = FileManager.default

		let libraryPaths = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .allDomainsMask, true)
		var dst: String? = NSString.path(withComponents: [ libraryPaths[0], "TextMate", "PlugIns", (src as NSString).lastPathComponent ])
		if src == dst {
			return
		}

		let plugInBundle = Bundle(path: src)
		let plugInName   = (plugInBundle?.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? ((src as NSString).lastPathComponent as NSString).deletingPathExtension

		if (plugInBundle?.object(forInfoDictionaryKey: "TMPlugInAPIVersion") as? NSNumber)?.intValue != TMPlugInController.kPlugInAPIVersion {
			let alert = NSAlert()
			alert.messageText     = "Cannot Install Plug-in"
			alert.informativeText = "The \(plugInName) plug-in is not compatible with this version of TextMate."
			alert.addButton(withTitle: "Continue")
			alert.runModal()
			return
		}

		let blacklist = UserDefaults.standard.stringArray(forKey: TMPlugInController.kUserDefaultsDisabledPlugInsKey)
		if let identifier = plugInBundle?.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String, blacklist?.contains(identifier) == true {
			let alert = NSAlert()
			alert.messageText     = "Cannot Install Plug-in"
			alert.informativeText = "The \(plugInName) plug-in should not be used with this version of TextMate because of stability problems."
			alert.addButton(withTitle: "Continue")
			alert.runModal()
			return
		}

		if fm.fileExists(atPath: dst!) {
			let newVersion = (plugInBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? (plugInBundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
			let oldVersion = (Bundle(path: dst!)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? (Bundle(path: dst!)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String)

			let alert = NSAlert()
			alert.messageText     = "Plug-in Already Installed"
			alert.informativeText = "Version \(oldVersion ?? "???") of “\(plugInName)” is already installed.\nDo you want to replace it with version \(newVersion ?? "???")?\n\nUpgrading a plug-in will require TextMate to be relaunched."
			for title in [ "Replace", "Cancel" ] {
				alert.addButton(withTitle: title)
			}

			let choice = alert.runModal()
			if choice == .alertFirstButtonReturn { // "Replace"
				do {
					try fm.removeItem(atPath: dst!)
				} catch {
					let alert = NSAlert()
					alert.messageText     = "Install Failed"
					alert.informativeText = "Couldn't remove old plug-in (“\((dst! as NSString).abbreviatingWithTildeInPath)”)"
					alert.addButton(withTitle: "Continue")
					alert.runModal()
					dst = nil
				}
			} else if choice == .alertSecondButtonReturn { // "Cancel"
				dst = nil
			}
		}

		guard let dst = dst else {
			return
		}

		let dstDir = (dst as NSString).deletingLastPathComponent
		do {
			try fm.createDirectory(atPath: dstDir, withIntermediateDirectories: true, attributes: nil)
		} catch {
			let alert = NSAlert()
			alert.messageText     = "Install Failed"
			alert.informativeText = "It was not possible to create the plug-in folder (“\((dstDir as NSString).abbreviatingWithTildeInPath)”)"
			alert.addButton(withTitle: "Continue")
			alert.runModal()
			return
		}

		do {
			try fm.copyItem(atPath: src, toPath: dst)
		} catch {
			let alert = NSAlert()
			alert.messageText     = "Install Failed"
			alert.informativeText = "The plug-in has not been installed."
			alert.addButton(withTitle: "Continue")
			alert.runModal()
			return
		}

		let alert = NSAlert()
		alert.messageText     = "Plug-in Installed"
		alert.informativeText = "To activate “\(plugInName)” you will need to relaunch TextMate."
		for title in [ "Relaunch", "Cancel" ] {
			alert.addButton(withTitle: title)
		}
		if alert.runModal() == .alertFirstButtonReturn { // "Relaunch"
			TMPlugInSupport.relaunchApplication()
		}
	}
}
