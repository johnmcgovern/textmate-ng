import AppKit

// Ported from OakOpenWithMenu.mm. No boundary file: the ObjC++ had no C++ types
// at all, only a range-for over an NSArray and a default argument on a static
// helper.
//
// Every @objc name below is spelled out, and that is rule 4 rather than
// pedantry. Three of these properties are declared with custom getters *and*
// used as KVC sort keys, so `defaultApplication` (the key) and
// `isDefaultApplication` (the getter) both have to exist. Swift generates
// neither pair by default, and the failure is an NSSortDescriptor throwing at
// runtime.

// -[NSURL filePathURL] has no Swift URL equivalent, and the ObjC++ leaned on it
// to turn a file-reference URL into a path one. The `?? url.path` fallback is
// new: the ObjC++ would have passed nil onwards, which Swift cannot express.
private func filePath(of url: URL) -> String {
	(url as NSURL).filePathURL?.path ?? url.path
}

@objc(OakOpenWithApplicationInfo)
class OakOpenWithApplicationInfo: NSObject {
	@objc(URL) private(set) var applicationURL: URL
	@objc private(set) var bundleIdentifier: String?
	@objc private(set) var name: String
	@objc private(set) var version: String

	private var _defaultApplication = false
	private var _multipleVersions   = false
	private var _multipleCopies     = false

	// Per-accessor @objc(…), so the KVC key stays `defaultApplication` while the
	// getter stays `isDefaultApplication`.
	@objc var defaultApplication: Bool {
		@objc(isDefaultApplication) get { _defaultApplication }
		@objc(setDefaultApplication:) set { _defaultApplication = newValue }
	}

	@objc var multipleVersions: Bool {
		@objc(hasMultipleVersions) get { _multipleVersions }
		@objc(setMultipleVersions:) set { _multipleVersions = newValue }
	}

	@objc var multipleCopies: Bool {
		@objc(hasMultipleCopies) get { _multipleCopies }
		@objc(setMultipleCopies:) set { _multipleCopies = newValue }
	}

	@objc(initWithBundleURL:)
	init?(bundleURL url: URL) {
		// nil rather than a half-built object: -applications relies on this to skip
		// URLs it cannot describe.
		guard let bundle = Bundle(url: url) else {
			return nil
		}

		applicationURL   = url
		bundleIdentifier = bundle.bundleIdentifier
		name             = FileManager.default.displayName(atPath: filePath(of: url))
		version          = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
		                ?? (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
		                ?? "???"
		super.init()
	}

	// Four branches in a fixed order, and the three flags are independent rather
	// than a ladder: multipleVersions alone appends the directory with no version
	// in front of it.
	@objc var displayName: String {
		var name = self.name

		if multipleCopies {
			name += " (\(version))"
		}
		if defaultApplication {
			name += " (default)"
		}
		if multipleVersions {
			let directory = (filePath(of: applicationURL) as NSString).deletingLastPathComponent
			name += " — \((directory as NSString).abbreviatingWithTildeInPath)"
		}

		return name
	}
}

// Two file URLs for the same application can differ in their trailing slash, so
// everything is compared through this. The ObjC++ spelled the default argument
// out as `BOOL isDirectoryFlag = YES`; nothing ever passed NO.
private func canonicalURL(_ url: URL?, isDirectory: Bool = true) -> URL? {
	guard let url else {
		return nil
	}
	// The original URL when there is no file path, exactly as CanonicalURL did.
	guard let path = (url as NSURL).filePathURL?.path else {
		return url
	}
	return URL(fileURLWithPath: path, isDirectory: isDirectory)
}

@objc(OakOpenWithMenuDelegate)
class OakOpenWithMenuDelegate: NSObject, @preconcurrency NSMenuDelegate {
	@objc private(set) var documentURLs: [URL]
	private var _applications: [OakOpenWithApplicationInfo]?

	@objc(initWithDocumentURLs:)
	init(documentURLs: [URL]) {
		self.documentURLs = documentURLs
		super.init()
	}

