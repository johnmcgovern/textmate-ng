import AppKit

// The action methods: what the context menu, the menu bar and the key bindings
// invoke — reveal, rename, favourites, duplicate, trash, Finder tags, and
// running a bundle command.
//
// Fourth section peeled off FileBrowserViewController, and the first that could
// not take its whole section. Two of the actions it *looks* like it should
// include, -newFile: and -newFolder:, stay in the ObjC++ for a reason worth
// stating once here:
//
//   **A method declared in FileBrowserViewController.h cannot be defined in
//   Swift while the class is still ObjC++.** That header is in this framework's
//   bridging header — it has to be, since Swift extends the class — so defining
//   one of its declared methods here would give the selector two declarations
//   and collide, exactly as FileBrowserDiskOperations.h was split out to avoid.
//   DiskOperations could split cleanly because nothing outside the framework
//   called performOperation:; newFile:/newFolder: are called by
//   DocumentWindowController.swift through that same public header, so there is
//   nowhere to move the declaration to. They wait for the flip.
//
// Everything below is private to the class and reached only by selector, which
// is why it can move now — and why every selector is spelled out with @objc(...).
extension FileBrowserViewController {
	@objc(openSelectedItems:)
	func openSelectedItems(_ sender: Any?) {
		openItems(selectedItems, animate: true)
	}

	@objc(showOriginal:)
	func showOriginal(_ sender: Any?) {
		guard let resolvedURL = selectedItems.first?.resolvedURL else { return }
		// -getResourceValue:forKey:error: takes an autoreleasing out-parameter
		// that Swift cannot spell comfortably; the URL-struct resourceValues form
		// is the same query and the same key.
		if let parentURL = try? (resolvedURL as URL).resourceValues(forKeys: [ .parentDirectoryURLKey ]).parentDirectory {
			go(to: parentURL)
			expandURLs(nil, selectURLs: [ resolvedURL as URL ])
		}
	}

	@objc(showEnclosingFolder:)
	func showEnclosingFolder(_ sender: Any?) {
		guard let url = selectedItems.first?.URL,
		      let enclosingFolder = url.deletingLastPathComponent else { return }
		go(to: enclosingFolder as URL)
		expandURLs(nil, selectURLs: [ url as URL ])
	}

	@objc(showPackageContents:)
	func showPackageContents(_ sender: Any?) {
		guard let url = previewableItems.first?.resolvedURL else { return }
		go(to: url as URL)
	}

	@objc(showSelectedEntriesInFinder:)
	func showSelectedEntriesInFinder(_ sender: Any?) {
		NSWorkspace.shared.activateFileViewerSelecting(previewableItems.map { $0.resolvedURL as URL })
	}

	@objc(editSelectedEntries:)
	func editSelectedEntries(_ sender: Any?) {
		let items = previewableItems
		guard items.count == 1, let item = items.first, item.canRename else { return }

		let row = outlineView.row(forItem: item)
		if row != -1 {
			NSApp.activate(ignoringOtherApps: true)
			outlineView.window?.makeKey()
			outlineView.editColumn(0, row: row, with: nil, select: true)
		}
	}

	@objc(addSelectedEntriesToFavorites:)
	func addSelectedEntriesToFavorites(_ sender: Any?) {
		let url = kURLLocationFavorites!
		do {
			try FileManager.default.createDirectory(at: url as URL, withIntermediateDirectories: true, attributes: nil)
		} catch let error {
			view.window?.presentError(error)
			return
		}

		for item in previewableItems {
			let linkURL = url.appendingPathComponent(item.localizedName)
			do {
				try FileManager.default.createSymbolicLink(at: linkURL!, withDestinationURL: item.resolvedURL as URL)
			} catch let error {
				view.window?.presentError(error)
			}
		}
	}

	@objc(removeSelectedEntriesFromFavorites:)
	func removeSelectedEntriesFromFavorites(_ sender: Any?) {
		for item in previewableItems {
			do {
				try FileManager.default.trashItem(at: item.URL as URL, resultingItemURL: nil)
			} catch let error {
				view.window?.presentError(error)
			}
		}
	}

	@objc(executeBundleCommand:)
	func executeBundleCommand(_ sender: Any?) {
		FileBrowserViewControllerSupport.executeBundleCommand(withUUIDString: (sender as? NSMenuItem)?.representedObject as? String, firstResponder: self)
	}

