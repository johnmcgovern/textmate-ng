import AppKit

// Every file-system change the browser makes — link, copy, duplicate, move,
// rename, trash, new file, new folder — plus the undo of each, and the outline
// view surgery that keeps the tree matching the disk without a reload.
//
// A category on FileBrowserViewController, so it is a Swift extension on the
// still-ObjC++ class (which the bridging header imports; the category's own
// declaration had to move to FileBrowserDiskOperations.h first, or the two
// spellings of these methods would collide).
//
// The @objc entry points keep their exact ObjC selectors: the controller calls
// performOperation: from eight places, t_file_browser_view_controller.mm pins
// both of its spellings, and the two undo selectors are sent through
// NSUndoManager's invocation proxy, which resolves them by selector at run time.
// Everything else here is internal to this file.
//
// Two things stay in FileBrowserDiskOperationsSupport: the path:: arithmetic and
// the -presentError: override (a Swift extension cannot override an inherited
// method). -addButtons: needed no shim despite being variadic and so uncallable
// from Swift (rule 16) — it is only a loop of -addButtonWithTitle:.
//
// Two pieces of ObjC nil-messaging the ObjC++ relied on, preserved deliberately
// (rule 27) because a literal Swift translation crashes or changes behaviour:
// -undoOperation:… is called with a *nil* sourceURLs array for the operations
// that have no sources (new file, new folder), where `srcURLs[i]` returned nil
// rather than trapping; and each of its results is only collected if non-nil.

// The bookkeeping for one source→destination pair as moveFromURLs(toURLs:)
// resolves it against the tree. A class, not a struct, because the resolution
// passes mutate records already in the array — the `for(auto& r : v)` of the
// ObjC++.
private final class MoveRecord {
	let sourceURL: NSURL
	let destURL: NSURL

	var sourceParent: FileItem?
	var sourceItem: FileItem?
	var destParent: FileItem?

	init(sourceURL: NSURL, destURL: NSURL) {
		self.sourceURL = sourceURL
		self.destURL = destURL
	}
}

// -[NSURL isEqual:], not Swift's URL ==, which normalises differently.
private func sameURL(_ lhs: NSURL?, _ rhs: NSURL?) -> Bool {
	guard let lhs = lhs else { return rhs == nil }
	return lhs.isEqual(rhs)
}

private func parentURL(of url: NSURL) -> NSURL? {
	return (url as URL).deletingLastPathComponent() as NSURL
}

extension FileBrowserViewController {
	@objc(performOperation:withURLs:unique:select:)
	dynamic func performOperation(_ op: FBOperation, withURLs urls: [NSURL: NSURL], unique makeUnique: Bool, select selectDestinationURLs: Bool) -> [NSURL]? {
		var srcURLs: [NSURL] = []
		var destURLs: [NSURL] = []
		for (srcURL, destURL) in urls {
			srcURLs.append(srcURL)
			destURLs.append(destURL)
		}
		return performOperation(op, sourceURLs: srcURLs, destinationURLs: destURLs, unique: makeUnique, select: selectDestinationURLs)
	}

