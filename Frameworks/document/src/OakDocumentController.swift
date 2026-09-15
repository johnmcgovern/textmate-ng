import Foundation

// Ported from OakDocumentController.mm — the document registry, the untitled-
// count reservation, the last-recently-used ranks, and the directory walk Find
// in Folder and the file chooser enumerate through. Pinned by
// t_document_controller.mm, written first.
//
// OakDocumentController.h stays as the hand-written declaration (rule 23) for
// the ObjC++ consumers and for the four bridging headers that import it. The
// C++ is behind two ObjC faces the previous commit made: OakDocumentRegistry
// (the three maps under a mutex) and OakDocumentWalk (the glob list and the
// directory walk). The two window wrappers that pass a C++ range are a category
// in OakDocumentControllerCxx.mm (rule 37) and do not move.
//
// Not @MainActor: the walk runs on Find's background queue and creates and
// looks up documents through the registry, whose mutex is what makes that
// safe — as the ObjC++ was. The LRU bookkeeping is main-thread by use, like
// the timer that saves it.

@objc(OakDocumentController)
class OakDocumentController: NSObject {
	// nonisolated(unsafe) for the reason SoftwareUpdate's is: not a MainActor
	// object, and the ObjC++ was a plain function-local static.
	@objc nonisolated(unsafe) static let sharedInstance = OakDocumentController()

	// The C++ registry, behind an ObjC face (rule 25). Created with the
	// controller, as the maps were.
	private let registry = OakDocumentRegistry()

	private var rankedPaths: [String: Int]?
	private var rankedUUIDs: [UUID: Int] = [:]
	private var lastLRURank = 0
	private var saveRankedPathsTimer: Timer?

	@objc override init() {
		super.init()
	}

	// MARK: - The registry

	@objc func untitledDocument() -> OakDocument {
		return document(withPath: nil)
	}

	@objc(documentWithPath:)
	func document(withPath aPath: String?) -> OakDocument {
		return registry.document(forPath: aPath)
	}

	@objc(findDocumentWithIdentifier:)
	func findDocument(withIdentifier anUUID: UUID) -> OakDocument? {
		return registry.document(forIdentifier: anUUID)
	}

	@objc(register:)
	func register(_ aDocument: OakDocument) {
		registry.addDocument(aDocument)
	}

	@objc(unregister:)
	func unregister(_ aDocument: OakDocument) {
		registry.removeDocument(aDocument)
	}

	@objc(update:)
	func update(_ aDocument: OakDocument) {
		registry.updateDocument(aDocument)
	}

	@objc func firstAvailableUntitledCount() -> UInt {
		return registry.firstAvailableUntitledCount()
	}

	@objc func documents() -> [OakDocument] {
		return registry.documents()
	}

	@objc func openDocuments() -> [OakDocument] {
		let array = (documents() as NSArray).filtered(using: NSPredicate(format: "isOpen == YES")) as? [OakDocument] ?? []
		return array.sorted { lhs, rhs in
			if lhs.path == nil && rhs.path == nil {
				return lhs.untitledCount < rhs.untitledCount
			}
			else if let lhsPath = lhs.path, let rhsPath = rhs.path {
				return lhsPath.localizedCompare(rhsPath) == .orderedAscending
			}
			else {
				return lhs.path == nil // untitled before paths
			}
		}
	}

	private func openDocuments(inDirectory aDirectory: String) -> [OakDocument] {
		let array = (documents() as NSArray).filtered(using: NSPredicate(format: "path BEGINSWITH %@ OR directory BEGINSWITH %@", aDirectory, aDirectory)) as? [OakDocument] ?? []
		return array.sorted { lhs, rhs in
			if lhs.untitledCount != rhs.untitledCount {
				return lhs.untitledCount < rhs.untitledCount
			}
			return (lhs.displayName ?? "").localizedCompare(rhs.displayName ?? "") == .orderedAscending
		}
	}

	private func untitledDocuments(inDirectory aDirectory: String) -> [OakDocument] {
		return openDocuments(inDirectory: aDirectory).filter { $0.path == nil }
	}

	// The two window wrappers, -showDocument: and -showDocument:inProject:
	// bringToFront:, are in OakDocumentControllerCxx.mm: they pass a C++ range.

	// MARK: - Last Recently Used

	private func setupRankedPaths() {
		if rankedPaths != nil {
			return
		}

		var ranked: [String: Int] = [:]
		rankedUUIDs = [:]

		var paths = UserDefaults.standard.stringArray(forKey: "LRUDocumentPaths")

		// LEGACY format used by 2.0-beta.12.11 and earlier
		if paths == nil {
			let dictionary = UserDefaults.standard.dictionary(forKey: "LRUDocumentPaths")
			paths = dictionary?["paths"] as? [String]
		}

		for path in (paths ?? []).reversed() {
			lastLRURank += 1
			ranked[path] = lastLRURank
		}
		rankedPaths = ranked
	}

	@objc private func saveRankedPathsTimerDidFire(_ aTimer: Timer) {
		saveRankedPathsTimer = nil

		// Was a std::map keyed by the negated rank: highest rank first, and the
		// first fifty. Ranks are unique, so a sort says the same thing.
		let ordered = (rankedPaths ?? [:]).sorted { $0.value > $1.value }
		var array: [String] = []
		for (path, _) in ordered {
			array.append(path)
			if array.count == 50 {
				break
			}
		}
		UserDefaults.standard.set(array, forKey: "LRUDocumentPaths")
	}

	@objc(lruRankForDocument:)
	func lruRank(for aDocument: OakDocument) -> Int {
		setupRankedPaths()
		if let path = aDocument.path {
			return rankedPaths?[path] ?? 0
		}
		return aDocument.identifier.flatMap { rankedUUIDs[$0] } ?? 0
	}

	@objc(didTouchDocument:)
	func didTouchDocument(_ aDocument: OakDocument?) {
		guard let aDocument else {
			return
		}

		setupRankedPaths()
		lastLRURank += 1
		if let path = aDocument.path {
			rankedPaths?[path] = lastLRURank
		}
		else if let identifier = aDocument.identifier {
			rankedUUIDs[identifier] = lastLRURank
		}

		saveRankedPathsTimer?.invalidate()
		saveRankedPathsTimer = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(saveRankedPathsTimerDidFire(_:)), userInfo: nil, repeats: false)
	}

	// MARK: - Directory Scanning

	@objc(enumerateDocumentsAtPath:options:usingBlock:)
	func enumerateDocuments(atPath aDirectory: String, options someOptions: [AnyHashable: Any]?, using block: @escaping (OakDocument, UnsafeMutablePointer<ObjCBool>) -> Void) {
		enumerateDocuments(atPaths: [ aDirectory ], options: someOptions, using: block)
	}

	@objc(enumerateDocumentsAtPaths:options:usingBlock:)
	func enumerateDocuments(atPaths items: [String], options someOptions: [AnyHashable: Any]?, using block: @escaping (OakDocument, UnsafeMutablePointer<ObjCBool>) -> Void) {
		OakDocumentWalk.enumerateDocuments(atPaths: items, options: someOptions, openDocumentsInDirectory: { directory, ignoreOrdering in
			return ignoreOrdering ? self.openDocuments(inDirectory: directory) : self.untitledDocuments(inDirectory: directory)
		}, using: block)
	}
}