	@objc(duplicateSelectedEntries:)
	func duplicateSelectedEntries(_ sender: Any?) {
		let items = previewableItems

		var urls: [NSURL: NSURL] = [:]
		if items.count == 1, let url = items.first?.URL {
			let base = url.lastPathComponent ?? ""
			var newBase: String?

			let dateRegex   = try? NSRegularExpression(pattern: "(\\b|_)[1-2][0-9]{3}(-|_|)(?!00|1[3-9])[0-1][0-9]\\2(?!00|3[2-9])[0-3][0-9](\\b|_)", options: [])
			let numberRegex = try? NSRegularExpression(pattern: "^\\d{2,}", options: [])

			let fullRange = NSRange(location: 0, length: (base as NSString).length)
			if let dateRegex, let match = dateRegex.firstMatch(in: base, options: [], range: fullRange) {
				let dateFormatter = DateFormatter()
				let separator = (base as NSString).substring(with: match.range(at: 2))
				dateFormatter.dateFormat = "yyyy\(separator)MM\(separator)dd"
				let template = "$1\(dateFormatter.string(from: Date()))$3"
				let replacement = dateRegex.replacementString(for: match, in: base, offset: 0, template: template)
				newBase = (base as NSString).replacingCharacters(in: match.range, with: replacement)
			} else if let numberRegex, let match = numberRegex.firstMatch(in: base, options: [], range: fullRange) {
				// std::set<NSInteger> in the ObjC++ — local scratch with no C++
				// dependency, so it translates straight rather than needing a
				// boundary.
				var set = Set<Int>()
				let contents = (try? FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent ?? (url as URL), includingPropertiesForKeys: nil, options: [])) ?? []
				for otherURL in contents {
					let otherBase = otherURL.lastPathComponent
					let otherRange = NSRange(location: 0, length: (otherBase as NSString).length)
					if let tmp = numberRegex.firstMatch(in: otherBase, options: [], range: otherRange) {
						set.insert(Int((otherBase as NSString).substring(with: tmp.range)) ?? 0)
					}
				}

				var i = (Int((base as NSString).substring(with: match.range)) ?? 0) + 1
				while set.contains(i) {
					i += 1
				}

				let number = String(format: "%0*ld", Int32(match.range.length), i)
				newBase = (base as NSString).replacingCharacters(in: match.range, with: number)
			}

			// NSURL.deletingLastPathComponent bridges to a `URL?`, and URL's own
			// appendingPathComponent is non-optional — so only the first is bound.
			if let newBase, newBase != base, let parent = url.deletingLastPathComponent {
				urls[url] = parent.appendingPathComponent(newBase, isDirectory: url.hasDirectoryPath) as NSURL
			}
		}

		if urls.isEmpty {
			let regex = try? NSRegularExpression(pattern: "^(.*?)(?: copy(?: \\d+)?)?(\\.\\w+)?$", options: [])
			for item in items {
				let base = item.URL.lastPathComponent ?? ""
				let range = NSRange(location: 0, length: (base as NSString).length)
				guard let name = regex?.stringByReplacingMatches(in: base, options: [], range: range, withTemplate: "$1 copy$2"),
				      let parent = item.URL.deletingLastPathComponent else { continue }
				urls[item.URL] = parent.appendingPathComponent(name, isDirectory: item.isDirectory) as NSURL
			}
		}

		_ = performOperation(.duplicate, withURLs: urls, unique: true, select: true)
		if urls.count == 1 && outlineView.numberOfSelectedRows == 1 {
			outlineView.editColumn(0, row: outlineView.selectedRow, with: nil, select: true)
		}
	}

	@objc(delete:)
	func delete(_ sender: Any?) {
		let outlineView = self.outlineView!

		let selectedRowIndexes = outlineView.selectedRowIndexes
		let clickedRow = outlineView.clickedRow

		// User right-clicked a single item that is not part of the selection, only delete that item
		if clickedRow != -1 && !selectedRowIndexes.contains(clickedRow) {
			if let item = outlineView.item(atRow: clickedRow) as? FileItem, let url = item.URL.filePathURL {
				_ = performOperation(.trash, sourceURLs: [ url as NSURL ], destinationURLs: nil, unique: false, select: false)
			}
			return
		}

		var urlsToTrash: [NSURL] = []
		var selectItem: FileItem?
		var previousItem: FileItem?

		var stack = (fileItem?.arrangedChildren as? [FileItem]) ?? []
		while let item = stack.first {
			stack.removeFirst()

			let url = item.URL.filePathURL
			if let url, selectedRowIndexes.contains(outlineView.row(forItem: item)) {
				selectItem = previousItem
				urlsToTrash.append(url as NSURL)
			} else {
				previousItem = item
				if outlineView.isItemExpanded(item) {
					stack = ((item.arrangedChildren as? [FileItem]) ?? []) + stack
				}
			}
		}

		_ = performOperation(.trash, sourceURLs: urlsToTrash, destinationURLs: nil, unique: false, select: false)

		let fallback = (fileItem?.arrangedChildren as? [FileItem])?.first
		let selectRow = outlineView.row(forItem: selectItem ?? fallback)
		if selectRow != -1 {
			outlineView.selectRowIndexes(IndexSet(integer: selectRow), byExtendingSelection: false)
			outlineView.scrollRowToVisible(selectRow)
		}
	}

	@objc(didChangeFinderTag:)
	func didChangeFinderTag(_ finderTagsChooser: OFBFinderTagsChooser) {
		guard let chosenTag = finderTagsChooser.chosenTag else { return }
		for item in previewableItems {
			var tags = item.finderTags ?? []
			if finderTagsChooser.removeChosenTag {
				tags.removeAll { $0 == chosenTag }
			} else if !tags.contains(chosenTag) {
				tags.append(chosenTag)
			}

			try? item.URL.setResourceValue(tags.map { $0.displayName }, forKey: .tagNamesKey)
			item.finderTags = OakFinderTagManager.finderTags(for: item.URL as URL)
		}
	}
}
