import Foundation

// The folder search's driver: enumerate documents on a background queue,
// accumulate matches, hand them to the UI in batches from a poll timer on the
// main thread.
//
// FFDocumentSearch.h stays hand-written and is deliberately absent from
// Find-Bridging-Header.h, the TMFileReference arrangement. The C++ half — the
// settings-driven glob dictionary, the one call that still speaks
// find::options_t, and the two exported notification names — is in
// FFDocumentSearchSupport.mm.
//
// @unchecked Sendable, and honestly so: the enumeration block reads
// `lastSearchToken` and writes the scanned counters from a global queue with no
// synchronisation whatsoever. That is exactly what the ObjC++ did, and the port
// is not the place to change it — only `matches` was ever guarded, and it still
// is. Recorded rather than quietly fixed.
@objc(FFDocumentSearch)
final class FFDocumentSearch: NSObject, @unchecked Sendable {

	@objc var searchString: String?
	@objc var options: FFFindOptions = []
	@objc var paths: [String]?
	@objc var glob: String?

	@objc var searchFolderLinks = false
	@objc var searchFileLinks = false
	@objc var searchBinaryFiles = false
	@objc var searchHiddenFolders = false

	// `dynamic` is load-bearing: Find observes this key path
	// (Find.swift's -setDocumentSearch:) to show which folder is being scanned.
	// A plain `@objc`
	// property emits no KVO notifications, so the status line would simply stop
	// updating — silently, and only in the running app.
	@objc dynamic private(set) var currentPath: String?

	@objc private(set) var searchDuration: TimeInterval = 0
	@objc private(set) var scannedFileCount: UInt = 0
	@objc private(set) var scannedByteCount: UInt = 0

	private var searching = false
	private var lastSearchToken: UInt = 0
	private var pollTimer: Timer?
	private let pollInterval: TimeInterval = 0.2
	private var lastDocumentPath: String?

	// An NSMutableArray rather than a Swift array, deliberately: -updateMatches:
	// posts *this object* and then empties it, and a Swift array would bridge to
	// a fresh NSArray in the userInfo, quietly changing what observers see.
	// Pinned by test_the_delivered_array_is_emptied_after_posting.
	private var matches = NSMutableArray()

	// Stands in for the ObjC++ @synchronized(self); nothing outside this class
	// ever synchronised on the instance.
	private let matchesLock = NSLock()

	// ==========
	// = Search =
	// ==========

	@objc func start() {
		stop()

		matchesLock.lock()
		matches = NSMutableArray()
		matchesLock.unlock()

		// Always false — -stop just cleared it. Kept because the ObjC++ had it
		// and removing it is a change to reason about, not a tidy-up.
		if searching {
			lastSearchToken += 1
		}

		searching = true
		pollTimer = Timer.scheduledTimer(timeInterval: pollInterval, target: self, selector: #selector(updateMatches(_:)), userInfo: nil, repeats: false)

		let searchToken = lastSearchToken
		let searchStartDate = Date()
		let searchPaths = paths ?? []

		let options = NSMutableDictionary(dictionary: FFGlobOptionsForPath(CommonAncestor(searchPaths), glob, searchBinaryFiles, searchHiddenFolders))
		options[kSearchFollowFileLinksKey] = searchFileLinks
		options[kSearchFollowDirectoryLinksKey] = searchFolderLinks
		options[kSearchDepthFirstSearchKey] = true

		let needle = searchString
		let findOptions = self.options

		DispatchQueue.global(qos: .default).async { [self] in
			OakDocumentController.sharedInstance.enumerateDocuments(atPaths: searchPaths, options: options as? [AnyHashable: Any]) { document, stop in
				let cancelled = searchToken != self.lastSearchToken
				stop?.pointee = ObjCBool(cancelled)
				if cancelled {
					return
				}

				self.lastDocumentPath = document?.path

				var bufferSize: UInt = 0
				let newMatches = FFMatchesInDocument(document, needle, findOptions, &bufferSize)
				self.scannedByteCount += bufferSize
				self.scannedFileCount += 1

				if let newMatches, !newMatches.isEmpty {
					self.matchesLock.lock()
					self.matches.addObjects(from: newMatches)
					self.matchesLock.unlock()
				}
			}

			DispatchQueue.main.async { [self] in
				if searchToken == lastSearchToken {
					searching = false
					searchDuration = Date().timeIntervalSince(searchStartDate)
					updateMatches(nil)
					NotificationCenter.default.post(name: .FFDocumentSearchDidFinish, object: self)
				}
			}
		}
	}

	// ===================
	// = Scanner Probing =
	// ===================

	@objc private func updateMatches(_ timer: Timer?) {
		currentPath = (lastDocumentPath as NSString?)?.deletingLastPathComponent

		matchesLock.lock()
		if matches.count != 0 {
			NotificationCenter.default.post(name: .FFDocumentSearchDidReceiveResults, object: self, userInfo: [ "matches": matches ])
			matches.removeAllObjects()
		}
		matchesLock.unlock()

		if searching {
			pollTimer = Timer.scheduledTimer(timeInterval: pollInterval, target: self, selector: #selector(updateMatches(_:)), userInfo: nil, repeats: false)
		} else {
			stop()
		}
	}

	@objc func stop() {
		if searching {
			searching = false
			lastSearchToken += 1
		}

		pollTimer?.invalidate()
		pollTimer = nil

		matchesLock.lock()
		matches.removeAllObjects()
		matchesLock.unlock()
	}
}
