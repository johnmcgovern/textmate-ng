import AppKit

// Directory observation, fanned out per URL. Ported from FSEventsManager.mm
// (2026-08-18) once 3f6bcc0c moved the std::shared_ptr<fs_events_t> ivar into the
// ObjC++ FSEventStream, which is the only reason this class can be Swift at all.
//
// **Deliberately not @MainActor**, unlike its neighbours in this framework. The
// ObjC++ carried no isolation and one of its callers is
// -[SCMRepository dealloc] (SCMManager.mm), which runs on whatever thread drops
// the last reference — SCMRepository does background status updates, so that is
// not always the main thread. Marking this class @MainActor would turn a
// background dealloc into a Swift 6 executor trap, which is exactly the failure
// that shipped as the alpha.13 Settings ▸ Software Update crash. The class is no
// less thread-safe than the ObjC++ was (it is not, and never was); what changed
// would only be how loudly it fails.
//
// The three-object shape is kept verbatim because its memory semantics are load
// bearing: `directories` holds its values **weakly**, so a directory lives only
// as long as some client holds it, and clients hold their directory strongly.
// The cycle that implies is broken by -removeFromDirectory, and a caller that
// drops its token without calling -removeObserver: leaks both — as before.

// A single registered observer. The token -addObserverToDirectoryAtURL:… hands
// back is one of these, so it is what -removeObserver: receives.
private class FSEventsClient: NSObject {
	let handler: (URL) -> Void
	let observeSubdirectories: Bool

	// Strong, matching the ObjC++ `@property (nonatomic) FSEventsDirectory*`.
	// This is the reference that keeps a directory alive in the weak-valued map.
	var directory: FSEventsDirectory?

	init(block handler: @escaping (URL) -> Void, observeSubdirectories flag: Bool) {
		self.handler = handler
		self.observeSubdirectories = flag
		super.init()
	}

	func removeFromDirectory() {
		directory?.removeClient(self)
	}
}

// One watched directory and the clients listening to it.
private class FSEventsDirectory: NSObject {
	let url: URL
	private(set) var clients: [FSEventsClient] = []

	init(url: URL) {
		self.url = url
		super.init()
	}

	func didObserveChange(inDirectoryAt changedURL: URL) {
		// A change *in* this directory reaches every client; a change below it
		// reaches only those that asked for subdirectories.
		let changeInCurrentDirectory = changedURL == url
		// Swift iterates a snapshot, so a handler that removes an observer here
		// is safe. The ObjC++ enumerated the live array and would have raised a
		// mutation exception; nothing does this today, and the snapshot is the
		// better of the two behaviours.
		for client in clients where changeInCurrentDirectory || client.observeSubdirectories {
			client.handler(changedURL)
		}
	}

	func addClient(_ observer: FSEventsClient) {
		observer.directory = self
		clients.append(observer)
	}

	func removeClient(_ observer: FSEventsClient) {
		clients.removeAll { $0 === observer }
		observer.directory = nil
	}
}

@objc(FSEventsManager)
class FSEventsManager: NSObject {
	@objc nonisolated(unsafe) static let sharedInstance = FSEventsManager()

	// Keys strong, values weak — +strongToWeakObjectsMapTable. Entries clear
	// themselves when the last client releases a directory.
	private let directories = NSMapTable<NSURL, FSEventsDirectory>.strongToWeakObjects()
	private var fsEvents: FSEventStream?

	@objc(reloadDirectoryAtURL:)
	func reloadDirectory(at url: URL) {
		directories.object(forKey: url as NSURL)?.didObserveChange(inDirectoryAt: url)
	}

	private func resetObservers() {
		let urls = (directories.keyEnumerator().allObjects as? [NSURL])?.map { $0 as URL } ?? []
		// Captures self strongly, as the ObjC++ block did by referencing the
		// _directories ivar. self owns the stream, so this is a cycle — on a
		// singleton, which is why it was never a leak worth breaking.
		fsEvents = FSEventStream(urls: urls) { originalURL in
			// Walk up from the changed directory: a client watching an ancestor
			// with observeSubdirectories set has to hear about it too. Stops at a
			// volume root, or where the parent stops changing.
			var url = originalURL
			while true {
				self.directories.object(forKey: url as NSURL)?.didObserveChange(inDirectoryAt: originalURL)

				if (try? url.resourceValues(forKeys: [.isVolumeKey]))?.isVolume == true {
					break
				}
				guard let parent = (try? url.resourceValues(forKeys: [.parentDirectoryURLKey]))?.parentDirectory, parent != url else {
					break
				}
				url = parent
			}
		}
	}

	@objc(addObserverToDirectoryAtURL:usingBlock:)
	func addObserverToDirectory(at url: URL, usingBlock handler: @escaping (URL) -> Void) -> Any {
		addObserverToDirectory(at: url, observeSubdirectories: false, usingBlock: handler)
	}

	@objc(addObserverToDirectoryAtURL:observeSubdirectories:usingBlock:)
	func addObserverToDirectory(at url: URL, observeSubdirectories flag: Bool, usingBlock handler: @escaping (URL) -> Void) -> Any {
		var directory = directories.object(forKey: url as NSURL)
		if directory == nil {
			let newDirectory = FSEventsDirectory(url: url)
			directories.setObject(newDirectory, forKey: url as NSURL)
			directory = newDirectory
			// Only after the map holds it: resetObservers reads the key list.
			resetObservers()
		}

		let newClient = FSEventsClient(block: handler, observeSubdirectories: flag)
		directory?.addClient(newClient)
		return newClient
	}

	@objc(removeObserver:)
	func removeObserver(_ someObserver: Any) {
		guard let client = someObserver as? FSEventsClient else { return }
		let directory = client.directory

		client.removeFromDirectory()

		// The ObjC++ rebuilt the stream when a directory lost its last client —
		// that is when the weak map entry is about to clear.
		if directory?.clients.isEmpty ?? false {
			resetObservers()
		}
	}
}