	@objc(performOperation:sourceURLs:destinationURLs:unique:select:)
	dynamic func performOperation(_ op: FBOperation, sourceURLs: [NSURL]?, destinationURLs: [NSURL]?, unique makeUnique: Bool, select selectDestinationURLs: Bool) -> [NSURL]? {
		let srcURLs = sourceURLs ?? []
		var destURLs = destinationURLs ?? []
		if makeUnique {
			destURLs = uniqueDestinationURLs(destURLs)
		}

		let itemDescription = srcURLs.count == 1
			? "“\(FileManager.default.displayName(atPath: srcURLs[0].path ?? ""))”"
			: "\(srcURLs.count) Items"

		var newSrcURLs: [NSURL] = []
		var newDestURLs: [NSURL] = []

		var forceFlag = false

		let total = max(srcURLs.count, destURLs.count)
		var i = 0
		while i < total {
			let srcURL  = i < srcURLs.count  ? srcURLs[i].filePathURL as NSURL?  : nil
			var destURL = i < destURLs.count ? destURLs[i].filePathURL as NSURL? : nil

			var error: NSError?
			var res = performOperation(op, sourceURL: srcURL, destinationURL: &destURL, force: forceFlag, error: &error)
			var skip = false

			if !res, let currentError = error, currentError.domain == NSCocoaErrorDomain {
				if !op.isDisjoint(with: [ .link, .copy, .move ]), currentError.code == NSFileWriteFileExistsError {
					let name = FileManager.default.displayName(atPath: destURL?.path ?? "")

					let alert = NSAlert()
					alert.alertStyle              = .critical
					alert.messageText             = "Do you want to replace “\(name)”?"
					alert.informativeText         = "An item named “\(name)” already exists in the location that you are moving this item to."
					alert.suppressionButton?.title = "Replace All"
					alert.showsSuppressionButton  = i+1 < total
					for title in [ "Replace", "Stop", "Skip" ] {
						alert.addButton(withTitle: title)
					}

					switch alert.runModal() {
						case .alertFirstButtonReturn: // Replace
							forceFlag = alert.suppressionButton?.state == .on
							res = performOperation(op, sourceURL: srcURL, destinationURL: &destURL, force: true, error: &error)
						case .alertSecondButtonReturn: // Stop
							error = nil
							i = total
						case .alertThirdButtonReturn: // Skip
							skip = true
						default:
							break
					}
				} else if op == .trash, currentError.code == NSFeatureUnsupportedError {
					let name = FileManager.default.displayName(atPath: srcURL?.path ?? "")

					let alert = NSAlert()
					alert.alertStyle              = .critical
					alert.messageText             = "Are you sure you want to delete “\(name)”?"
					alert.informativeText         = "This item will be deleted immediately. You can’t undo this action."
					alert.suppressionButton?.title = "Delete All"
					alert.showsSuppressionButton  = i+1 < total
					for title in [ "Delete", "Stop", "Skip" ] {
						alert.addButton(withTitle: title)
					}

					switch alert.runModal() {
						case .alertFirstButtonReturn: // Delete
							forceFlag = alert.suppressionButton?.state == .on
							res = performOperation(op, sourceURL: srcURL, destinationURL: &destURL, force: true, error: &error)
						case .alertSecondButtonReturn: // Stop
							error = nil
							i = total
						case .alertThirdButtonReturn: // Skip
							skip = true
						default:
							break
					}
				}
			}

			if skip {
				i += 1
				continue
			}

			if res {
				if let destURL = destURL {
					if let srcURL = srcURL {
						newSrcURLs.append(srcURL)
					}
					newDestURLs.append(destURL)
				}
			} else if let error = error {
				presentError(error)
			}

			i += 1
		}

		if newDestURLs.isEmpty {
			return nil
		}

		var newItems: [FileItem] = []
		if !op.isDisjoint(with: [ .move, .rename, .trash ]) {
			newItems = moveFromURLs(newSrcURLs, toURLs: newDestURLs)
		} else if !op.isDisjoint(with: [ .link, .copy, .duplicate, .newFile, .newFolder ]) {
			newItems = insertURLs(newDestURLs)
		}

		if !newItems.isEmpty && selectDestinationURLs {
			let newIndexes = NSMutableIndexSet()
			for item in newItems {
				let row = outlineView.row(forItem: item)
				if row != -1 {
					newIndexes.add(row)
				}
			}
			outlineView.selectRowIndexes(newIndexes as IndexSet, byExtendingSelection: false)
		}

		if !op.isDisjoint(with: [ .link, .move, .copy, .duplicate ]) {
			OakPlayUISound(OakSoundDidMoveItemUISound)
		} else if op.contains(.trash) {
			OakPlayUISound(OakSoundDidTrashItemUISound)
		}

		// **Block-based registration, not -prepareWithInvocationTarget:, and the
		// change is forced by the flip.** That method hands back an NSProxy, and
		// the old line cast it with `as? FileBrowserViewController` — which worked
		// only because the proxy forwards -isKindOfClass: to its target and the
		// class was an imported ObjC one. Now that Swift defines the class, the
		// cast is answered from Swift class metadata, reads the proxy's own isa,
		// and fails. The `if let` then does not run: **every operation silently
		// stops being undoable**, with nothing failing and the menu item still
		// enabled. Probed, not guessed — the cast logs FAILED on every operation.
		//
		// -registerUndoWithTarget:handler: has no proxy in it, so there is nothing
		// for a cast to get wrong. Same semantics: the handler runs on undo with
		// the controller as its argument.
		if let undoManager {
			undoManager.registerUndo(withTarget: self) { target in
				target.undoOperation(op, sourceURLs: newSrcURLs.isEmpty ? nil : newSrcURLs, destinationURLs: newDestURLs, select: selectDestinationURLs)
			}
		}

		switch op {
			case .link:      undoManager?.setActionName("Create Link to \(itemDescription)")
			case .copy:      undoManager?.setActionName("Copy of \(itemDescription)")
			case .duplicate: undoManager?.setActionName("Duplicate \(itemDescription)")
			case .move:      undoManager?.setActionName("Move of \(itemDescription)")
			case .rename:    undoManager?.setActionName("Rename \(itemDescription)")
			case .trash:     undoManager?.setActionName("Move of \(itemDescription) to Trash")
			case .newFile:   undoManager?.setActionName("New File")
			case .newFolder: undoManager?.setActionName("New Folder")
			default:         break
		}

		return newDestURLs
	}

