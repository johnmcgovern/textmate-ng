import AppKit

// The file browser's directory-observation machinery. FileItem
// (addObserverToDirectory / removeObserver) hands each watched URL a shared
// URLObserver that fans changes out to its clients; the concrete watcher behind
// each one comes from +makeObserverForURL:usingBlock: (the default here is a
// FileSystemObserver for file URLs; SCM/computer subclasses override it).
//
// The one C++ fragment — the git-deleted files in a directory — lives in ObjC++
// FileItemObserverSupport; everything else uses the C++-free FSEventsManager /
// SCMManager APIs.

// The directory enumeration the ObjC++ ran on a global queue. A file-scope
// nonisolated async function runs off the main actor, so FileSystemObserver
// (main-actor-isolated) can await it and apply the result on the main actor
// without sending self or a closure off-actor.
private func enumerateDirectoryContents(_ url: URL) async -> [URL] {
	return (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isHiddenKey, .localizedNameKey, .effectiveIconKey], options: [])) ?? []
}

// Watches a file:// directory: reloads its contents on FSEvents, and adds the
// files git now considers deleted (which no longer exist on disk, so FSEvents
// alone would miss them) from the SCM status.
@MainActor
@objc(FileSystemObserver)
class FileSystemObserver: NSObject {
	private let handler: ([URL]) -> Void

	private var fsEventsURLs: [URL]?
	private var scmURLs: [URL] = []

	private var fsEventsObserver: Any?
	private var scmObserver: Any?

	@objc(initWithURL:usingBlock:)
	init(URL url: NSURL, usingBlock handler: @escaping ([URL]) -> Void) {
		self.handler = handler
		super.init()

		fsEventsObserver = FSEventsManager.sharedInstance.addObserverToDirectory(at: url as URL) { [weak self] _ in
			self?.loadContentsOfDirectory(at: url)
		}

		scmObserver = SCMManager.sharedInstance.addObserverToRepository(at: url as URL) { [weak self] repository in
			let urls = FileItemObserverSupport.deletedURLs(in: repository, forDirectoryURL: url as URL)
			self?.updateFSEventsURLs(nil, scmURLs: urls)
		}

		loadContentsOfDirectory(at: url)
	}

	deinit {
		// A @MainActor class cannot touch its own state from a nonisolated deinit
		// under Swift 6; this object is always released on the main thread.
		MainActor.assumeIsolated {
			if let fsEventsObserver {
				FSEventsManager.sharedInstance.removeObserver(fsEventsObserver)
			}
			if let scmObserver {
				SCMManager.sharedInstance.removeObserver(scmObserver)
			}
		}
	}

	private func loadContentsOfDirectory(at url: NSURL) {
		// The ObjC++ did the enumeration on a global queue and applied the result
		// on the main queue. This class is main-actor-isolated, so the off-main
		// hop is a detached task (a @MainActor class is Sendable, so self may be
		// captured) and the result is applied back on the main actor.
		let directoryURL = url as URL
		Task {
			let urls = await enumerateDirectoryContents(directoryURL)
			self.updateFSEventsURLs(urls, scmURLs: nil)
		}
	}

	private func updateFSEventsURLs(_ fsEventsURLs: [URL]?, scmURLs: [URL]?) {
		self.fsEventsURLs = fsEventsURLs ?? self.fsEventsURLs
		self.scmURLs      = scmURLs ?? self.scmURLs

		guard let fsEventsURLs = self.fsEventsURLs else { return }

		var set = Set(fsEventsURLs)
		set.formUnion(self.scmURLs)
		handler(Array(set))
	}
}

// =====================================================
// = Shared per-URL observer that fans out to clients  =
// =====================================================

@MainActor
@objc(URLObserverClient)
class URLObserverClient: NSObject {
	let handler: ([URL]) -> Void
	// Strong, as in the ObjC++ original: the shared URLObserver is held only
	// weakly by the registry, so the client (retained by the file browser) is
	// what keeps it alive. The resulting client↔observer cycle is broken by
	// removeFromURLObserver when the browser drops the client.
	var urlObserver: URLObserver?

	init(block handler: @escaping ([URL]) -> Void) {
		self.handler = handler
		super.init()
	}

	func removeFromURLObserver() {
		urlObserver?.removeClient(self)
	}
}

@MainActor
@objc(URLObserver)
class URLObserver: NSObject {
	let url: NSURL
	private var clients: [URLObserverClient] = []
	var driver: Any?

	var cachedURLs: [URL]? {
		didSet {
			for client in clients {
				client.handler(cachedURLs ?? [])
			}
		}
	}

	init(URL url: NSURL) {
		self.url = url
		super.init()
	}

	func addClient(_ client: URLObserverClient) {
		client.urlObserver = self
		clients.append(client)
		if let cachedURLs, !cachedURLs.isEmpty {
			client.handler(cachedURLs)
		}
	}

	func removeClient(_ client: URLObserverClient) {
		clients.removeAll { $0 === client }
		client.urlObserver = nil
	}
}

// The registry was a method-static NSMapTable; a file-private global keeps the
// same (main-thread-only, unsynchronized) contract, since an extension cannot
// hold a stored static property.
nonisolated(unsafe) private let fileItemDirectoryObservers = NSMapTable<NSURL, URLObserver>.strongToWeakObjects()

extension FileItem {
	@MainActor
	@objc(addObserverToDirectoryAtURL:usingBlock:)
	class func addObserverToDirectory(at url: NSURL, usingBlock handler: @escaping ([URL]) -> Void) -> URLObserverClient {
		let observer: URLObserver
		if let existing = fileItemDirectoryObservers.object(forKey: url) {
			observer = existing
		} else {
			observer = URLObserver(URL: url)
			fileItemDirectoryObservers.setObject(observer, forKey: url)
		}

		let client = URLObserverClient(block: handler)
		observer.addClient(client)

		if observer.driver == nil {
			let klass = classForURL(url) as? FileItem.Type
			observer.driver = klass?.makeObserver(forURL: url, usingBlock: { [weak observer] urls in
				observer?.cachedURLs = urls
			})
		}

		return client
	}

	@MainActor
	@objc(removeObserver:)
	class func removeObserver(_ someObserver: Any) {
		(someObserver as? URLObserverClient)?.removeFromURLObserver()
	}
}
