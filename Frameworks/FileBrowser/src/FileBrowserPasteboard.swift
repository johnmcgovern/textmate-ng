import AppKit

// Cut, copy, paste and their variants, plus the two predicates the menu
// validation asks about a selection.
//
// The rest of the action methods moved in the previous commit; these came
// separately because they are a closed set — every one of them is either a
// pasteboard reader or a pasteboard writer, and -validateMenuItem: (which moves
// with them) is the only other caller of -canPaste and
// -favoritesDirectoryContainsItems:.
//
// With -URLsFromPasteboard: now here, its declaration leaves
// FileBrowserViewControllerInternal.h: that header is in the bridging header,
// and a method Swift defines must not be declared where Swift can see the
// declaration too.
extension FileBrowserViewController {
	@objc(writeItems:toPasteboard:)
	func writeItems(_ items: [FileItem], toPasteboard pboard: NSPasteboard) -> Bool {
		if items.isEmpty {
			return false
		}

		pboard.clearContents()
		pboard.writeObjects(items.map { $0.URL })

		// If we use writeObjects: then Terminal.app will paste both URLs and their fallback strings
		if pboard.availableType(from: [ .string ]) == nil {
			pboard.setString(items.map { $0.localizedName ?? "" }.joined(separator: "\n"), forType: .string)
		}

		return true
	}

	@objc(cut:)
	func cut(_ sender: Any?) {
		let pboard = NSPasteboard.general
		if writeItems(previewableItems, toPasteboard: pboard) {
			pboard.setString("cut", forType: NSPasteboard.PasteboardType("OakFileBrowserOperation"))
		}
	}

	@objc(copy:)
	func copy(_ sender: Any?) {
		_ = writeItems(previewableItems, toPasteboard: NSPasteboard.general)
	}

	@objc(copyAsPathname:)
	func copyAsPathname(_ sender: Any?) {
		let pathnames = previewableItems.compactMap { $0.URL.path }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.writeObjects(pathnames as [NSString])
	}

	@objc(paste:)
	func paste(_ sender: Any?) {
		let operationType = NSPasteboard.PasteboardType("OakFileBrowserOperation")
		let hasOperation = NSPasteboard.general.availableType(from: [ operationType ]) == operationType
		let cut = hasOperation && NSPasteboard.general.string(forType: operationType) == "cut"
		insertItemsFromPasteboard(with: cut ? .move : .copy)
	}

	@objc(pasteNext:)
	func pasteNext(_ sender: Any?) {
		// We use pasteNext: so that this action is triggered by ⌥⌘V
		insertItemsFromPasteboard(with: .move)
	}

	@objc(createLinkToPasteboardItems:)
	func createLinkToPasteboardItems(_ sender: Any?) {
		insertItemsFromPasteboard(with: .link)
	}

	@objc(insertItemsFromPasteboardWithOperation:)
	func insertItemsFromPasteboard(with operation: FBOperation) {
		guard let directoryURL = directoryURLForNewItems else { return }

		var urls: [NSURL: NSURL] = [:]
		for srcURL in urlsFromPasteboard(NSPasteboard.general) {
			var srcIsDirectory: ObjCBool = false
			if FileManager.default.fileExists(atPath: srcURL.path, isDirectory: &srcIsDirectory) {
				let destURL = directoryURL.appendingPathComponent(srcURL.lastPathComponent, isDirectory: srcIsDirectory.boolValue)
				if !(srcURL as NSURL).isEqual(destURL) || operation != .move {
					urls[srcURL as NSURL] = destURL as NSURL
				}
			}
		}
		_ = performOperation(operation, withURLs: urls, unique: true, select: true)
	}

	@objc(URLsFromPasteboard:)
	func urlsFromPasteboard(_ pboard: NSPasteboard) -> [URL] {
		return pboard.readObjects(forClasses: [ NSURL.self ], options: nil) as? [URL] ?? []
	}

	@objc(favoritesDirectoryContainsItems:)
	func favoritesDirectoryContains(_ items: [FileItem]) -> Bool {
		for item in items {
			// -[NSURL isEqual:], not URL ==, matching the ObjC++ and rule 33.
			if kURLLocationFavorites.isEqual(item.parentURL) {
				return true
			}
		}
		return false
	}

	@objc(canPaste)
	func canPaste() -> Bool {
		return directoryURLForNewItems != nil && !urlsFromPasteboard(NSPasteboard.general).isEmpty
	}
}