	private func performOperation(_ op: FBOperation, sourceURL srcURL: NSURL?, destinationURL destURL: inout NSURL?, force: Bool, error: inout NSError?) -> Bool {
		if force, !op.isDisjoint(with: [ .link, .copy, .move ]), let existing = destURL, FileManager.default.fileExists(atPath: existing.path ?? "") {
			do {
				try FileManager.default.removeItem(at: existing as URL)
			} catch let err as NSError {
				error = err
				return false
			}
		}

		switch op {
			case .link:
				guard let srcURL = srcURL, let destURL = destURL else { return false }
				do {
					if let target = FileBrowserDiskOperationsSupport.symbolicLinkDestination(for: srcURL as URL, at: destURL as URL) {
						try FileManager.default.createSymbolicLink(atPath: destURL.path ?? "", withDestinationPath: target)
					} else {
						try FileManager.default.createSymbolicLink(at: destURL as URL, withDestinationURL: srcURL as URL)
					}
					return true
				} catch let err as NSError {
					error = err
					return false
				}

			case .move, .rename:
				guard let srcURL = srcURL, let destURL = destURL else { return false }
				do {
					try FileManager.default.moveItem(at: srcURL as URL, to: destURL as URL)
					return true
				} catch let err as NSError {
					error = err
					return false
				}

			case .newFile:
				guard let destURL = destURL else { return false }
				return FileManager.default.createFile(atPath: destURL.path ?? "", contents: nil, attributes: nil)

			case .newFolder:
				guard let destURL = destURL else { return false }
				do {
					try FileManager.default.createDirectory(at: destURL as URL, withIntermediateDirectories: false, attributes: nil)
					return true
				} catch let err as NSError {
					error = err
					return false
				}

			case .copy, .duplicate:
				guard let srcURL = srcURL, let destURL = destURL else { return false }
				if FileBrowserDiskOperationsSupport.isURL(destURL as URL, childOf: srcURL as URL) {
					error = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTSUP), userInfo: nil)
					return false
				}

				do {
					try FileManager.default.copyItem(at: srcURL as URL, to: destURL as URL)
				} catch let err as NSError {
					error = err
					return false
				}

				if op == .duplicate {
					NotificationCenter.default.post(name: .FileBrowserDidDuplicate, object: self, userInfo: [ FileBrowserURLDictionaryKey: [ srcURL: destURL ] ])
				}
				return true

			case .trash:
				guard let srcURL = srcURL else { return false }
				NotificationCenter.default.post(name: .FileBrowserWillDelete, object: self, userInfo: [ FileBrowserPathKey: srcURL.path ?? "" ])

				var resultingURL: NSURL?
				do {
					try FileManager.default.trashItem(at: srcURL as URL, resultingItemURL: &resultingURL)
					destURL = resultingURL
					return true
				} catch let err as NSError {
					error = err
					if force, err.domain == NSCocoaErrorDomain, err.code == NSFeatureUnsupportedError {
						do {
							try FileManager.default.removeItem(at: srcURL as URL)
							return true
						} catch let removeError as NSError {
							error = removeError
							return false
						}
					}
					return false
				}

