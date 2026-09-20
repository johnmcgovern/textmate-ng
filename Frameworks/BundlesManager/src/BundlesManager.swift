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

	// Fetch the bundle index, verify its signature, and write the document it
	// carries — nothing else touches disk.
	//
	// This replaced a `downloadFile(…publicKeys:)` that took the signature from
	// `x-amz-meta-x-signee` and `x-amz-meta-x-signature`, because MacroMates
	// served the index from S3 and those headers are how S3 carries object
	// metadata. GitHub cannot set custom response headers on a release asset, so
	// that scheme could not follow the index to a host of this project's own.
	// The signature now travels *inside* the document, in the same wrapper the
	// software updater has used since alpha.24, and is checked by the same code:
	// UpdateManifest.verifiedPayload, against the keys in TMUpdateManifestKeys.
	//
	// The bytes are written only after the signature checks out, so an index
	// that fails verification cannot be read back later as if it had passed.
	static func fetchVerifiedIndex(from url: URL, writingTo path: String, completionHandler: @escaping (Bool, Error?) -> Void) {
		// URLSession's completion is @Sendable and this handler is not, so the
		// capture has to be stated rather than implied (rule 26). Every caller
		// hands over a closure that was already crossing this boundary before,
		// through the download manager; naming it here changes nothing about what
		// runs where, only about what is written down.
		//
		// Swift 6.4, which is what Xcode 27 ships, accepts the capture without
		// this. Xcode 26.6 — what CI pins — rejects it, so a green local build
		// said nothing about a red CI one. That is how alpha.31 was tagged on a
		// commit CI could not build.
		nonisolated(unsafe) let unsafeHandler = completionHandler
		let task = URLSession.shared.dataTask(with: url) { data, response, error in
			if let error {
				unsafeHandler(false, error)
				return
			}
			guard let data, !data.isEmpty else {
				unsafeHandler(false, NSError(domain: "BundlesManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Empty response from the bundle index."]))
				return
			}
			if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
				unsafeHandler(false, NSError(domain: "BundlesManager", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Bundle index returned HTTP \(http.statusCode)."]))
				return
			}

			let payload: Data
			do {
				// TMUpdateManifest, not UpdateManifest: this crosses a module
				// boundary through a hand-written header, so the name here is the
				// @objc one (rule 23).
				payload = try TMUpdateManifest.verifiedPayload(from: data, keys: TMUpdateManifest.embeddedKeys())
			} catch {
				// Worth distinguishing in the log: being served an error page by a
				// proxy looks identical to a bad signature unless the type is named.
				let contentType = (response as? HTTPURLResponse)?.allHeaderFields["Content-Type"] as? String
				log.error("Bundle index failed verification (\(contentType ?? "no content-type", privacy: .public)): \(error.localizedDescription, privacy: .public)")
				unsafeHandler(false, error)
				return
			}

			// Unchanged is not an update. Comparing the verified bytes rather than
			// an ETag keeps this honest about what actually changed, and the index
			// is tens of kilobytes.
			if let existing = try? Data(contentsOf: URL(fileURLWithPath: path)), existing == payload {
				unsafeHandler(false, nil)
				return
			}
			do {
				// On a fresh install nothing has created Cache/ yet, and an atomic
				// write into a directory that does not exist fails with "the folder
				// doesn't exist" — which reads like a missing download rather than a
				// missing directory. The old header-signature path created it on the
				// way past; this has to do the same.
				let destination = URL(fileURLWithPath: path)
				try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
				                                        withIntermediateDirectories: true)
				try payload.write(to: destination, options: .atomic)
				unsafeHandler(true, nil)
			} catch {
				log.error("Could not store the bundle index at \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
				unsafeHandler(false, error)
			}
		}
		task.resume()
	}

	private func tryUpdateBundleIndex(andCallback completionHandler: @escaping (Bool) -> Void) {
		// The completion runs on URLSession.shared's queue — downloadFile uses the
		// shared session, not the manager's main-queue one — and then hops to the
		// main queue with dispatch_async, as the ObjC++ did. Everything before the
		// hop is what the ObjC++ also did off the main thread: a file-date write,
		// a defaults write, a log line. nonisolated(unsafe) states both crossings
		// (concurrency audit, 2026-09-16).
		nonisolated(unsafe) let unsafeSelf = self
		nonisolated(unsafe) let unsafeHandler = completionHandler

		// Snapshot what was recommended **before** the new index is written.
		//
		// `bundles` is lazily loaded, and the getter reads whatever index is on
		// disk at the moment it is first touched. Taken after the download, as it
		// used to be, the very first run loads the *new* index as the "old"
		// recommendations — so every recommended bundle is in the set it is being
		// compared against, `NOT (SELF IN …)` is false for all of them, and a
		// fresh install ends up with only the three mandatory bundles. Measured
		// on 2026-09-19 with an empty Managed directory: 3 installed, 30 skipped.
		//
		// This is not caused by moving off api.textmate.org; the ordering was the
		// same before. It stayed hidden because on any machine that already had
		// bundles, the getter had run at launch and the snapshot was genuinely
		// the previous state.
		nonisolated(unsafe) let oldRecommendations = NSSet(array: ((self.bundles ?? []) as NSArray).filtered(using: NSPredicate(format: "isRecommended == YES")))

		BundlesManager.fetchVerifiedIndex(from: remoteIndexURL, writingTo: remoteIndexPath) { wasUpdated, error in
			BundlesManagerSupport.recordIndexCheck(atPath: unsafeSelf.remoteIndexPath)
			if error == nil {
				UserDefaults.standard.set(Date(), forKey: kUserDefaultsLastBundleUpdateCheckKey)
			}
			// **Evaluated on every check, not only when the index moved.**
			//
			// What to install depends on local state as much as on the index: a
			// bundle can become missing, or stale, or newly eligible, while the
			// index is byte-for-byte what it was. Gating this on `wasUpdated`
			// meant none of that was ever noticed — on 2026-09-20 the fix that
			// makes an unknown install date count as stale did nothing at all,
			// because the index had not changed since the release before and so
			// the decision was never revisited.
			//
			// It costs a predicate over a few dozen bundles when nothing is due,
			// and `installBundles` with an empty list returns immediately.
			if error == nil {
				if wasUpdated {
					log.log("Bundle index updated: \(unsafeSelf.remoteIndexPath, privacy: .public)")
				}

				DispatchQueue.main.async {
					let newBundles = unsafeSelf.bundlesByLoadingIndex()
					unsafeSelf.bundles = newBundles
					let bundlesToUpdate = (newBundles as NSArray).filtered(using: NSPredicate(format: "(hasUpdate == YES AND isCompatible == YES) OR (isInstalled == NO AND (isMandatory == YES OR (isRecommended == YES AND isCompatible == YES AND NOT (SELF IN %@))))", oldRecommendations)) as? [TMBundle] ?? []
					log.log("Bundle index: \(newBundles.count, privacy: .public) listed, \(oldRecommendations.count, privacy: .public) previously recommended, \(bundlesToUpdate.count, privacy: .public) to install")
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
		// installed"; NSNull plays that part now. Written from the archive-download
		// completions and read after the group empties. Both happen on the main
		// queue — the archive task's session has delegateQueue: .main, and its
		// completion is a delegate callback — so the writes never race;
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

			// No digest means an index entry this build cannot verify, and the
			// answer to that is to refuse rather than to fetch it anyway. The
			// only way to reach here is an index that omitted `sha256`, which
			// our own mirror never does — so this is the guard that would catch
			// being pointed at somebody else's index.
			guard let expectedSHA256 = bundle.downloadSHA256, !expectedSHA256.isEmpty else {
				log.error("Refusing to download \(bundle.name ?? "", privacy: .public): the index carries no sha256 for it")
				group.leave()
				continue
			}

			progress.becomeCurrent(withPendingUnitCount: 1)
			_ = OakDownloadManager.sharedInstance.downloadArchive(at: downloadURL, forReplacing: destURL, expectedSHA256: expectedSHA256, expectedSize: Int64(bundle.downloadSize)) { extractedArchiveURL, error in
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
			bundle.downloadSHA256      = version?["sha256"] as? String

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

	// **The two MacroMates DSA keys that used to live here are gone**, removed
	// 2026-09-20 with the move off api.textmate.org. They were the fallback when
	// the index named no keys of its own, which meant this fork trusted, by
	// default, signatures made by an organisation it has no relationship with —
	// and a bundle command is arbitrary code, so that was a code-execution path
	// into every user of this fork if their infrastructure were ever turned or
	// compromised.
	//
	// Nothing replaces them here. The index is now verified as a whole through
	// UpdateManifest.verifiedPayload against TMUpdateManifestKeys, and each
	// payload by the sha256 that signed index carries, so there is no longer a
	// per-archive signature and no key list for one.

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
