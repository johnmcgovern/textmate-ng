import AppKit

// Accepting a drop onto the browser: deciding what a drag would do (move, copy
// or link), performing it, and the outline view's report that it trashed
// something itself.
//
// Third section peeled off FileBrowserViewController. The class is still
// ObjC++; this is a Swift extension on it, and every entry point keeps its ObjC
// selector because all three are reached by selector — the first two by AppKit
// through NSOutlineViewDataSource, the third by FileBrowserOutlineView.swift
// through FileBrowserOutlineViewDelegate.
//
// Both of those conformances stay declared on the class extension in the .mm,
// out of Swift's sight. That is deliberate and it is what lets these compile:
// when Swift can see both a protocol *and* the class's conformance to it, the
// protocol's own member counts as a previous declaration of the selector and
// the witness stops compiling — see the note in FileBrowserViewControllerInternal.h.

// Which single operation a drag's mask means, in the order the browser prefers
// them. Moved verbatim from a file-static in the .mm.
private func filter(_ mask: NSDragOperation) -> NSDragOperation {
	return mask.contains(.move) ? .move : (mask.contains(.copy) ? .copy : (mask.contains(.link) ? .link : []))
}

extension FileBrowserViewController {
	@objc(outlineView:validateDrop:proposedItem:proposedChildIndex:)
	func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: FileItem?, proposedChildIndex childIndex: Int) -> NSDragOperation {
		let parent: FileItem? = item ?? fileItem
		guard let dropURL = parent?.resolvedURL.filePathURL,
		      self.outlineView.isExpandable(item),
		      FileManager.default.fileExists(atPath: dropURL.path) else {
			return []
		}

		// NSFilenamesPboardType is `nonswift` in AppKit's apinotes ("use
		// 'PasteboardType.fileURL'"), so the constant cannot be named here at all
		// — only its raw value, which is the literal string (checked, not
		// assumed). Spelled out rather than modernised on the way past: swapping
		// to fileURL items would change which drags this accepts, and that is a
		// change to make deliberately, not inside a port (rule 6).
		let pboard = info.draggingPasteboard
		let draggedPaths = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] ?? []

		let targetDevice     = FileBrowserViewControllerSupport.device(forURL: dropURL)
		let modifierFlags    = NSApp.currentEvent?.modifierFlags ?? []
		let linkOperation    = modifierFlags.contains(.control)
		let toggleOperation  = modifierFlags.contains(.option)

		// We accept the drop as long as it is valid for at least one of the items
		for draggedPath in draggedPaths {
			let sameSource = FileBrowserViewControllerSupport.device(forPath: draggedPath) == targetDevice
			let operation: NSDragOperation = linkOperation ? .link : ((sameSource != toggleOperation) ? .move : .copy)

			// Can’t move into same location
			let parentPath = (draggedPath as NSString).deletingLastPathComponent
			if operation == .move && parentPath == dropURL.path {
				continue
			}

			outlineView.setDropItem(item, dropChildIndex: NSOutlineViewDropOnItemIndex)
			return operation
		}
		return []
	}

	@objc(outlineView:acceptDrop:item:childIndex:)
	func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: FileItem?, childIndex: Int) -> Bool {
		let newParent: FileItem? = item ?? fileItem
		let op = filter(info.draggingSourceOperationMask)
		guard op != [], let newParent, self.outlineView.isExpandable(newParent), newParent.resolvedURL.isFileURL else {
			return false
		}

		// -URLsFromPasteboard: declares NSArray<NSURL*>*, which bridges to [URL],
		// while performOperation's dictionary is keyed by NSURL — so each end
		// converts explicitly rather than relying on where the bridge happens to
		// land.
		var urls: [NSURL: NSURL] = [:]
		for url in urlsFromPasteboard(info.draggingPasteboard) {
			let isDirectory = op != .link && url.hasDirectoryPath
			if let dest = newParent.resolvedURL.appendingPathComponent(url.lastPathComponent, isDirectory: isDirectory) {
				urls[url as NSURL] = dest as NSURL
			}
		}

		switch op {
			case .link: _ = performOperation(.link, withURLs: urls, unique: false, select: false)
			case .copy: _ = performOperation(.copy, withURLs: urls, unique: false, select: false)
			case .move: _ = performOperation(.move, withURLs: urls, unique: false, select: false)
			default:    break
		}

		return true
	}

	@objc(outlineView:didTrashURLs:)
	func outlineView(_ outlineView: NSOutlineView, didTrashURLs someURLs: [NSURL]) {
		_ = performOperation(.trash, sourceURLs: someURLs, destinationURLs: nil, unique: false, select: false)
	}
}
