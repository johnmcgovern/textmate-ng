import AppKit
import Quartz

// -validateMenuItem:, which decides for every item in the action menu whether it
// is enabled, hidden, and what it is called.
//
// It is the single largest method in the controller and it names nearly every
// action in the class by selector, which is why it moves last of the action
// work: each of those selectors has to be visible to Swift first. Three groups
// of them, and where they come from is the whole story of this file:
//
//   * already Swift — the actions peeled in the previous commits;
//   * public header — goBack:/goForward:/newFolder:/toggleShowInvisibles:,
//     which Swift sees because the bridging header imports that header;
//   * still ObjC++ and private — undo:, redo:, toggleQuickLookPreview: and
//     openWithMenuAction:, which had to be declared in
//     FileBrowserViewControllerInternal.h. That is the *reverse* of that
//     header's usual direction and it is safe for exactly one reason: ObjC
//     still implements them. Declaring something Swift defines there would
//     collide.
//
// #selector is used throughout rather than NSSelectorFromString, so that a
// selector this method tests for cannot quietly stop matching the method it
// belongs to — which would show up as a menu item that is always enabled, or
// always hidden, and nothing else.
extension FileBrowserViewController {
	@objc(validateMenuItem:)
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		let selectedItems    = self.selectedItems
		let previewableItems = self.previewableItems

		var res = true
		var hideAndDisable = false

		switch menuItem.action {
			case #selector(FileBrowserViewController.undo(_:)):
				menuItem.title = activeUndoManager?.undoMenuItemTitle ?? ""
				res = activeUndoManager?.canUndo ?? false

			case #selector(FileBrowserViewController.redo(_:)):
				menuItem.title = activeUndoManager?.redoMenuItemTitle ?? ""
				res = activeUndoManager?.canRedo ?? false

			case #selector(FileBrowserViewController.toggleQuickLookPreview(_:)):
				if QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible {
					menuItem.title = "Close Quick Look"
				} else if previewableItems.count == 0 {
					menuItem.isHidden = true
				} else if previewableItems.count == 1 {
					// `?? ""` is not defensive padding: localizedName is `String!`,
					// and interpolating an implicitly unwrapped optional prints
					// `Optional("…")` into the menu. Caught in the app, never by a
					// test — the suite was green with it wrong.
					let name = previewableItems.first!.localizedName ?? ""
					menuItem.title = "Quick Look “\(name)”"
				} else {
					menuItem.title = "Quick Look \(previewableItems.count) Items"
				}

			case #selector(FileBrowserViewController.toggleShowInvisibles(_:)):
				menuItem.setDynamicTitle(showExcludedItems ? "Hide Invisible Files" : "Show Invisible Files")

			case #selector(FileBrowserViewController.goBack(_:)):    res = canGoBack()
			case #selector(FileBrowserViewController.goForward(_:)): res = canGoForward()
			case #selector(FileBrowserViewController.newFolder(_:)): res = directoryURLForNewItems != nil

			case #selector(FileBrowserViewController.openSelectedItems(_:)):
				hideAndDisable = previewableItems.count == 0
			case #selector(FileBrowserViewController.openWithMenuAction(_:)):
				hideAndDisable = previewableItems.count == 0 || (selectedItems.count == 1 && selectedItems.first!.isApplication)
			case #selector(FileBrowserViewController.showSelectedEntriesInFinder(_:)):
				hideAndDisable = previewableItems.count == 0
			case #selector(FileBrowserViewController.showOriginal(_:)):
				hideAndDisable = selectedItems.count != 1 || selectedItems.first!.URL.isEqual(selectedItems.first!.resolvedURL)
			case #selector(FileBrowserViewController.showEnclosingFolder(_:)):
				// Two nil cases here and the ObjC++ answered differently to each.
				// The ?: falls back to the item's own parentURL, which makes the
				// comparison true and hides the item. But if parentURL itself is
				// nil, `[nil isEqual:…]` answered **NO** and the item stayed
				// visible — so the coalesce below is `false`, not `true`. Getting
				// that backwards hides "Show Enclosing Folder" for exactly the
				// items that most need it, and nothing here would fail (rule 33).
				let item = selectedItems.first
				let outlineParent = (outlineView.parent(forItem: item) as? FileItem)?.URL ?? item?.parentURL
				hideAndDisable = selectedItems.count != 1 || (item?.parentURL as NSURL?)?.isEqual(outlineParent) ?? false
			case #selector(FileBrowserViewController.showPackageContents(_:)):
				hideAndDisable = previewableItems.count != 1 || previewableItems.first!.package == false
			case #selector(FileBrowserViewController.editSelectedEntries(_:)):
				hideAndDisable = previewableItems.count != 1 || previewableItems.first!.canRename == false
			case #selector(FileBrowserViewController.addSelectedEntriesToFavorites(_:)):
				hideAndDisable = previewableItems.count == 0 || favoritesDirectoryContains(previewableItems)
			case #selector(FileBrowserViewController.removeSelectedEntriesFromFavorites(_:)):
				hideAndDisable = previewableItems.count == 0 || !favoritesDirectoryContains(previewableItems)
			case #selector(FileBrowserViewController.delete(_:)):
				hideAndDisable = previewableItems.count == 0
			case #selector(FileBrowserViewController.cut(_:)):
				hideAndDisable = previewableItems.count == 0
			case #selector(FileBrowserViewController.copy(_:)):
				hideAndDisable = previewableItems.count == 0
			case #selector(FileBrowserViewController.copyAsPathname(_:)):
				hideAndDisable = previewableItems.count == 0
			case #selector(FileBrowserViewController.paste(_:)):
				hideAndDisable = canPaste() == false
			case #selector(FileBrowserViewController.pasteNext(_:)):
				hideAndDisable = canPaste() == false
			case #selector(FileBrowserViewController.createLinkToPasteboardItems(_:)):
				hideAndDisable = canPaste() == false
			case #selector(FileBrowserViewController.duplicateSelectedEntries(_:)):
				hideAndDisable = previewableItems.count == 0

			default: break
		}

