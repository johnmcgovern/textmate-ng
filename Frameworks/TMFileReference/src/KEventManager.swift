import Foundation
import os

// Watches a path with one dispatch VNODE source per *component*, so an observer
// on /a/b/c also learns when /a or /a/b is renamed, deleted or replaced — the
// reason this is a tree of nodes rather than a flat table of watchers.
//
// KEventManager.h stays hand-written, so no consumer changed — the pattern
// Preferences established and TMFileReference followed. It is deliberately not
// in TMFileReference-Bridging-Header.h either: it declares this class, the
// generated TMFileReference-Swift.h declares it too, and clang rejects the pair.

// Subsystem moved from the invented "KEventManager" to the app's own, as
// Shared/include/oak/log.h asks of these sites when they are touched:
//
//     /usr/bin/log stream --predicate 'subsystem == "com.j23software.TextMate-NG"'
//
// now catches this file's output along with everything else. Every interpolation
// below is `privacy: .public` because the ObjC++ spelled every one %{public}@ —
// Swift's Logger defaults to private, so leaving it off would silently turn the
// log into <private> placeholders.
private let log = Logger(subsystem: "com.j23software.TextMate-NG", category: "kevent-manager")

private func describe(_ mask: DispatchSource.FileSystemEvent) -> String {
	// The C spellings, not Swift's, because these strings go into a log a reader
	// greps against dispatch's own documentation. The overlay's raw values are
	// the DISPATCH_VNODE_* macro values bit for bit (checked, all eight).
	let flags: [(DispatchSource.FileSystemEvent, String)] = [
		( .delete,  "DISPATCH_VNODE_DELETE"  ),
		( .write,   "DISPATCH_VNODE_WRITE"   ),
		( .extend,  "DISPATCH_VNODE_EXTEND"  ),
		( .attrib,  "DISPATCH_VNODE_ATTRIB"  ),
		( .link,    "DISPATCH_VNODE_LINK"    ),
		( .rename,  "DISPATCH_VNODE_RENAME"  ),
		( .revoke,  "DISPATCH_VNODE_REVOKE"  ),
		( .funlock, "DISPATCH_VNODE_FUNLOCK" ),
	]
	return flags.filter { mask.contains($0.0) }.map(\.1).joined(separator: "|")
}

// -[NSString fileSystemRepresentation]'s buffer lives only as long as the string
// does, so it is scoped to a closure rather than handed out. Kept rather than
// passing Swift's UTF-8 straight to open()/access()/stat(): the ObjC++ used
// fileSystemRepresentation, and that is the conversion Foundation guarantees
// round-trips a path.
private func withFileSystemRepresentation<T>(of path: String, _ body: (UnsafePointer<CChar>) -> T) -> T {
	let string = path as NSString
	return withExtendedLifetime(string) { body(string.fileSystemRepresentation) }
}

// -getRelationship:ofDirectory:inDomain:toItemAtURL:error: imports as a throwing
// call with an out-parameter, so its BOOL-and-out-param pair becomes this: a
// thrown error means "could not tell", which the ObjC++ also read as "not in the
// trash".
private func isInTrash(_ path: String) -> Bool {
	var relationship: FileManager.URLRelationship = .other
	guard (try? FileManager.default.getRelationship(&relationship, of: .trashDirectory, in: .allDomainsMask, toItemAt: URL(fileURLWithPath: path))) != nil else { return false }
	return relationship == .contains
}

private func pathsShareInode(_ lhs: String, _ rhs: String) -> Bool {
	var lhsStatBuf = stat(), rhsStatBuf = stat()
	guard withFileSystemRepresentation(of: lhs, { stat($0, &lhsStatBuf) }) == 0,
	      withFileSystemRepresentation(of: rhs, { stat($0, &rhsStatBuf) }) == 0
	else { return false }
	return lhsStatBuf.st_ino == rhsStatBuf.st_ino && lhsStatBuf.st_dev == rhsStatBuf.st_dev
}

// =========================
// = KEventManagerCallback =
// =========================

// The token -addObserverToItemAtURL:usingBlock: hands back, and the strong half
// of a deliberate cycle: a node holds its callbacks and each callback holds its
// node, so the token the caller keeps alive is what keeps that node — and, up
// the `parentNode` chain, every watcher above it — from being collected.
// -removeObserver: breaks the cycle. Dropping the token without calling it
// leaks the chain, exactly as the ObjC++ did.
final class KEventManagerCallback: NSObject {
	let handler: (URL, UInt) -> Void
	var node: KEventManagerNode?

	init(handler: @escaping (URL, UInt) -> Void) {
		self.handler = handler
		super.init()
	}

	func removeFromKEventManagerNode() {
		node?.removeCallback(self)
	}
}

// =====================
// = KEventManagerNode =
// =====================

