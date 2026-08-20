import AppKit
import TMFileReference

// Ported from SCMManager.mm (2026-08-18). No C++ crosses into this file: 7dde4c06
// moved the `scm::driver_t const*` and the `std::map<std::string, scm::status::type>`
// behind SCMDriver / SCMStatus (SCMSupport.h), which is the whole reason the manager
// can be Swift. The two ObjC++ consumers that still want the raw map reach it through
// SCMStatus's own Cxx category (SCMSupportCxx.h), untouched by this port.
//
// **Deliberately not @MainActor**, like FSEventsManager and for the same reason: a
// @MainActor SCMRepository would trap the moment its background status update read
// `self.driver` off the main actor, and its deinit — which runs on whatever thread
// drops the last reference — would trap the same way. That is the alpha.13/alpha.14
// crash family. The class is no more and no less thread-safe than the ObjC++ was.
//
// SCMRepository is `@unchecked Sendable`, honestly (rule from FFDocumentSearch): every
// piece of its mutable state is written only on the main queue — in `init` and in
// `updateStatus`, which the background hop dispatches back to main — and the one thing
// the background block reads, `driver`/`url`, is immutable after `init`.
//
// Ownership is load-bearing and copied verbatim (rule 27): both maps hold their values
// **weakly** (`strongToWeakObjects`), so a repository lives only as long as an observer
// or a SCMDirectory holds it, and the observer↔repository strong cycle that implies is
// broken by `removeObserver`. Do not "improve" any of these weak/strong choices.

// -removeObserver: sends -remove to whatever token -addObserver… returned, and both
// token types answer it; a Swift protocol both conform to preserves that dynamic
// dispatch (rule 33) without an NSProxy or an ObjC-only conformance (rule 47).
private protocol SCMObserverToken: AnyObject {
	func remove()
}

// ===========================================
// = Helper classes for observer identifiers =
// ===========================================

private class SCMRepositoryObserver: NSObject, SCMObserverToken {
	let handler: (SCMRepository) -> Void
	// Strong, matching the ObjC++ `@property (nonatomic) SCMRepository*`: the
	// observer array holds this, and this holds the repository, so a repository with
	// observers outlives the weak manager map. removeObserver breaks the cycle.
	var repository: SCMRepository?

	init(block handler: @escaping (SCMRepository) -> Void) {
		self.handler = handler
		super.init()
	}

	func remove() {
		repository?.removeObserver(self)
	}
}

private class SCMDirectoryObserver: NSObject, SCMObserverToken {
	let handler: (SCMRepository) -> Void
	var directory: SCMDirectory?

	init(block handler: @escaping (SCMRepository) -> Void) {
		self.handler = handler
		super.init()
	}

	func remove() {
		directory?.removeObserver(self)
	}
}

// ===========================================

@objc(SCMRepository)
class SCMRepository: NSObject, @unchecked Sendable {
	@objc(URL) let url: URL
	@objc private(set) var enabled: Bool = false
	@objc private(set) var tracksDirectories: Bool = false
	@objc private(set) var hasStatus: Bool = false
	@objc private(set) var status: SCMStatus?
	@objc private(set) var variables: [String: String] = [:]

	private let driver: SCMDriver
	private var observers: [SCMRepositoryObserver] = []
	private var fsEventsObserver: Any?

	private var needsUpdate = false
	private var updating = false
	private var updateTimer: Timer?
	private var noUpdateBefore = Date.distantPast
	// nil in the ObjC++ until the first update; an empty set behaves identically for
	// the -removeObject:/for-in below (rule 33), so a plain empty set is faithful.
	private var fileReferences = Set<TMFileReference>()