	@objc var applications: [OakOpenWithApplicationInfo] {
		if let _applications {
			return _applications
		}

		// The *intersection* across all the documents, not the union: an
		// application only appears if it can open every one of them.
		var allAppURLs: Set<URL>?
		var defaultAppURLs = Set<URL>()

		for documentURL in documentURLs {
			var appURLs = Set<URL>()
			let appURLsArray = LSCopyApplicationURLsForURL(documentURL as CFURL, .all)?.takeRetainedValue() as? [URL] ?? []
			for appURL in appURLsArray {
				if let canonical = canonicalURL(appURL) {
					appURLs.insert(canonical)
				}
			}

			if let defaultAppURL = canonicalURL(NSWorkspace.shared.urlForApplication(toOpen: documentURL)) {
				appURLs.insert(defaultAppURL)
				defaultAppURLs.insert(defaultAppURL)
			}

			if allAppURLs != nil {
				allAppURLs!.formIntersection(appURLs)
			}
			else {
				allAppURLs = appURLs
			}
		}

		var apps: [OakOpenWithApplicationInfo] = []
		let counts = NSCountedSet(capacity: (allAppURLs?.count ?? 0) * 2)

		for appURL in allAppURLs ?? [] {
			guard let app = OakOpenWithApplicationInfo(bundleURL: appURL) else {
				continue
			}

			// Only marked default when *one* application is default across every
			// document — two documents preferring different applications means
			// neither gets the badge.
			app.defaultApplication = defaultAppURLs.count == 1 && defaultAppURLs.contains(appURL)
			apps.append(app)

			counts.add(app.name)
			counts.add("\(app.name) (\(app.version))")
		}

		for app in apps {
			let nameWithVersion = "\(app.name) (\(app.version))"
			app.multipleVersions = counts.count(for: nameWithVersion) > 1
			app.multipleCopies   = counts.count(for: app.name) > counts.count(for: nameWithVersion)
		}

		let sorted = (apps as NSArray).sortedArray(using: [
			NSSortDescriptor(key: "defaultApplication", ascending: false),
			NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedCompare(_:))),
			NSSortDescriptor(key: "version", ascending: false),
		]) as? [OakOpenWithApplicationInfo] ?? apps

		_applications = sorted
		return sorted
	}

	@objc(openDocumentURLs:withApplicationURL:)
	func openDocumentURLs(_ documentURLs: [URL], withApplicationURL applicationURL: URL) {
		// Since we can have multiple applications for the same bundle identifier, e.g. Xcode release and beta, we must open by URL.
		// Unfortunately the API that is URL-based does not allow opening multiple documents at once, so we use AppleScript.

		let listDesc = NSAppleEventDescriptor.list()
		var nextIndex = 1

		for url in documentURLs {
			if let urlData = url.absoluteString.data(using: .utf8),
			   let urlDesc = NSAppleEventDescriptor(descriptorType: typeFileURL, data: urlData) {
				listDesc.insert(urlDesc, at: nextIndex)
				nextIndex += 1
			}
		}

		let odocEvent = NSAppleEventDescriptor.appleEvent(withEventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenDocuments), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
		odocEvent.setParam(listDesc, forKeyword: keyDirectObject)

		let launchOptions: [NSWorkspace.LaunchConfigurationKey: Any] = [.appleEvent: odocEvent]

		// Deliberately the deprecated, *synchronous* call, warning and all.
		// -openApplication:configuration:completionHandler: is the modern spelling
		// and reports its failure asynchronously, which is a change in behaviour
		// dressed as a cleanup — not something this port is making.
		do {
			try NSWorkspace.shared.launchApplication(at: applicationURL, options: [], configuration: launchOptions)
		}
		catch let err {
			NSLog("%@: %@", applicationURL as NSURL, err.localizedDescription)
		}
	}

	// MARK: - MenuItem Action Method

	@objc func openWith(_ sender: Any?) {
		guard let applicationURL = (sender as? NSMenuItem)?.representedObject as? URL else {
			return
		}
		openDocumentURLs(documentURLs, withApplicationURL: applicationURL)
	}

	// MARK: - NSMenuDelegate Methods

	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()

		let apps = applications
		if apps.isEmpty {
			menu.addItem(withTitle: "No Suitable Applications Found", action: Selector(("nop:")), keyEquivalent: "")
		}
		else {
			var didInsertDefaultItems = false
			for app in apps {
				// One separator, at the boundary between the default application and
				// the rest — not between every group.
				if didInsertDefaultItems && !app.defaultApplication {
					menu.addItem(.separator())
				}
				didInsertDefaultItems = app.defaultApplication

				let menuItem = menu.addItem(withTitle: app.displayName, action: #selector(openWith(_:)), keyEquivalent: "")
				menuItem.target            = self
				menuItem.representedObject = app.applicationURL
				menuItem.toolTip           = (filePath(of: app.applicationURL) as NSString).abbreviatingWithTildeInPath

				var image: NSImage?
				if let values = try? app.applicationURL.resourceValues(forKeys: [.effectiveIconKey]), let icon = values.effectiveIcon as? NSImage {
					image = icon
				}
				else {
					image = NSWorkspace.shared.icon(forFile: filePath(of: app.applicationURL))
				}

				if let image = image?.copy() as? NSImage {
					image.size = NSSize(width: 16, height: 16)
					menuItem.image = image
				}
			}
		}
	}

	// Returning false is what keeps the Open With submenu from being walked on
	// every key press. It is a performance guarantee, and dropping it is invisible
	// until a menu with many applications makes typing stutter.
	func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>, action: UnsafeMutablePointer<Selector?>) -> Bool {
		return false
	}
}