final class KEventManagerNode: NSObject {
	private var dispatchSource: DispatchSourceFileSystemObject?
	private var fileDescriptor: Int32 = -1
	// The `[_callbacks copy]` the ObjC++ wrote at every site that notifies is
	// implicit here — an array is a value, so a handler that removes an observer
	// cannot mutate the sequence being iterated.
	private var callbacks: [KEventManagerCallback] = []

	// Children are held *weakly* and the parent strongly, so a subtree lives
	// exactly as long as something at its bottom is still observed.
	let childNodesMap = NSMapTable<NSString, KEventManagerNode>.strongToWeakObjects()
	var parentNode: KEventManagerNode?

	let pathComponent: String?
	private var accessibleStorage = false

	init(pathComponent: String?, parentNode: KEventManagerNode?) {
		self.pathComponent = pathComponent
		super.init()

		addToParentNode(parentNode)
		checkAccessible()
	}

	deinit {
		let component = pathComponent
		log.debug("[KEventManagerNode deinit] \(component ?? "", privacy: .public)")

		removeFromParent()
		accessible = false
	}

	func addCallback(_ callback: KEventManagerCallback) {
		callbacks.append(callback)
		callback.node = self
	}

	func removeCallback(_ callback: KEventManagerCallback) {
		callbacks.removeAll { $0 === callback }
		callback.node = nil
	}

	// A snapshot rather than the live enumerator: -didMoveObservedPathToPath:
	// re-parents children while iterating them, and -setAccessible: can drop the
	// last reference to one mid-loop.
	private var childNodes: [KEventManagerNode] {
		return (childNodesMap.objectEnumerator()?.allObjects as? [KEventManagerNode]) ?? []
	}

	// nil only for the root, which stands in for "no path at all" — every real
	// node below it has a component, and the volume node carries the whole
	// volume path as its own.
	var path: String? {
		guard let pathComponent else { return nil }
		guard let parentNode, parentNode.pathComponent != nil, let parentPath = parentNode.path else { return pathComponent }
		return (parentPath as NSString).appendingPathComponent(pathComponent)
	}

	private func addChildNode(_ child: KEventManagerNode) {
		guard let component = child.pathComponent else { return }
		childNodesMap.setObject(child, forKey: component as NSString)
		child.parentNode = self
	}

	private func removeChildNode(_ child: KEventManagerNode) {
		guard let component = child.pathComponent else { return }
		childNodesMap.removeObject(forKey: component as NSString)
		child.parentNode = nil
	}

	func addToParentNode(_ parentNode: KEventManagerNode?) {
		parentNode?.addChildNode(self)
	}

	private func removeFromParent() {
		parentNode?.removeChildNode(self)
	}

	var accessible: Bool {
		get { accessibleStorage }
		set {
			guard accessibleStorage != newValue else { return }

			accessibleStorage = newValue
			if newValue {
				setUpEventSource()

				for childNode in childNodes {
					childNode.checkAccessible()
				}
			} else {
				tearDownEventSource()

				for childNode in childNodes {
					childNode.accessible = false
				}
			}

			// Only the root has no path, and it never changes accessibility, so
			// this guard never fires — it stands in for the ObjC++ handing a nil
			// path to +fileURLWithPath:, which would have thrown.
			guard let path else { return }

			let mask = newValue ? DispatchSource.FileSystemEvent.write : .delete
			for callback in callbacks {
				callback.handler(URL(fileURLWithPath: path), mask.rawValue)
			}
		}
	}

	func checkAccessible() {
		guard let path else { return }
		accessible = withFileSystemRepresentation(of: path) { access($0, F_OK) } != -1
	}

	private func setUpEventSource() {
		guard let path else { return }

		if fileDescriptor != -1 {
			log.error("[KEventManagerNode setUpEventSource] Event source already exists for \(path, privacy: .public)")
			return
		}

		fileDescriptor = withFileSystemRepresentation(of: path) { open($0, O_EVTONLY | O_CLOEXEC, 0) }
		guard fileDescriptor != -1 else {
			log.error("[KEventManagerNode setUpEventSource] Unable to access \(path, privacy: .public)")
			return
		}

		log.debug("[KEventManagerNode setUpEventSource] \(path, privacy: .public)")

		let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: [ .delete, .write, .extend, .rename, .revoke ], queue: .main)
		source.setEventHandler { [weak self] in
			self?.handleKEvent(source.data)
		}