	init(url: URL, driver: SCMDriver) {
		self.url = url
		self.driver = driver
		super.init()

		enabled = SCMDriver.isSCMEnabled(forPath: url.path)
		tracksDirectories = driver.tracksDirectories

		if enabled {
			tryUpdateStatusInBackground()

			fsEventsObserver = FSEventsManager.sharedInstance.addObserverToDirectory(at: url, observeSubdirectories: true) { [weak self] _ in
				guard let self else { return }
				// FSEvents is scheduled on the main runloop (FSEventStream.mm), so this
				// block is on the main actor; assumeIsolated makes the NSApp read honest
				// rather than a bare cross-actor access.
				let active = MainActor.assumeIsolated { NSApp.isActive }
				noUpdateBefore = max(noUpdateBefore, Date(timeIntervalSinceNow: active ? 0.5 : 3))
				tryUpdateStatusInBackground()
			}
		}

		// object: nil, not NSApp: NSApplicationDidBecomeActive only ever comes from
		// NSApp, and reading NSApp from this non-@MainActor init (and, worse, from a
		// deinit that can run on any thread) would be the cross-actor trap this
		// framework's port queue keeps meeting.
		NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive(_:)), name: NSApplication.didBecomeActiveNotification, object: nil)
	}

	deinit {
		// This object registers exactly the one observation above, so removeObserver(self)
		// clears it without naming NSApp — see the note there.
		NotificationCenter.default.removeObserver(self)
		if let fsEventsObserver {
			FSEventsManager.sharedInstance.removeObserver(fsEventsObserver)
		}
	}

	@objc private func applicationDidBecomeActive(_ notification: Notification) {
		if updateTimer != nil {
			updateStatusInBackground(nil)
		}
	}

	private func tryUpdateStatusInBackground() {
		if updating {
			needsUpdate = true
			return
		}

		let delayUpdate = noUpdateBefore.timeIntervalSinceNow
		if delayUpdate > 0 {
			updateTimer?.invalidate()
			updateTimer = Timer.scheduledTimer(timeInterval: delayUpdate, target: self, selector: #selector(updateStatusInBackground(_:)), userInfo: nil, repeats: false)
		} else {
			updateStatusInBackground(nil)
		}
	}

	@objc private func updateStatusInBackground(_ sender: Any?) {
		updateTimer?.invalidate()
		updateTimer = nil
		needsUpdate = false
		updating = true

		DispatchQueue.global(qos: .default).async { [weak self] in
			guard let self else { return }
			// driver and url are immutable after init, so reading them here is the
			// honest part of @unchecked Sendable. status/variables are computed
			// snapshots that then cross back to the main queue.
			let status = self.driver.status(forDirectory: self.url.path)
			let variables = self.driver.variables(forDirectory: self.url.path)

			DispatchQueue.main.async { [weak self] in
				self?.updateStatus(status, variables: variables)
			}
		}
	}

	private func updateStatus(_ status: SCMStatus, variables: [String: String]) {
		self.status = status
		self.variables = variables
		hasStatus = true

		var fileReferences = Set<TMFileReference>()
		for (path, rawStatus) in status.entries {
			let scmStatus = TMSCMStatus(rawValue: rawStatus.uintValue)
			if scmStatus != .none {
				let fileReference = TMFileReference(url: URL(fileURLWithPath: path))
				fileReference.scmStatus = scmStatus
				fileReferences.insert(fileReference)
				self.fileReferences.remove(fileReference)
			}
		}

		for fileReference in self.fileReferences {
			fileReference.scmStatus = .none
		}
		self.fileReferences = fileReferences

		for observer in observers {
			observer.handler(self)
		}

		updating = false
		noUpdateBefore = max(noUpdateBefore, Date(timeIntervalSinceNow: 1.5))
		if needsUpdate {
			tryUpdateStatusInBackground()
		}
	}

	fileprivate func addObserver(_ handler: @escaping (SCMRepository) -> Void) -> SCMRepositoryObserver {
		let observer = SCMRepositoryObserver(block: handler)
		observer.repository = self
		observers.append(observer)

		if hasStatus {
			handler(self)
		}

		return observer
	}

	fileprivate func removeObserver(_ observer: SCMRepositoryObserver) {
		observers.removeAll { $0 === observer }
		observer.repository = nil
	}
}

private class SCMDirectory: NSObject {
	let url: URL
	let repository: SCMRepository?
	private var repositoryObserver: SCMRepositoryObserver?
	private var observers: [SCMDirectoryObserver] = []

	init(url: URL) {
		self.url = url
		repository = SCMManager.sharedInstance.repository(at: url)
		super.init()

		repositoryObserver = repository?.addObserver { [weak self] repository in
			guard let self else { return }
			for observer in observers {
				observer.handler(repository)
			}
		}
	}

	deinit {
		if let repositoryObserver {
			repository?.removeObserver(repositoryObserver)
		}
	}

	func addObserver(_ handler: @escaping (SCMRepository) -> Void) -> SCMDirectoryObserver {
		let observer = SCMDirectoryObserver(block: handler)
		observer.directory = self
		observers.append(observer)

		if let repository, repository.hasStatus {
			handler(repository)
		}

		return observer
	}

	func removeObserver(_ observer: SCMDirectoryObserver) {
		observers.removeAll { $0 === observer }
		observer.directory = nil
	}
}

@objc(SCMManager)
class SCMManager: NSObject {
	@objc nonisolated(unsafe) static let sharedInstance = SCMManager()

	// Keys strong, values weak — +strongToWeakObjectsMapTable. The manager does not
	// own repositories or directories; their observers do.
	private let repositories = NSMapTable<NSURL, SCMRepository>.strongToWeakObjects()
	private let directories = NSMapTable<NSURL, SCMDirectory>.strongToWeakObjects()

	@objc(repositoryAtURL:)
	func repository(at url: URL) -> SCMRepository? {
		var url: URL? = url
		while let currentURL = url {
			if let repository = repositories.object(forKey: currentURL as NSURL) {
				return repository
			}

			if let driver = SCMDriver.driverWithInfo(forDirectory: currentURL.path) {
				let repository = SCMRepository(url: currentURL, driver: driver)
				repositories.setObject(repository, forKey: currentURL as NSURL)
				return repository
			}

			if (try? currentURL.resourceValues(forKeys: [.isVolumeKey]))?.isVolume == true {
				break
			}

			// NSURL -isEqual:, as the ObjC++ used — not Swift's URL ==, which normalizes
			// (rule 33). Only matters at the volume root, where parentDirectory returns
			// the URL itself, but the discipline is cheap and the divergence is a trap.
			guard let parentURL = (try? currentURL.resourceValues(forKeys: [.parentDirectoryURLKey]))?.parentDirectory, !(currentURL as NSURL).isEqual(parentURL) else {
				break
			}

			url = parentURL
		}
		return nil
	}

	private func directory(at url: URL) -> SCMDirectory {
		if let directory = directories.object(forKey: url as NSURL) {
			return directory
		}
		let directory = SCMDirectory(url: url)
		directories.setObject(directory, forKey: url as NSURL)
		return directory
	}

	@objc(addObserverToRepositoryAtURL:usingBlock:)
	func addObserverToRepository(at url: URL, usingBlock handler: @escaping (SCMRepository) -> Void) -> Any? {
		return repository(at: url)?.addObserver(handler)
	}

	@objc(removeObserver:)
	func removeObserver(_ someObserver: Any) {
		(someObserver as? SCMObserverToken)?.remove()
	}
}
