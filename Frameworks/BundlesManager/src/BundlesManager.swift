import AppKit
import os.log

// Ported from BundlesManager.mm — the bundle index: fetching the remote index,
// reading the local one and the Bundles directory into TMBundle objects,
// installing and uninstalling, and keeping the in-process bundle index built
// and watched. Pinned by t_bundles_manager.mm, written first.
//
// BundlesManager.h stays as the hand-written declaration (rule 23): the ObjC++
// consumers import it unchanged, and so do four bridging headers, which it can
// enter now that its one C++ method lives in BundlesManagerCxx.h.
//
// The C++ is behind two ObjC faces the previous commit made: BundlesIndexCache
// (the plist cache, the FSEvents callback, the index build) and
// BundlesManagerSupport (the one-liners). -findBundleForInstall: is a category
// in BundlesManagerCxx.mm and does not move (rule 37).
//
// Not @MainActor, for the reason SoftwareUpdate is not: the scheduler block
// runs on NSBackgroundActivityScheduler's queue and the download completions on
// the download manager's, and the ObjC++ crossed back to the main thread with
// dispatch_async where it needed to. Those crossings are kept as they were,
// with nonisolated(unsafe) stating what the ObjC++ did implicitly. What must be
// on the main thread — the Avian alert, and the index build that registers the
// FSEvents stream on the current run loop — is reached from -loadBundlesIndex,
// which AppController calls at launch.

private let log = Logger()

private let kDefaultPollInterval: TimeInterval = 3*60*60

private func SafeBasename(_ name: String?) -> String? {
	return name?.replacingOccurrences(of: "/", with: ":").replacingOccurrences(of: ".", with: "_")
}

@objc(BundlesManager)
class BundlesManager: NSObject, OakUserDefaultsObserver {
	// nonisolated(unsafe) for the same reason as SoftwareUpdate's: this is not a
	// MainActor object, and the ObjC++ was a plain function-local static.
	@objc nonisolated(unsafe) static let sharedInstance = BundlesManager()

	private var updateBundleIndexScheduler: NSBackgroundActivityScheduler?

	// The C++ model layer, behind an ObjC face (rule 25). nil until
	// -loadBundlesIndex, and every use is nil-tolerant, which is what an empty
	// plist::cache_t answered before.
	private var indexCache: BundlesIndexCache?

	private var autoUpdateBundles = false

	private var needsCreateBundlesIndexStorage = false
	private var needsSaveBundlesIndexStorage = false

	private var bundlesStorage: [TMBundle]?

	private let installDirectory: String
	private let localIndexPath: String
	private let remoteIndexPath: String
	private let remoteIndexURL: URL