		// From here the SOURCE owns the descriptor, and closing it is the
		// cancellation handler's job.
		//
		// dispatch_source_cancel() is asynchronous, and dispatch_source_create's
		// contract for the fd-based source types is explicit: the descriptor must
		// not be closed until the cancellation handler runs, because the source may
		// still be delivering an event against it. -tearDownEventSource used to
		// close it immediately after cancelling, which left the number free for any
		// other open() in the process to claim while the dying source still
		// referenced it.
		//
		// That is not merely untidy here: handleKEvent(_:) recovers a renamed
		// file's new path with fcntl(F_GETPATH) on this very descriptor, so a
		// recycled number means re-parenting the node onto an unrelated file and
		// reporting its changes instead. The rename branch below even tears down
		// and immediately sets up again, which is exactly the window where the
		// number would have been reused.
		let fd = fileDescriptor
		source.setCancelHandler { close(fd) }

		dispatchSource = source
		source.resume()
	}

	private func tearDownEventSource() {
		log.debug("[KEventManagerNode tearDownEventSource] \(self.path ?? "", privacy: .public)")

		if let dispatchSource {
			// Forget the descriptor here but do not close it — the cancellation
			// handler installed in setUpEventSource() owns that, and will run once
			// the source has finished draining. Clearing the ivar first means a
			// queued event arriving in the meantime sees -1 and does nothing, rather
			// than reading a descriptor that is on its way out.
			fileDescriptor = -1
			dispatchSource.cancel()
			self.dispatchSource = nil
		} else if fileDescriptor != -1 {
			// open() succeeded but the source was never created, so there is nothing
			// to hand ownership to and this is the only place that can close it.
			close(fileDescriptor)
			fileDescriptor = -1
		} else {
			log.error("[KEventManagerNode tearDownEventSource] No event source for \(self.path ?? "", privacy: .public)")
		}
	}

	private func handleKEvent(_ mask: DispatchSource.FileSystemEvent) {
		log.debug("[KEventManagerNode handleKEvent:\(describe(mask), privacy: .public)] \(self.path ?? "", privacy: .public)")

		if mask.contains(.rename) {
			var buf = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
			if fcntl(fileDescriptor, F_GETPATH, &buf) == 0 {
				let oldPath   = self.path ?? ""
				let oldParent = (oldPath as NSString).deletingLastPathComponent
				var newPath   = String(decoding: buf.prefix { $0 != 0 }, as: UTF8.self)
				let newParent = (newPath as NSString).deletingLastPathComponent

				if oldPath == newPath {
					log.error("[KEventManagerNode handleKEvent:\(describe(mask), privacy: .public)] Path unchanged \(newPath, privacy: .public)")
				} else if isInTrash(newPath) {
					log.info("[KEventManagerNode handleKEvent:\(describe(mask), privacy: .public)] Item moved to trash \(oldPath, privacy: .public) → \(newPath, privacy: .public)")
					didDeleteObservedPath()
				} else {
					if oldParent != newParent && pathsShareInode(oldParent, newParent) {
						newPath = (oldParent as NSString).appendingPathComponent((newPath as NSString).lastPathComponent)
						log.info("[KEventManagerNode handleKEvent:\(describe(mask), privacy: .public)] Preserve symbolic name of ancestor \(oldPath, privacy: .public) → \(newPath, privacy: .public) (ignored directory \(newParent, privacy: .public))")
					}

					if withFileSystemRepresentation(of: oldPath, { access($0, F_OK) }) == 0 {
						if pathsShareInode(oldPath, newPath) {
							log.info("[KEventManagerNode handleKEvent:\(describe(mask), privacy: .public)] Old path exists after rename (\(oldPath, privacy: .public)) with same inode, likely case change, use new path (\(newPath, privacy: .public))")
							didMoveObservedPath(to: newPath)
						} else {
							log.info("[KEventManagerNode handleKEvent:\(describe(mask), privacy: .public)] Old path exists after rename (\(oldPath, privacy: .public)) ignore new path (\(newPath, privacy: .public))")
							tearDownEventSource()
							setUpEventSource()
							didUpdateObservedPath()

							// Original folder was replaced with new one, so check accessibility of children
							for childNode in childNodes {
								childNode.checkAccessible()
							}
						}
					} else {
						log.info("[KEventManagerNode handleKEvent:\(describe(mask), privacy: .public)] Rename \(oldPath, privacy: .public) → \(newPath, privacy: .public)")
						didMoveObservedPath(to: newPath)
					}
				}
			} else {
				log.error("[KEventManagerNode handleKEvent:\(describe(mask), privacy: .public)] Unable to obtain new path for \(self.path ?? "", privacy: .public)")
			}
		}

		if mask.contains(.write) || mask.contains(.extend) {
			for childNode in childNodes where !childNode.accessible {
				childNode.checkAccessible()
			}
			didUpdateObservedPath()
		}

		if mask.contains(.delete) || mask.contains(.revoke) {
			if !mask.contains(.rename) {
				didDeleteObservedPath()
			}
		}
	}

	private func didUpdateObservedPath() {
		guard let path else { return }
		for callback in callbacks {
			callback.handler(URL(fileURLWithPath: path), DispatchSource.FileSystemEvent.write.rawValue)
		}
	}

	private func didMoveObservedPath(to newPath: String) {
		let newNode = KEventManager.sharedInstance.node(for: URL(fileURLWithPath: newPath), makeIfNecessary: true)

		for childNode in childNodes {
			childNode.addToParentNode(newNode)
		}
		childNodesMap.removeAllObjects()

		for callback in callbacks {
			newNode?.addCallback(callback)
		}
		callbacks.removeAll()

		// Hands off the last strong reference to self, so this node may be gone
		// the moment the caller's frame unwinds. Nothing below touches it.
		newNode?.didRenameObservedPath()
	}

	private func didRenameObservedPath() {
		if let path {
			for callback in callbacks {
				callback.handler(URL(fileURLWithPath: path), DispatchSource.FileSystemEvent.rename.rawValue)
			}
		}

		for childNode in childNodes {
			childNode.didRenameObservedPath()
		}
	}

	private func didDeleteObservedPath() {
		// FIXME This may send DELETE followed by WRITE to observers (when overwritten)
		accessible = false // Remove observer from old inode and send DELETE
		checkAccessible()  // Check if new file has been written to observed path
	}

	// Debug helper, reachable only from -[KEventManager dumpNodes]. The stray
	// newline inside the "NO" is upstream's and is kept so the output is
	// unchanged; NSLog rather than the Logger for the same reason.
	func dumpNodes(indent level: Int) {
		NSLog("%@- %@ (%lu, accessible %@)", String(repeating: " ", count: 2 * level), pathComponent ?? "", callbacks.count, accessible ? "YES" : "NO\n")

		for childNode in childNodes {
			childNode.dumpNodes(indent: level + 1)
		}
	}
}

