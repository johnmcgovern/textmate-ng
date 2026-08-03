import AppKit
import os

// One object per file URL, shared by everything that displays that file: it
// carries the icon (with its SCM badge and modified dimming) and the open and
// modified counts that several windows contribute to at once.
//
// TMFileReference.h stays hand-written, so no consumer changed — the pattern
// Preferences established. It cannot be imported here: the module and the class
// share a name, which is the `namespace TMFileReference` collision.

@objc(TMFileReference)
final class TMFileReference: NSObject {

	// Interned per URL, weakly, so every view of one file shares an object and
	// therefore its KVO notifications — that sharing is the class's whole
	// purpose, not an optimisation.
	//
	// nonisolated(unsafe) because the table is main-thread-only by contract, not
	// by isolation; the precondition below is what enforces it, exactly as the
	// ObjC++ NSAssert did. Marking the class @MainActor instead would change the
	// concurrency contract of a type many ObjC++ callers touch.
	nonisolated(unsafe) private static let mapTable = NSMapTable<NSURL, TMFileReference>.strongToWeakObjects()

	private let url: NSURL?
	private var openCount: UInt = 0
	private var modifiedCount: UInt = 0
	private var cachedImage: NSImage?

	@objc class func keyPathsForValuesAffectingIcon() -> Set<String> {
		return [ "image", "modified" ]
	}

	@objc(fileReferenceWithURL:)
	static func fileReference(with url: URL?) -> TMFileReference? {
		precondition(Thread.isMainThread, "TMFileReference.fileReference(with:) must be called on the main thread")

		guard let url else { return nil }
		let key = url.absoluteURL as NSURL

		if let existing = mapTable.object(forKey: key) {
			return existing
		}

		let res = TMFileReference(url: key)
		mapTable.setObject(res, forKey: key)
		return res
	}

	@objc(fileReferenceWithImage:)
	static func fileReference(with image: NSImage) -> TMFileReference {
		return TMFileReference(image: image)
	}

	@objc(imageForURL:size:)
	static func image(for url: URL, size: NSSize) -> NSImage? {
		guard let image = fileReference(with: url)?.image?.copy() as? NSImage else { return nil }
		image.size = size
		return image
	}

	private init(url: NSURL) {
		self.url = url
		super.init()
	}

	private init(image: NSImage) {
		self.url = nil
		self.cachedImage = image
		super.init()
	}

	deinit {
		// A leaked open count means some window closed without balancing its
		// -increaseOpenCount, which would leave the file looking permanently
		// open. Debug-only, as it was: assertionFailure compiles out in Release.
		if openCount != 0 {
			assertionFailure("TMFileReference deallocated with a non-zero open count: \(openCount)")
		}
	}

	override var hash: Int {
		return url?.hash ?? ObjectIdentifier(self).hashValue
	}

	override func isEqual(_ object: Any?) -> Bool {
		guard let other = object as? TMFileReference else { return false }
		// An image-backed reference has no URL and is never interned, so it is
		// only ever equal to itself.
		guard let url, let otherURL = other.url else { return self === other }
		return url.isEqual(otherURL)
	}

	// MARK: - Counts

    // Manual KVO notifications throughout: these are derived from counters that
    // several owners increment independently, so there is no single assignment
    // for Swift to observe.

	// @property (getter = isClosable) BOOL closable — selector -isClosable, KVC
	// key `closable`, which is what the will/didChangeValue calls below use.
	//
	// Annotating the *accessor* is the exact spelling. Worth being precise about
	// why, because the project's own rule overstates it: `@objc(isClosable)` on
	// the property would also work *here*, since KVC's search order for key
	// "closable" already tries -isClosable, and these two properties are
	// readonly. The documented setSelected: trap is about the **setter** —
	// @objc(isX) renames it to setIsX: — so it only bites a readwrite property.
	// The accessor spelling is used anyway: it is unambiguous, and it stays
	// correct if either of these ever gains a setter.
	@objc var closable: Bool {
		@objc(isClosable) get { openCount != 0 }
	}

	@objc var modified: Bool {
		@objc(isModified) get { modifiedCount != 0 }
	}

	@objc func increaseOpenCount() {
		willChangeValue(forKey: "closable")
		openCount += 1
		didChangeValue(forKey: "closable")
	}

	@objc func decreaseOpenCount() {
		assert(openCount != 0, "decreaseOpenCount with an open count of zero")
		guard openCount != 0 else { return }

		willChangeValue(forKey: "closable")
		openCount -= 1
		didChangeValue(forKey: "closable")
	}

	@objc func increaseModifiedCount() {
		assert(openCount != 0, "increaseModifiedCount with an open count of zero")

		willChangeValue(forKey: "modified")
		modifiedCount += 1
		didChangeValue(forKey: "modified")
	}

	@objc func decreaseModifiedCount() {
		assert(modifiedCount != 0, "decreaseModifiedCount with a modified count of zero")
		guard modifiedCount != 0 else { return }

		willChangeValue(forKey: "modified")
		modifiedCount -= 1
		didChangeValue(forKey: "modified")
	}

	@objc func performClose(_ sender: Any?) {
		guard let url else { return }
		// Swift's importer turns an NSNotificationName global whose name ends in
		// "Notification" into a static member on NSNotification.Name with that
		// suffix stripped — so the C symbol defined in TMFRSupport.mm arrives
		// here as .TMURLWillClose, and declaring one by hand would duplicate it.
		NotificationCenter.default.post(name: .TMURLWillClose, object: self, userInfo: [ "URL": url ])
	}