		menuItem.isHidden = hideAndDisable && (menuItem.target as? FileBrowserViewController) === self

		res = res && !hideAndDisable
		guard res else { return res }

		let copyAsPathnameTitle = previewableItems.count > 1 ? "Copy%@ as Pathnames" : "Copy%@ as Pathname"

		let menuTitles: [(format: String, action: Selector)] = [
			( "Cut%@",                   #selector(FileBrowserViewController.cut(_:))                                ),
			( "Copy%@",                  #selector(FileBrowserViewController.copy(_:))                               ),
			( copyAsPathnameTitle,       #selector(FileBrowserViewController.copyAsPathname(_:))                     ),
			( "Show%@ in Finder",        #selector(FileBrowserViewController.showSelectedEntriesInFinder(_:))        ),
			( "Add%@ to Favorites",      #selector(FileBrowserViewController.addSelectedEntriesToFavorites(_:))      ),
			( "Remove%@ From Favorites", #selector(FileBrowserViewController.removeSelectedEntriesFromFavorites(_:)) ),
		]

		let isOurs = (menuItem.target as? FileBrowserViewController) === self

		for info in menuTitles {
			if isOurs && menuItem.action == info.action {
				let items: String
				switch previewableItems.count {
					case 0:  items = " “\(fileItem?.localizedName ?? "")”"
					case 1:  items = " “\(previewableItems.first!.localizedName ?? "")”"
					default: items = " \(previewableItems.count) Items"
				}
				menuItem.updateTitle(String(format: info.format, items))
			}
		}

		guard let directoryURLForNewItems,
		      let folderNameForNewItems = try? directoryURLForNewItems.resourceValues(forKeys: [ .localizedNameKey ]).localizedName else {
			return res
		}

		if menuItem.action == #selector(FileBrowserViewController.newFolder(_:)) {
			menuItem.setDynamicTitle("New Folder in “\(folderNameForNewItems)”")
		}

		if menuItem.action == #selector(FileBrowserViewController.paste(_:)) && isOurs {
			let count = urlsFromPasteboard(NSPasteboard.general).count
			menuItem.setDynamicTitle(count == 1 ? "Paste Item in “\(folderNameForNewItems)”"
			                                    : "Paste \(count) Items in “\(folderNameForNewItems)”")
		} else if menuItem.action == #selector(FileBrowserViewController.pasteNext(_:)) && isOurs {
			let count = urlsFromPasteboard(NSPasteboard.general).count
			menuItem.setDynamicTitle(count == 1 ? "Move Item to “\(folderNameForNewItems)”"
			                                    : "Move \(count) Items to “\(folderNameForNewItems)”")
		} else if menuItem.action == #selector(FileBrowserViewController.createLinkToPasteboardItems(_:)) && isOurs {
			let count = urlsFromPasteboard(NSPasteboard.general).count
			menuItem.setDynamicTitle(count == 1 ? "Create Link in “\(folderNameForNewItems)”"
			                                    : "Create Link to \(count) Items in “\(folderNameForNewItems)”")
		}

		return res
	}
}
