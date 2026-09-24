import AppKit
import Security

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

	// Every alert this controller shows runs on the main thread — plug-ins load
	// at launch and install from an open panel — but the class is deliberately
	// not @MainActor (see sharedInstance), so the hop is made explicit here once
	// rather than at each of the eight sites (rule 26).
	@MainActor private static func runAlert(_ messageText: String, _ informativeText: String, buttons: [String]) -> NSApplication.ModalResponse {
		let alert = NSAlert()
		alert.messageText     = messageText
		alert.informativeText = informativeText
		for title in buttons {
			alert.addButton(withTitle: title)
		}
		return alert.runModal()
	}

	// ============================================================
	// = Whether a plug-in can be loaded at all                    =
	// ============================================================
	//
	// **Only plug-ins signed by this application's own team load.** Until
	// 2026-09-23 the application disabled library validation so third-party
	// plug-ins could load — which meant it loaded, at launch, any bundle placed in
	// ~/Library/Application Support/TextMate/PlugIns, a folder anything running as
	// the user can write to. A probe dropped there ran inside the notarized
	// alpha.34. Validation is on now, and the system refuses such a bundle at
	// dlopen whatever this code does.
	//
	// This asks the same question first, so the answer is a sentence rather than
	// a dlopen failure: install says why it cannot, and launch logs one clear line
	// instead of attempting a load that cannot succeed. The requirement is the one
	// validation enforces — a certificate chain to Apple naming our Team ID.
	//
	// An ad-hoc developer build has no Team ID and keeps validation relaxed (see
	// Entitlements.plist), so there is nothing to match and everything is allowed,
	// exactly as the system will allow it.

	private static let ownTeamIdentifier: String? = {
		var code: SecCode?
		guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
		var staticCode: SecStaticCode?
		guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
		var info: CFDictionary?
		guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
		      let dict = info as? [String: Any] else { return nil }
		return dict[kSecCodeInfoTeamIdentifier as String] as? String
	}()

	static func plugInIsLoadable(atPath path: String) -> Bool {
		guard let team = ownTeamIdentifier else {
			return true
		}
		var staticCode: SecStaticCode?
		guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
			return false
		}
		var requirement: SecRequirement?
		guard SecRequirementCreateWithString("anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"" as CFString, [], &requirement) == errSecSuccess, let requirement else {
			return false
		}
		return SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode), requirement) == errSecSuccess
	}

	private static func alert(_ messageText: String, _ informativeText: String, buttons: [String]) -> NSApplication.ModalResponse {
		return MainActor.assumeIsolated { runAlert(messageText, informativeText, buttons: buttons) }
	}

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

		// Before the crash marker below, so a plug-in that could never load is not
		// mistaken for one that crashed while loading.
		guard Self.plugInIsLoadable(atPath: aPath) else {
			NSLog("Skip plug-in not signed by this application's developer: %@, path %@", name ?? identifier, aPath)
			return
		}

		let crashedDuringPlugInLoad = TMPlugInSupport.crashMarkerPath(forIdentifier: identifier)
		if access(crashedDuringPlugInLoad, F_OK) == 0 {
			let choice = Self.alert("Move “\(name ?? identifier)” plug-in to Trash?", "Previous attempt of loading the plug-in caused abnormal exit. Would you like to move it to trash?", buttons: ["Move to Trash", "Cancel", "Skip Loading"])
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
			_ = Self.alert("Cannot Install Plug-in", "The \(plugInName) plug-in is not compatible with this version of TextMate.", buttons: ["Continue"])
			return
		}

		let blacklist = UserDefaults.standard.stringArray(forKey: TMPlugInController.kUserDefaultsDisabledPlugInsKey)
		if let identifier = plugInBundle?.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String, blacklist?.contains(identifier) == true {
			_ = Self.alert("Cannot Install Plug-in", "The \(plugInName) plug-in should not be used with this version of TextMate because of stability problems.", buttons: ["Continue"])
			return
		}

		// Refused here rather than installed and then silently skipped at launch:
		// copying it and asking for a relaunch would promise something the system
		// will not allow.
		if !Self.plugInIsLoadable(atPath: src) {
			_ = Self.alert("Cannot Install Plug-in", "“\(plugInName)” is not signed by the developer of TextMate-NG, so this version cannot load it.\n\nTextMate-NG only loads plug-ins signed by its own developer. Any program on your Mac can place a plug-in where TextMate-NG would load it, so allowing others would let that program run inside the editor.", buttons: ["Continue"])
			return
		}

		if fm.fileExists(atPath: dst!) {
			let newVersion = (plugInBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? (plugInBundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
			let oldVersion = (Bundle(path: dst!)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? (Bundle(path: dst!)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String)

			let choice = Self.alert("Plug-in Already Installed", "Version \(oldVersion ?? "???") of “\(plugInName)” is already installed.\nDo you want to replace it with version \(newVersion ?? "???")?\n\nUpgrading a plug-in will require TextMate to be relaunched.", buttons: ["Replace", "Cancel"])
			if choice == .alertFirstButtonReturn { // "Replace"
				do {
					try fm.removeItem(atPath: dst!)
				} catch {
					_ = Self.alert("Install Failed", "Couldn't remove old plug-in (“\((dst! as NSString).abbreviatingWithTildeInPath)”)", buttons: ["Continue"])
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
			_ = Self.alert("Install Failed", "It was not possible to create the plug-in folder (“\((dstDir as NSString).abbreviatingWithTildeInPath)”)", buttons: ["Continue"])
			return
		}

		do {
			try fm.copyItem(atPath: src, toPath: dst)
		} catch {
			_ = Self.alert("Install Failed", "The plug-in has not been installed.", buttons: ["Continue"])
			return
		}

		if Self.alert("Plug-in Installed", "To activate “\(plugInName)” you will need to relaunch TextMate.", buttons: ["Relaunch", "Cancel"]) == .alertFirstButtonReturn { // "Relaunch"
			TMPlugInSupport.relaunchApplication()
		}
	}
}