// =================
// = KEventManager =
// =================

@objc(KEventManager)
final class KEventManager: NSObject {
	// nonisolated(unsafe) rather than @MainActor: the tree is main-queue-only by
	// contract — the sources all target the main queue — but the type is reached
	// from ObjC++ callers Swift cannot see, and a node has to tear its own
	// watcher down from deinit, which a @MainActor class is not allowed to do.
	@objc nonisolated(unsafe) static let sharedInstance = KEventManager()

	private let rootNode = KEventManagerNode(pathComponent: nil, parentNode: nil)

	deinit {
		log.debug("[KEventManager deinit]")
	}

	// Walks up to the volume, then back down from the root, so /a/b/c becomes
	// four nodes and each of them gets its own watcher.
	func node(for url: URL, makeIfNecessary flag: Bool) -> KEventManagerNode? {
		var url = url
		var pathComponents: [String] = []

		while !((try? url.resourceValues(forKeys: [ .isVolumeKey ]))?.isVolume ?? false) {
			let parent = url.deletingLastPathComponent()
			if url.path.count < parent.path.count {
				log.error("[KEventManager node(for:makeIfNecessary:)] Unable to obtain wellformed parent for \(url.path, privacy: .public)")
				return nil
			}

			// -[NSString lastPathComponent], not -[NSURL lastPathComponent]: the
			// two disagree about a trailing slash, and this has to pair with the
			// -URLByDeletingLastPathComponent above.
			pathComponents.append((url.path as NSString).lastPathComponent)
			url = parent
		}
		pathComponents.append(url.path)

		var res: KEventManagerNode? = rootNode
		for pathComponent in pathComponents.reversed() {
			// Only reachable with flag == false, where the ObjC++ went on messaging
			// nil for the remaining components and returned nil just the same.
			guard let node = res else { break }

			var child = node.childNodesMap.object(forKey: pathComponent as NSString)
			if child == nil && flag {
				child = KEventManagerNode(pathComponent: pathComponent, parentNode: node)
			}
			res = child
		}
		return res
	}

	// ==============
	// = Public API =
	// ==============

	@objc(addObserverToItemAtURL:usingBlock:)
	func addObserver(toItemAt url: URL, using handler: @escaping (URL, UInt) -> Void) -> Any {
		let callback = KEventManagerCallback(handler: handler)
		node(for: url, makeIfNecessary: true)?.addCallback(callback)
		return callback
	}

	@objc(removeObserver:)
	func removeObserver(_ someObserver: Any) {
		// The ObjC++ cast unconditionally; this ignores anything that is not one of
		// our tokens rather than trapping on it.
		(someObserver as? KEventManagerCallback)?.removeFromKEventManagerNode()
	}

	@objc func dumpNodes() {
		autoreleasepool {
			for node in (rootNode.childNodesMap.objectEnumerator()?.allObjects as? [KEventManagerNode]) ?? [] {
				node.dumpNodes(indent: 0)
			}
		}
	}
}