			default:
				return false
		}
	}

	private func uniqueDestinationURLs(_ urls: [NSURL]) -> [NSURL] {
		var res: [NSURL] = []

		var existingURLs = Set<NSURL>()
		for url in urls {
			var destURL = url

			let base = destURL.lastPathComponent ?? ""

			var i = 1
			while existingURLs.contains(destURL) || FileManager.default.fileExists(atPath: destURL.path ?? "") {
				i += 1
				let regex = try? NSRegularExpression(pattern: "^(.*?)(?: \\d+)?(\\.\\w+)?$", options: [])
				let name = regex?.stringByReplacingMatches(in: base, options: [], range: NSMakeRange(0, (base as NSString).length), withTemplate: "$1 \(i)$2") ?? base
				destURL = (destURL as URL).deletingLastPathComponent().appendingPathComponent(name, isDirectory: destURL.hasDirectoryPath) as NSURL
			}
			existingURLs.insert(destURL)
			res.append(destURL)
		}
		return res
	}

	@objc(undoOperation:sourceURLs:destinationURLs:select:)
	dynamic func undoOperation(_ op: FBOperation, sourceURLs: [NSURL]?, destinationURLs: [NSURL]?, select selectDestinationURLs: Bool) {
		let srcURLs = sourceURLs ?? []
		let destURLs = destinationURLs ?? []

		var newSrcURLs: [NSURL] = []
		var newDestURLs: [NSURL] = []

		let total = max(srcURLs.count, destURLs.count)
		for i in 0..<total {
			// nil, not a trap, when the array is shorter — the ObjC++ indexed a
			// nil sourceURLs for the new-file/new-folder undo.
			let srcURL  = i < srcURLs.count  ? srcURLs[i]  : nil
			let destURL = i < destURLs.count ? destURLs[i] : nil

			var error: NSError?
			if undoOperation(op, sourceURL: srcURL, destinationURL: destURL, error: &error) {
				if let srcURL = srcURL {
					newSrcURLs.append(srcURL)
				}
				if let destURL = destURL {
					newDestURLs.append(destURL)
				}
			} else if let error = error {
				presentError(error)
			}
		}

		if !op.isDisjoint(with: [ .move, .rename, .trash ]) {
			_ = moveFromURLs(newDestURLs, toURLs: newSrcURLs)
		} else if !op.isDisjoint(with: [ .link, .copy, .duplicate, .newFile, .newFolder ]) {
			removeURLs(newDestURLs)
		}

		if !op.isDisjoint(with: [ .trash, .move ]) {
			OakPlayUISound(OakSoundDidMoveItemUISound)
		} else if !op.isDisjoint(with: [ .link, .copy, .duplicate, .newFile, .newFolder ]) {
			OakPlayUISound(OakSoundDidTrashItemUISound)
		}

		// The redo half, and the same change for the same reason as above.
		if let undoManager {
			undoManager.registerUndo(withTarget: self) { target in
				_ = target.performOperation(op, sourceURLs: newSrcURLs, destinationURLs: newDestURLs, unique: false, select: selectDestinationURLs)
			}
		}
	}

	private func undoOperation(_ op: FBOperation, sourceURL srcURL: NSURL?, destinationURL destURL: NSURL?, error: inout NSError?) -> Bool {
		if !op.isDisjoint(with: [ .link, .copy, .duplicate, .newFile, .newFolder ]) {
			guard let destURL = destURL else { return false }
			NotificationCenter.default.post(name: .FileBrowserWillDelete, object: self, userInfo: [ FileBrowserPathKey: destURL.path ?? "" ])
			do {
				try FileManager.default.removeItem(at: destURL as URL)
				return true
			} catch let err as NSError {
				error = err
				return false
			}
		} else if !op.isDisjoint(with: [ .move, .rename, .trash ]) {
			guard let srcURL = srcURL, let destURL = destURL else { return false }
			do {
				try FileManager.default.moveItem(at: destURL as URL, to: srcURL as URL)
				return true
			} catch let err as NSError {
				error = err
				return false
			}
		}
		return false
	}

	// ========================
	// = Update NSOutlineView =
	// ========================

	private func removeURLs(_ urls: [NSURL]) {
		removeURLs(Set(urls), inParent: fileItem, rearrange: true, removeInChildren: true)
	}

	private func removeURLs(_ urls: Set<NSURL>, inParent parent: FileItem?, rearrange rearrangeFlag: Bool) {
		removeURLs(urls, inParent: parent, rearrange: rearrangeFlag, removeInChildren: false)
	}

	private func removeURLs(_ urls: Set<NSURL>, inParent parent: FileItem?, rearrange rearrangeFlag: Bool, removeInChildren recursive: Bool) {
		guard let parent = parent else { return }

		var indexesToRemove: [Int] = []
		for (i, child) in (parent.children ?? []).enumerated() {
			if let url = child.URL, urls.contains(url) {
				indexesToRemove.append(i)
			}
		}

		if !indexesToRemove.isEmpty {
			var children = parent.children ?? []
			for i in indexesToRemove.reversed() {
				children.remove(at: i)
			}
			parent.children = children

			if rearrangeFlag {
				rearrangeChildren(inParent: parent)
			}
		}

		if recursive {
			for child in parent.children ?? [] {
				if child.children != nil {
					removeURLs(urls, inParent: child, rearrange: rearrangeFlag, removeInChildren: recursive)
				}
			}
		}
	}

	private func insertURLs(_ urls: [NSURL]) -> [FileItem] {
		var newItems: [FileItem] = []

		for parent in parentsWithFileURL() {
			let parentItemURL = parent.resolvedURL

			var urlsToInsert: [NSURL] = []
			for url in urls {
				if sameURL(parentURL(of: url), parentItemURL) {
					urlsToInsert.append(url)
				}
			}

			if !urlsToInsert.isEmpty {
				removeURLs(Set(urls), inParent: parent, rearrange: false)
				var children = parent.children ?? []

				for url in urlsToInsert {
					if let newItem = FileItem.fileItem(withURL: url) {
						newItem.missing = false
						children.append(newItem)
						newItems.append(newItem)
					}
				}

				parent.children = children
				rearrangeChildren(inParent: parent)
			}
		}

		return newItems
	}

	private func moveFromURLs(_ fromURLs: [NSURL], toURLs: [NSURL]) -> [FileItem] {
		var newItems: [FileItem] = []

		var v: [MoveRecord] = []
		for i in 0..<fromURLs.count {
			v.append(MoveRecord(sourceURL: fromURLs[i], destURL: toURLs[i]))
		}

		var urlsToRemove: [NSURL] = []
		var urlsToInsert: [NSURL] = []

		for parent in parentsWithFileURL() {
			let parentItemURL = parent.resolvedURL

			for r in v {
				if sameURL(parentURL(of: r.sourceURL), parentItemURL) {
					r.sourceParent = parent
					for case let item as FileItem in (parent.arrangedChildren ?? []) {
						if sameURL(item.URL, r.sourceURL) {
							r.sourceItem = item
							break
						}
					}
				}

				if sameURL(parentURL(of: r.destURL), parentItemURL) {
					r.destParent = parent
				}
			}
		}

		for r in v {
			if r.sourceParent == nil, r.destParent == nil, sameURL(parentURL(of: r.sourceURL), parentURL(of: r.destURL)) {
				var stack = fileItem?.children ?? []
				while let parent = stack.first {
					stack.remove(at: 0)
					for child in parent.children ?? [] {
						if sameURL(child.URL, r.sourceURL) {
							r.sourceItem   = child
							r.sourceParent = parent
							r.destParent   = parent
							break
						}

						if child.children != nil {
							stack.append(child)
						}
					}

					if r.sourceItem != nil {
						break
					}
				}
			}
		}

		guard let compare = itemComparator() else { return newItems }
		for r in v {
			guard let destParent = r.destParent else {
				urlsToRemove.append(r.sourceURL)
				continue
			}

			guard let sourceItem = r.sourceItem, let sourceParent = r.sourceParent else {
				urlsToInsert.append(r.destURL)
				continue
			}

			removeURLs([ r.destURL ], inParent: destParent, rearrange: true)

			let oldIndex = sourceParent.arrangedChildren?.index(of: sourceItem) ?? NSNotFound
			if oldIndex == NSNotFound {
				urlsToInsert.append(r.destURL)
			} else {
				var children = sourceParent.children ?? []
				if let at = children.firstIndex(where: { $0 === sourceItem }) {
					children.remove(at: at)
				}
				sourceParent.children = children

				sourceParent.arrangedChildren?.removeObject(at: oldIndex)

				sourceItem.URL = r.destURL
				newItems.append(sourceItem)

				var newIndex = 0
				while newIndex < (destParent.arrangedChildren?.count ?? 0) {
					if compare(sourceItem, destParent.arrangedChildren![newIndex]) == .orderedAscending {
						break
					}
					newIndex += 1
				}

				destParent.arrangedChildren?.insert(sourceItem, at: newIndex)
				destParent.children = (destParent.children ?? []) + [ sourceItem ]

				outlineView.moveItem(at: oldIndex, inParent: sourceParent !== fileItem ? sourceParent : nil, to: newIndex, inParent: destParent !== fileItem ? destParent : nil)
			}
		}

		if !urlsToRemove.isEmpty {
			removeURLs(urlsToRemove)
		}

		if !urlsToInsert.isEmpty {
			newItems.append(contentsOf: insertURLs(urlsToInsert))
		}

		return newItems
	}

	private func parentsWithFileURL() -> [FileItem] {
		guard let root = fileItem else { return [] }

		var parents: [FileItem] = [ root ]

		var stack = root.children ?? []
		while let item = stack.first {
			stack.remove(at: 0)
			guard let children = item.children else { continue }
			if item.URL?.isFileURL == true {
				parents.append(item)
			}
			stack.append(contentsOf: children)
		}

		return parents
	}
}