	@objc override init() {
		let applicationSupport = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first ?? ""
		installDirectory = (applicationSupport as NSString).appendingPathComponent("TextMate/Managed")
		localIndexPath   = (installDirectory as NSString).appendingPathComponent("LocalIndex.plist")
		remoteIndexPath  = (installDirectory as NSString).appendingPathComponent("Cache/org.textmate.updates.default")
		remoteIndexURL   = BundlesManagerSupport.remoteIndexURL()
		super.init()

		userDefaultsDidChange(nil)
		OakObserveUserDefaults(self)

		// The shared instance is first touched from AppController at launch, and
		// the tests build theirs on the main thread; assumeIsolated says so.
		let application = MainActor.assumeIsolated { NSApp }
		NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate(_:)), name: NSApplication.willTerminateNotification, object: application)
	}

	@objc func userDefaultsDidChange(_ aNotification: Notification!) {
		setAutoUpdateBundles(!UserDefaults.standard.bool(forKey: kUserDefaultsDisableBundleUpdatesKey))
	}

	@objc private func applicationWillTerminate(_ aNotification: Notification) {
		if needsSaveBundlesIndex {
			saveBundlesIndex(self)
		}
	}

	private func setAutoUpdateBundles(_ flag: Bool) {
		if autoUpdateBundles == flag {
			return
		}

		updateBundleIndexScheduler?.invalidate()
		updateBundleIndexScheduler = nil

		autoUpdateBundles = flag
		if autoUpdateBundles {
			var updateFrequency = TimeInterval(UserDefaults.standard.float(forKey: kUserDefaultsBundleUpdateFrequencyKey))
			if updateFrequency == 0 {
				updateFrequency = kDefaultPollInterval
			}

			let scheduler = NSBackgroundActivityScheduler(identifier: "\(Bundle.main.bundleIdentifier ?? "").UpdateBundleIndex")
			scheduler.interval = updateFrequency
			scheduler.repeats  = true
			// The block runs on the scheduler's queue; nonisolated(unsafe) states the
			// crossing the ObjC++ made implicitly (rule 26).
			nonisolated(unsafe) let unsafeSelf = self
			scheduler.schedule { completionHandler in
				BundlesManagerSupport.runInUpdateBundleIndexActivity {
					unsafeSelf.tryUpdateBundleIndex { wasUpdated in
						log.log("Newer bundle index retrieved: \(wasUpdated ? "YES" : "NO", privacy: .public)")
						completionHandler(.finished)
					}
				}
			}
			updateBundleIndexScheduler = scheduler
		}
	}

	private func tryUpdateBundleIndex(andCallback completionHandler: @escaping (Bool) -> Void) {
		// The completion runs on the download session's delegate queue, which
		// OakDownloadManager creates as the main queue (measured, concurrency audit
		// 2026-09-16), and then hops to the main queue with dispatch_async as the
		// ObjC++ did — a hop from main to main, kept for the ordering it gives.
		// nonisolated(unsafe) states the crossing the compiler cannot see.
		nonisolated(unsafe) let unsafeSelf = self
		nonisolated(unsafe) let unsafeHandler = completionHandler
		OakDownloadManager.sharedInstance.downloadFile(at: remoteIndexURL, replacingFileAt: URL(fileURLWithPath: remoteIndexPath), publicKeys: publicKeys) { wasUpdated, error in
			BundlesManagerSupport.recordIndexCheck(atPath: unsafeSelf.remoteIndexPath)
			if error == nil {
				UserDefaults.standard.set(Date(), forKey: kUserDefaultsLastBundleUpdateCheckKey)
			}
			if wasUpdated {
				log.log("Bundle index updated: \(unsafeSelf.remoteIndexPath, privacy: .public)")

				DispatchQueue.main.async {
					let newBundles = unsafeSelf.bundlesByLoadingIndex()
					let oldRecommendations = NSSet(array: ((unsafeSelf.bundles ?? []) as NSArray).filtered(using: NSPredicate(format: "isRecommended == YES")))
					unsafeSelf.bundles = newBundles
					let bundlesToUpdate = (newBundles as NSArray).filtered(using: NSPredicate(format: "(hasUpdate == YES AND isCompatible == YES) OR (isInstalled == NO AND (isMandatory == YES OR (isRecommended == YES AND isCompatible == YES AND NOT (SELF IN %@))))", oldRecommendations)) as? [TMBundle] ?? []
					unsafeSelf.installBundles(bundlesToUpdate) { updatedBundles in
						for bundle in updatedBundles ?? [] {
							log.log("\(bundle.name ?? "", privacy: .public) bundle updated: \(bundle.path ?? "", privacy: .public)")
						}
						unsafeHandler(wasUpdated)
					}
				}
			}
			else {
				if let error {
					log.error("Failed to update bundle index: \(error.localizedDescription, privacy: .public)")
				}
				unsafeHandler(wasUpdated)
			}
		}
	}

	@objc(installBundleItemsAtPaths:)
	func installBundleItems(atPaths somePaths: [Any]) {
		BundlesManagerSupport.installBundleItems(atPaths: somePaths)
	}

	@objc(installBundles:completionHandler:)
	@discardableResult
	func installBundles(_ someBundles: [TMBundle]?, completionHandler callback: @escaping ([TMBundle]?) -> Void) -> Progress? {
		let bundlesToInstall = NSMutableSet()

		let queue = NSMutableArray(array: someBundles ?? [])
		while let bundle = queue.lastObject as? TMBundle {
			bundlesToInstall.add(bundle)
			let dependencies = ((bundle.dependencies ?? []) as NSArray).filtered(using: NSPredicate(format: "isInstalled == NO AND NOT (SELF IN %@)", bundlesToInstall))
			for case let dependency as TMBundle in dependencies {
				dependency.dependency = true
			}
			queue.replaceObjects(in: NSRange(location: queue.count-1, length: 1), withObjectsFrom: dependencies)
		}

		if bundlesToInstall.count == 0 {
			callback(nil)
			return nil
		}

		let bundlesDirectory = (installDirectory as NSString).appendingPathComponent("Bundles")
		do {
			try FileManager.default.createDirectory(atPath: bundlesDirectory, withIntermediateDirectories: true)
		}
		catch {
			log.error("Failed to create directory \(bundlesDirectory, privacy: .public): \(error.localizedDescription, privacy: .public)")
			callback(nil)
			return nil
		}

		let group = DispatchGroup()
		let bundles = bundlesToInstall.allObjects.compactMap { $0 as? TMBundle }
		let progress = Progress.discreteProgress(totalUnitCount: Int64(bundles.count))

		// Was a std::vector<std::string> sized to the bundles, NULL_STR meaning "not
		// installed"; NSNull plays that part now. Written from the download
		// completions and read after the group empties. Both happen on the main
		// queue — the session's delegate queue is main — so the writes never race;
		// nonisolated(unsafe) states what the compiler cannot see.
		nonisolated(unsafe) let res = NSMutableArray(array: Array(repeating: NSNull(), count: bundles.count))

		for i in 0..<bundles.count {
			group.enter()

			let bundle = bundles[i]
			let defaultPath = ((bundlesDirectory as NSString).appendingPathComponent(SafeBasename(bundle.name) ?? "") as NSString).appendingPathExtension("tmbundle") ?? ""
			let destURL = URL(fileURLWithPath: bundle.path ?? defaultPath, isDirectory: true)
			log.log("Download \(bundle.downloadURL?.absoluteString ?? "", privacy: .public) as \(destURL.path, privacy: .public)")

			// The header declares the server URL nonnull; the ObjC++ handed over
			// whatever the bundle had. A bundle in this list always came from the
			// remote index and has one; if it somehow did not, that is the download
			// failing rather than a trap.
			guard let downloadURL = bundle.downloadURL else {
				log.error("Failed to download \(bundle.name ?? "", privacy: .public): no download URL")
				group.leave()
				continue
			}

			progress.becomeCurrent(withPendingUnitCount: 1)
			_ = OakDownloadManager.sharedInstance.downloadArchive(at: downloadURL, forReplacing: destURL, publicKeys: publicKeys) { extractedArchiveURL, error in
				if let extractedArchiveURL {
					do {
						_ = try FileManager.default.replaceItemAt(destURL, withItemAt: extractedArchiveURL, backupItemName: nil, options: .usingNewMetadataOnly)
						res[i] = String(cString: (destURL as NSURL).fileSystemRepresentation)
						log.log("Updated \(destURL.path, privacy: .public)")
					}
					catch {
						log.error("Failed to update \(destURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
					}
				}
				else {
					log.error("Failed to download \(downloadURL.absoluteString, privacy: .public): \(error?.localizedDescription ?? "", privacy: .public)")
				}
				group.leave()
			}
			progress.resignCurrent()
		}

		nonisolated(unsafe) let unsafeSelf = self
		nonisolated(unsafe) let unsafeBundles = bundles
		nonisolated(unsafe) let unsafeCallback = callback
		group.notify(queue: .main) {
			for i in 0..<unsafeBundles.count {
				guard let path = res[i] as? String else {
					continue
				}

				let bundle = unsafeBundles[i]
				bundle.installed   = true
				bundle.path        = path
				bundle.lastUpdated = bundle.downloadLastUpdated

				BundlesManagerSupport.setUpdatedDate(bundle.downloadLastUpdated, forBundleAtPath: path)
				unsafeSelf.reloadPath(path, recursive: true)
			}

			unsafeSelf.createBundlesIndex(unsafeSelf)
			unsafeSelf.saveLocalIndex()

			unsafeCallback(unsafeBundles)
		}
		return progress
	}

	@objc(uninstallBundle:)
	func uninstallBundle(_ bundle: TMBundle) {
		bundle.installed = false
		guard let path = bundle.path, (try? FileManager.default.removeItem(atPath: path)) != nil else {
			return
		}

		erasePath(path)

		bundle.path        = nil
		bundle.lastUpdated = nil

		// TODO Remove bundle’s dependencies

		saveLocalIndex()
	}

	// MARK: - Creating Bundle Index and Handling FSEvents

	@objc private func createBundlesIndex(_ sender: Any?) {
		if needsCreateBundlesIndexStorage == false {
			return
		}
		needsCreateBundlesIndexStorage = false

		indexCache?.createIndex()
	}

	@objc private func saveBundlesIndex(_ sender: Any?) {
		indexCache?.save()
		needsSaveBundlesIndexStorage = false
	}

	// Each setter schedules its work once, on the transition to true, which is
	// what `if(_flag != newFlag && (_flag = newFlag))` did.
	private var needsCreateBundlesIndex: Bool {
		get { needsCreateBundlesIndexStorage }
		set {
			if needsCreateBundlesIndexStorage != newValue {
				needsCreateBundlesIndexStorage = newValue
				if newValue {
					perform(#selector(createBundlesIndex(_:)), with: self, afterDelay: 0)
				}
			}
		}
	}

	private var needsSaveBundlesIndex: Bool {
		get { needsSaveBundlesIndexStorage }
		set {
			if needsSaveBundlesIndexStorage != newValue {
				needsSaveBundlesIndexStorage = newValue
				if newValue {
					perform(#selector(saveBundlesIndex(_:)), with: self, afterDelay: 5)
				}
			}
		}
	}

	private func setEventId(_ anEventId: UInt64, forPath aPath: String) {
		indexCache?.setEventId(anEventId, forPath: aPath)
		needsSaveBundlesIndex = true
	}

	private func erasePath(_ aPath: String) {
		if indexCache?.erasePath(aPath) == true {
			needsCreateBundlesIndex = true
			needsSaveBundlesIndex   = true
		}
	}

	@objc(reloadPath:)
	func reloadPath(_ aPath: String) {
		reloadPath(aPath, recursive: false)
	}

	private func reloadPath(_ aPath: String, recursive flag: Bool) {
		if indexCache?.reloadPath(aPath, recursive: flag) == true {
			needsCreateBundlesIndex = true
			needsSaveBundlesIndex   = true
		}
	}

	@MainActor
	private func moveAvianBundles() {
		let fm = FileManager.default

		var moves: [[String]] = []
		var moveDescription = ""

		for path in NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, [.userDomainMask, .localDomainMask], true) {
			for dir in [ "", "Pristine Copy" ] {
				let textMateFolder = NSString.path(withComponents: [ path, "TextMate", dir ])
				let avianFolder    = NSString.path(withComponents: [ path, "Avian", dir ])
				let src = (avianFolder as NSString).appendingPathComponent("Bundles")
				let dst = (textMateFolder as NSString).appendingPathComponent("Bundles")

				if fm.fileExists(atPath: src) == false {
					continue
				}

				if fm.fileExists(atPath: dst) == true {
					moves.append([ dst, dst + "-1.x" ])
					moveDescription += "Rename “Bundles” at “\((textMateFolder as NSString).abbreviatingWithTildeInPath)” to “Bundles-1.x” (backup).\n"
				}

				moves.append([ src, dst ])
				moveDescription += "Move “Bundles” at “\((avianFolder as NSString).abbreviatingWithTildeInPath)” to “\((textMateFolder as NSString).abbreviatingWithTildeInPath)”.\n"
			}
		}

		if moves.isEmpty {
			return
		}

		let alert = NSAlert()
		alert.alertStyle      = .informational
		alert.messageText     = "Move Bundles?"
		alert.informativeText = "Bundles are no longer read from the “Avian” folder. Would you like to move the following items:\n\n\(moveDescription)"
		alert.addButton(withTitle: "Move Bundles")
		alert.addButton(withTitle: "Cancel")
		if alert.runModal() != .alertFirstButtonReturn {
			return
		}

		for move in moves {
			let dstFolder = (move[1] as NSString).deletingLastPathComponent
			do {
				if !fm.fileExists(atPath: dstFolder) {
					try fm.createDirectory(atPath: dstFolder, withIntermediateDirectories: true)
				}
				try fm.moveItem(atPath: move[0], toPath: move[1])
			}
			catch {
				NSAlert(error: error).runModal()
				break
			}
		}
	}

	@objc @MainActor
	func loadBundlesIndex() {
		// LEGACY locations used by 2.0-beta.12.22 and earlier
		moveAvianBundles()

		let cache = BundlesIndexCache()

		// What the fs::event_callback_t did, which was to message the shared
		// instance. `self` is that instance; weak keeps the cache from owning its
		// owner.
		cache.pathDidChange = { [weak self] path, observedPath, eventId, recursive in
			self?.reloadPath(path, recursive: recursive)
			self?.setEventId(eventId, forPath: observedPath)
		}
		cache.replayingHistoryDidChange = { [weak self] _, observedPath, eventId in
			self?.setEventId(eventId, forPath: observedPath)
		}
		indexCache = cache

		needsCreateBundlesIndexStorage = true
		createBundlesIndex(self)
	}

	// MARK: - The index files

	private static func bundlesFromIndex(remoteIndexPath: String, localIndexPath: String, installDir: String, cache: [UUID: TMBundle]?) -> [TMBundle] {
		var res: [UUID: TMBundle] = [:]

		// =====================
		// = Load Remote Index =
		// =====================

		var dependencies: [UUID: [[String: Any]]] = [:]
		var bundlesByScope: [String: TMBundle] = [:]

		for item in NSDictionary(contentsOfFile: remoteIndexPath)?["bundles"] as? [[String: Any]] ?? [] {
			// An entry without a parsable UUID was an exception (nil dictionary key);
			// it is skipped now.
			guard let identifier = (item["uuid"] as? String).flatMap({ UUID(uuidString: $0) }) else {
				continue
			}
			let bundle = cache?[identifier] ?? TMBundle(identifier: identifier)

			bundle.name              = item["name"] as? String
			bundle.minimumAppVersion = item["requires"] as? String
			bundle.category          = item["category"] as? String
			bundle.htmlURL           = (item["html_url"] as? String).flatMap { URL(string: $0) }
			bundle.contactName       = item["contactName"] as? String
			bundle.contactEmail      = BundlesManagerSupport.rot13(item["contactEmailRot13"] as? String)
			bundle.summary           = item["description"] as? String
			bundle.recommended       = (item["isDefault"] as? Bool) ?? false
			bundle.mandatory         = (item["isMandatory"] as? Bool) ?? false

			let version = (item["versions"] as? [[String: Any]])?.first
			bundle.downloadURL         = (version?["url"] as? String).flatMap { URL(string: $0) }
			bundle.downloadLastUpdated = version?["updated"] as? Date
			bundle.downloadSize        = (version?["size"] as? NSNumber)?.intValue ?? 0

			var grammars: [BundleGrammar] = []
			for info in item["grammars"] as? [[String: Any]] ?? [] {
				let grammar = BundleGrammar()
				grammar.bundle         = bundle
				grammar.name           = info["name"] as? String
				grammar.identifier     = (info["uuid"] as? String).flatMap { UUID(uuidString: $0) }
				grammar.fileType       = info["scope"] as? String
				grammar.firstLineMatch = info["firstLineMatch"] as? String
				grammar.filePatterns   = info["fileTypes"] as? [String]
				grammars.append(grammar)

				if let fileType = grammar.fileType {
					bundlesByScope[fileType] = bundle
				}
			}
			bundle.grammars = grammars
			res[identifier] = bundle

			if let deps = item["dependencies"] as? [[String: Any]], !deps.isEmpty {
				dependencies[identifier] = deps
			}
		}

		// ======================
		// = Setup Dependencies =
		// ======================

		for (uuid, infos) in dependencies {
			guard let bundle = res[uuid] else {
				continue
			}

			var array: [TMBundle] = []
			for info in infos {
				if let scope = info["grammar"] as? String {
					if let otherBundle = bundlesByScope[scope] {
						array.append(otherBundle)
					}
					else {
						NSLog("%@: No bundle provides ‘%@’.", bundle.name ?? "(null)", scope)
					}
				}
				else if let uuidString = info["uuid"] as? String {
					if let otherBundle = UUID(uuidString: uuidString).flatMap({ res[$0] }) {
						array.append(otherBundle)
					}
					else {
						NSLog("%@: Required bundle not found ‘%@’ (%@).", bundle.name ?? "(null)", info["name"] as? String ?? "(null)", uuidString)
					}
				}
			}

			bundle.dependencies = array
		}

		// ====================
		// = Load Local Index =
		// ====================

		for item in NSDictionary(contentsOfFile: localIndexPath)?["bundles"] as? [[String: Any]] ?? [] {
			guard let identifier = (item["uuid"] as? String).flatMap({ UUID(uuidString: $0) }) else {
				continue
			}
			let bundle = res[identifier] ?? TMBundle(identifier: identifier)

			bundle.installed   = true
			bundle.path        = (installDir as NSString).appendingPathComponent(item["path"] as? String ?? "")
			bundle.category    = item["category"] as? String ?? bundle.category ?? "Discontinued"
			bundle.lastUpdated = item["updated"] as? Date
			bundle.dependency  = (item["isDependency"] as? Bool) ?? false

			res[identifier] = bundle
		}

		// ========================
		// = Load Bundles on Disk =
		// ========================

		var bundlesByPath: [String: TMBundle] = [:]
		for bundle in res.values {
			if let path = bundle.path {
				bundlesByPath[path] = bundle
			}
		}

		let bundlesDir = (installDir as NSString).appendingPathComponent("Bundles")
		for name in BundlesManagerSupport.bundleDirectoryNames(inDirectory: bundlesDir) {
			let bundlePath = (bundlesDir as NSString).appendingPathComponent(name)
			if let bundle = bundlesByPath[bundlePath] {
				bundlesByPath.removeValue(forKey: bundlePath)
				if bundle.downloadURL != nil { // We have category, description etc. from remote index
					continue
				}
			}

			if let info = NSDictionary(contentsOfFile: (bundlePath as NSString).appendingPathComponent("info.plist")) as? [String: Any] {
				guard let identifier = (info["uuid"] as? String).flatMap({ UUID(uuidString: $0) }) else {
					continue
				}
				let bundle = res[identifier] ?? TMBundle(identifier: identifier)

				bundle.installed    = true
				bundle.path         = bundlePath
				bundle.category     = bundle.category     ?? "Orphaned"
				bundle.name         = bundle.name         ?? info["name"] as? String
				bundle.contactName  = bundle.contactName  ?? info["contactName"] as? String
				bundle.contactEmail = bundle.contactEmail ?? BundlesManagerSupport.rot13(info["contactEmailRot13"] as? String)
				bundle.summary      = bundle.summary      ?? info["description"] as? String

				if let updated = BundlesManagerSupport.updatedDate(forBundleAtPath: bundlePath) {
					bundle.lastUpdated = updated
				}

				res[identifier] = bundle

				NSLog("Found: ‘%@’ missing in local index.", bundle.name ?? "(null)")
			}
		}

		for bundle in bundlesByPath.values {
			bundle.installed = false
			NSLog("Missing: ‘%@’ not on disk.", bundle.name ?? "(null)")
		}

		return (Array(res.values) as NSArray).sortedArray(using: [ NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedCompare(_:))) ]) as? [TMBundle] ?? []
	}

	// The tests' way in to the parser, declared for them in
	// tests/BundlesManagerTesting.h. A class method rather than a free function
	// because a Swift free function has no ObjC symbol (rule 19).
	@objc(bundlesFromRemoteIndexAtPath:localIndexPath:installDirectory:previousBundles:)
	static func bundles(fromRemoteIndexAtPath remoteIndexPath: String, localIndexPath: String, installDirectory installDir: String, previousBundles cache: [UUID: TMBundle]?) -> [TMBundle] {
		return bundlesFromIndex(remoteIndexPath: remoteIndexPath, localIndexPath: localIndexPath, installDir: installDir, cache: cache)
	}

	private var publicKeys: [String: String] {
		var res: [String: String] = [:]

		let dummy = Progress.discreteProgress(totalUnitCount: 1)
		dummy.becomeCurrent(withPendingUnitCount: 1)
		for key in NSDictionary(contentsOfFile: remoteIndexPath)?["keys"] as? [[String: Any]] ?? [] {
			if let identity = key["identity"] as? String, let publicKey = key["publicKey"] as? String {
				res[identity] = publicKey
			}
		}
		dummy.resignCurrent()

		if !res.isEmpty {
			return res
		}

		return [
			"org.textmate.duff":    "-----BEGIN PUBLIC KEY-----\nMIIBtjCCASsGByqGSM44BAEwggEeAoGBAPIE9PpXPK3y2eBDJ0dnR/D8xR1TiT9m\n8DnPXYqkxwlqmjSShmJEmxYycnbliv2JpojYF4ikBUPJPuerlZfOvUBC99ERAgz7\nN1HYHfzFIxVo1oTKWurFJ1OOOsfg8AQDBDHnKpS1VnwVoDuvO05gK8jjQs9E5LcH\ne/opThzSrI7/AhUAy02E9H7EOwRyRNLofdtPxpa10o0CgYBKDfcBscidAoH4pkHR\nIOEGTCYl3G2Pd1yrblCp0nCCUEBCnvmrWVSXUTVa2/AyOZUTN9uZSC/Kq9XYgqwj\nhgzqa8h/a8yD+ao4q8WovwGeb6Iso3WlPl8waz6EAPR/nlUTnJ4jzr9t6iSH9owS\nvAmWrgeboia0CI2AH++liCDvigOBhAACgYAFWO66xFvmF2tVIB+4E7CwhrSi2uIk\ndeBrpmNcZZ+AVFy1RXJelNe/cZ1aXBYskn/57xigklpkfHR6DGqpEbm6KC/47Jfy\ny5GEx+F/eBWEePi90XnLinytjmXRmS2FNqX6D15XNG1xJfjociA8bzC7s4gfeTUd\nlpQkBq2z71yitA==\n-----END PUBLIC KEY-----\n",
			"org.textmate.msheets": "-----BEGIN PUBLIC KEY-----\nMIIDOzCCAi4GByqGSM44BAEwggIhAoIBAQDfYsqBc18uL7yYb/bDrrEtVTBG8tML\nmMtNFyU8XhlVKWdQJwBGG/fV2Wjc0hVYSeTWv3VueITZbuuVZEePXlem6Dki1DEL\nsMNeDvE/l0MKHXi1+sr1cht7QvuTi/c1UK4I6QNWDJWi7KmqJg3quLCwJfMef1x5\n/qgLUln5cU6+pAj43Vp62bzHJBjAnrC432yD7F4Mxu4oV/PEm5QC6pU7RcvUwAox\np7m7c8+CxX7Aq4dH6Jd8Jt6XuYIktlfcFivvvF60CvxhABDBdGMra4roO0wlJmID\n91oQ3PLxFBsDmbluPJlkmTp4YetsF8/Zd9P3WwBQUArtNdiqKZIQ4uHXAhUAvNZ5\ntZkzuUiblIxZKmOCBN/JeMsCggEBAK9jUiC98+hwY5XcDQjDSLPE4uvv+dHZ29Bx\n8KevX+qzd6shIhp6urvyBXrM+h8l7iB6Jh4Wm3WhqKMBjquRqyGogQDGxJr7QBVk\nQSOiyaKDT4Ue/Nhg1MFsrt3PtS1/nscZ6GGWswrCfQ1t4m/wXDasUSfz2smae+Jd\nZ6UGBzWQMRawyU/O/LX0PlJkBOMHopecAUcxHc2G02P2QwAMKPavwksQ4tWCJvIr\n7ZELfCcVQtG2UnpTRWqLZQaVwSYMHoNK9/reu099sdv9CQ+trH2Q5LlBXJmHloFK\nafiuQPjTmaJVf/piiQ79xJB6VmwoEpOJJG4NYNt7f+I7YCk07xwDggEFAAKCAQA5\nSBwWJouMKUI6Hi0EZ4/Yh98qQmItx4uWTYFdjcUVVYCKK7GIuXu67rfkbCJUrvT9\nID1vw2eyTmbuW2TPuRDsxUcB7WRyyLekl67vpUgMgLBLgYMXQf6RF4HM2tW7UWg7\noNQHkZKWbhDgXdumKzKf/qZPB/LT2Yndv/zqkQ+YXIu08j0RGkxJaAjB7nEv1XGq\nL2VJf8aEi+MnihAtMPCHcW34qswqO1kOCbOWNShlfWHGjKlfdsPYv87RcalHNqps\nk1r60kyEkeZvKGM+FDT80N7cafX286v8n9L4IvvnLr/FDOH4XXzEjXB9Vr5Ffvj1\ndxNPRmDZOo6JNKA8Uvki\n-----END PUBLIC KEY-----\n",
		]
	}

	// Lazily loaded, as before, and without a KVO notification for that first
	// load — the getter filled the ivar directly. The Preferences pane binds an
	// NSArrayController's content to this key, which the setter notifies.
	@objc dynamic var bundles: [TMBundle]? {
		get {
			if bundlesStorage == nil {
				bundlesStorage = bundlesByLoadingIndex()
			}
			return bundlesStorage
		}
		set {
			bundlesStorage = newValue
		}
	}

	private func bundlesByLoadingIndex() -> [TMBundle] {
		var previousBundles: [UUID: TMBundle] = [:]
		for bundle in bundlesStorage ?? [] {
			if let identifier = bundle.identifier {
				previousBundles[identifier] = bundle
			}
		}
		return Self.bundlesFromIndex(remoteIndexPath: remoteIndexPath, localIndexPath: localIndexPath, installDir: installDirectory, cache: previousBundles)
	}

	private func saveLocalIndex() {
		guard let all = bundlesStorage else {
			return
		}

		var bundles: [[String: Any]] = []
		for case let bundle as TMBundle in (all as NSArray).filtered(using: NSPredicate(format: "isInstalled == YES AND path != NULL")) {
			var dict: [String: Any] = [
				"uuid": bundle.identifier?.uuidString ?? "",
				"path": (bundle.path ?? "").replacingOccurrences(of: installDirectory + "/", with: ""),
			]

			if let lastUpdated = bundle.lastUpdated {
				dict["updated"] = lastUpdated
			}
			if bundle.isDependency {
				dict["isDependency"] = true
			}
			if let category = bundle.category {
				dict["category"] = category
			}

			bundles.append(dict)
		}

		let plist: NSDictionary = [ "bundles": bundles ]
		plist.write(toFile: localIndexPath, atomically: true)
	}
}