	// MARK: - Image

	// `[]`, not `.unknown`: TMSCMStatusUnknown is 0, and Swift imports the
	// zero member of an NS_OPTIONS as the empty set rather than as a case.
	@objc var SCMStatus: TMSCMStatus = [] {
		didSet {
			guard SCMStatus != oldValue else { return }
			// The badge is drawn into the cached image, so a status change has to
			// discard it — and say so, because views bind to `image`.
			if cachedImage != nil {
				willChangeValue(forKey: "image")
				cachedImage = nil
				didChangeValue(forKey: "image")
			}
		}
	}

	// Extension → icon file, from the app's DocumentTypes/bindings.plist. Lazily
	// built once; a Swift `static let` is already thread-safe, so this is the
	// dispatch_once the ObjC++ spelled out.
	private static let customBindings: [String: String] = {
		guard let path = Bundle.main.path(forResource: "DocumentTypes/bindings", ofType: "plist"),
		      let dict = NSDictionary(contentsOfFile: path) as? [String: [String]]
		else { return [:] }

		var res: [String: String] = [:]
		for (file, extensions) in dict {
			for ext in extensions {
				res[ext.lowercased()] = file
			}
		}
		return res
	}()

	// Icons loaded from the app bundle, cached by name. Reached from the drawing
	// handler, which AppKit may run off the main thread, so the cache is locked
	// rather than assumed main-thread — matching the ObjC++'s @synchronized.
	private static let log = Logger(subsystem: "com.j23software.TextMate-NG", category: "file-reference")

	nonisolated(unsafe) private static var imageCache: [String: NSImage] = [:]
	private static let imageCacheLock = NSLock()

	private static func imageNamed(_ name: String?) -> NSImage? {
		guard let name else { return nil }

		imageCacheLock.lock()
		defer { imageCacheLock.unlock() }

		if let cached = imageCache[name] {
			return cached
		}
		guard let url = Bundle.main.url(forResource: name, withExtension: "icns", subdirectory: "DocumentTypes"),
		      let image = NSImage(contentsOf: url)
		else { return nil }

		imageCache[name] = image
		return image
	}

	private static func badgeName(for status: TMSCMStatus) -> String? {
		// Only ever one badge, so this matches the whole value rather than
		// masking: a file carrying more than one status bit draws none. Existing
		// behaviour, preserved deliberately.
		switch status {
			case .conflicted:  return "scm-badge-conflicted"
			case .modified:    return "scm-badge-modified"
			case .added:       return "scm-badge-added"
			case .deleted:     return "scm-badge-deleted"
			case .unversioned: return "scm-badge-unversioned"
			case .mixed:       return "scm-badge-mixed"
			default:           return nil
		}
	}

	@objc var image: NSImage? {
		if let cachedImage { return cachedImage }

		let url = self.url as URL?
		let scmStatus = self.SCMStatus

		let res = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { dstRect in
			var drawLinkBadge = false
			var image: NSImage?

			if scmStatus == TMSCMStatus.deleted {
				image = NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kUnknownFSObjectIcon)))
			} else if let url, url.isFileURL {
				if !url.hasDirectoryPath {
					// Longest-suffix first: "foo.tar.gz" should match a "tar.gz"
					// binding before falling back to the plain extension.
					let pathName = url.lastPathComponent.lowercased()
					var imageName = Self.customBindings[pathName]

					if let dot = pathName.firstIndex(of: ".") {
						let afterDot = String(pathName[pathName.index(after: dot)...])
						imageName = Self.customBindings[afterDot] ?? Self.customBindings[(pathName as NSString).pathExtension]
					}

					image = Self.imageNamed(imageName)
					if image != nil {
						if let type = try? url.resourceValues(forKeys: [ .fileResourceTypeKey ]).fileResourceType {
							drawLinkBadge = (type == .symbolicLink)
						}
					}
				}

				if image == nil {
					guard let values = try? url.resourceValues(forKeys: [ .effectiveIconKey ]), let effective = values.effectiveIcon as? NSImage else {
						Self.log.error("No effective icon for \(url.path, privacy: .public)")
						return false
					}
					image = effective
				}
			} else if url?.scheme == "computer" {
				image = NSImage(named: NSImage.computerName)
			} else if url?.hasDirectoryPath == true {
				image = NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericFolderIcon)))
			} else {
				image = NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericDocumentIcon)))
			}

			image?.draw(in: dstRect, from: .zero, operation: .copy, fraction: 1)

			if scmStatus != TMSCMStatus.none, let badge = Self.imageNamed(Self.badgeName(for: scmStatus)) {
				badge.draw(in: dstRect, from: .zero, operation: .sourceOver, fraction: 1)
			}

			if drawLinkBadge, let badge = TMAliasBadgeImage() {
				badge.draw(in: dstRect, from: .zero, operation: .sourceOver, fraction: 1)
			}

			return true
		}

		cachedImage = res
		return res
	}

	// The image dimmed when the file has unsaved changes.
	@objc var icon: NSImage? {
		guard let res = image else { return nil }
		guard modified else { return res }

		return NSImage(size: res.size, flipped: false) { dstRect in
			res.draw(in: dstRect, from: .zero, operation: .copy, fraction: 0.4)
			return true
		}
	}
}
