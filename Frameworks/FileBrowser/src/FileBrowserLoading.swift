import AppKit

// Loading a directory's children and keeping the outline view's expansion in
// step with them: the observer that delivers a directory's contents, the merge
// of what came back into the items already on screen, the pending
// expand/select sets that survive a load, and the four nesting counters that
// tell an expand-all from an ordinary expand.
//
// Seventh section peeled, and the one the ivar promotion was really for —
// twelve of these thirteen methods touched an ivar.
//
// **The pending sets are `pendingExpandedURLs` / `pendingSelectedURLs`, never
// `expandedURLs` / `selectedURLs`.** The latter pair merge in what the outline
// view currently shows; this file means the pending sets every time. Getting
// that wrong is not a subtle difference — the first draft of this file did, and
// collapsing a folder sent -removeObject: to an immutable NSSet and crashed
// (rule 46, `d680bbe5`).
//
// Since the flip they are simply four different declarations on the Swift class
// rather than an ivar and an accessor sharing a name, so the mistake is no
// longer available to make. -setFileItem: is in that class too now, and is
// still the one place that deliberately merges the two.
extension FileBrowserViewController {
	@objc(outlineViewItemDidExpand:)
	func outlineViewItemDidExpand(_ aNotification: Notification) {
		let item = aNotification.userInfo?["NSObject"] as? FileItem
		loadChildren(for: item, expandChildren: expandingChildrenCounter > 0)
		invalidateRestorableState()
	}

	@objc(loadChildrenForItem:expandChildren:)
	func loadChildren(for item: FileItem?, expandChildren flag: Bool) {
		guard let item, item.arrangedChildren == nil && item.children == nil else { return }

		let url = item.URL!

		if fileItemObservers?[url] != nil {
			// ================
			// = Debug Output =
			// ================

			var itemInfo: [String] = []

			var stack: [FileItem] = fileItem.map { [ $0 ] } ?? []
			while let item = stack.first {
				stack.removeFirst()
				// Bound once and non-optional: FileItem.URL imports as `NSURL!`,
				// and NSMutableSet/NSMutableDictionary take `Any`, so passing the
				// IUO straight in wraps it in an Optional rather than unwrapping
				// it — every lookup below would silently miss (rule 44).
				if let itemURL = item.URL, item.isDirectory {
					var info = itemURL.path ?? ""
					if item === fileItem || outlineView.isItemExpanded(item) {
						info += " [expanded]"
					}
					if fileItemObservers?[itemURL] != nil {
						info += " [observing]"
					}
					if loadingURLs?.contains(itemURL) ?? false {
						info += " [loading]"
					}
					if item.arrangedChildren != nil || item.children != nil {
						info += " [\(item.arrangedChildren?.count ?? 0) / \(item.children?.count ?? 0) children]"
					}
					itemInfo.append(info)
				}

				if let children = item.arrangedChildren as? [FileItem] {
					stack.append(contentsOf: children)
				}
			}

			NSLog("%@ *** Observer already exists for: %@\n%@", #function, url, itemInfo.joined(separator: "\n"))

			// ===================================
			// = Temporary (possible) workaround =
			// ===================================

			if let observer = fileItemObservers?[url] {
				FileItem.removeObserver(observer)
			}
			fileItemObservers?[url] = nil
		}

		loadingURLs?.add(url)

		fileItemObservers?[url] = FileItem.addObserverToDirectory(at: item.resolvedURL, usingBlock: { [weak self] urls in
			self?.didReceiveURLs(urls, forItemWithURL: url, expandChildren: flag)
		})
	}

	@objc(findItemForURL:)
	func findItem(forURL url: NSURL) -> FileItem? {
		var stack: [FileItem] = fileItem.map { [ $0 ] } ?? []
		while let item = stack.first {
			stack.removeFirst()
			// -[NSURL isEqual:], not URL == (rule 33): these are FileItem URLs.
			if item.URL.isEqual(url) {
				return item
			}
			if let children = item.arrangedChildren as? [FileItem] {
				stack.append(contentsOf: children)
			}
		}
		return nil
	}

	@objc(didReceiveURLs:forItemWithURL:expandChildren:)
	func didReceiveURLs(_ incomingURLs: [URL], forItemWithURL url: NSURL, expandChildren flag: Bool) {
		// **`map`, not `as [NSURL]`.** The observer hands back `[URL]`, and writing
		// `urls as [NSURL]` compiles and then crashes: the array cast does not
		// convert the elements, so Swift `URL` values reach the ObjC APIs below
		// (+fileItemWithURL: among them) and die on an unrecognised selector. The
		// suite cannot see this — nothing there drives a real observer — and the
		// app crashed on the first file added to an expanded folder.
		var urls = incomingURLs.map { $0 as NSURL }
		let item = findItem(forURL: url)

		if item == nil {
			NSLog("%@ *** unable to find item for %@", #function, url)
		} else if let item, item !== fileItem && !outlineView.isItemExpanded(item) {
			NSLog("%@ *** item no longer expanded: %@", #function, item)

			item.children = nil
			item.arrangedChildren = nil
			outlineView.reloadItem(item, reloadChildren: true)

			if let observer = fileItemObservers?[url] {
				FileItem.removeObserver(observer)
			}
			fileItemObservers?[url] = nil
		} else if let item {
			var children: [FileItem] = []

			if let existing = item.children {
				var newURLs = Set(urls)

				for child in existing {
					if let resolved = child.fileReferenceURL?.filePathURL {
						child.URL = resolved as NSURL
					}

					if newURLs.contains(child.URL) {
						newURLs.remove(child.URL)
						child.updateFileProperties()
						children.append(child)
					}
				}

				urls = Array(newURLs)
			}

			for url in urls {
				if let child = FileItem.fileItem(withURL: url) {
					children.append(child)
				}
			}

			item.children = children
			rearrangeChildren(inParent: item)

			for child in (item.arrangedChildren as? [FileItem]) ?? [] {
				guard let childURL = child.URL else { continue }

				if (flag && !child.symbolicLink || pendingExpandedURLs?.contains(childURL) ?? false || childURL.scheme == "scm") && outlineView.isExpandable(child) {
					outlineView.expandItem(child, expandChildren: flag && !child.symbolicLink)
				}

				if pendingSelectedURLs?.contains(childURL) ?? false {
					outlineView.selectRowIndexes(IndexSet(integer: outlineView.row(forItem: child)), byExtendingSelection: true)
					pendingSelectedURLs?.remove(childURL)
				}
			}
		}

		loadingURLs?.remove(url)
		checkLoadCompletionHandlers()
	}

	@objc(checkLoadCompletionHandlers)
	func checkLoadCompletionHandlers() {
		if loadingURLs?.count == 0 {
			let completionHandlers = loadingURLsCompletionHandlers
			loadingURLsCompletionHandlers = nil
			for handler in completionHandlers ?? [] {
				handler()
			}
		}
	}

	@objc(expandURLs:selectURLs:)
	func expandURLs(_ expandURLs: [NSURL]?, selectURLs: [NSURL]?) {
		// Captures self strongly, exactly as the ObjC++ block did (rule 27) —
		// this handler must run even if nothing else is holding the controller
		// through the load.
		loadingURLsCompletionHandlers = (loadingURLsCompletionHandlers ?? []) + [ {
			self.perform(#selector(NSResponder.centerSelectionInVisibleArea(_:)), with: self, afterDelay: 0)
		} ]

		self.pendingExpandedURLs = expandURLs.map { NSMutableSet(array: $0) } ?? self.pendingExpandedURLs
		self.pendingSelectedURLs = selectURLs.map { NSMutableSet(array: $0) } ?? self.pendingSelectedURLs

		var stack = (fileItem?.arrangedChildren as? [FileItem]) ?? []
		while let item = stack.first {
			stack.removeFirst()
			if let itemURL = item.URL, pendingExpandedURLs?.contains(itemURL) ?? false {
				outlineView.expandItem(item)
				if let arrangedChildren = item.arrangedChildren as? [FileItem] {
					stack.append(contentsOf: arrangedChildren)
				}
			}
		}

		var indexesToSelect = IndexSet()
		for i in 0 ..< outlineView.numberOfRows {
			if let item = outlineView.item(atRow: i) as? FileItem, let itemURL = item.URL, pendingSelectedURLs?.contains(itemURL) ?? false {
				indexesToSelect.insert(i)
			}
		}
		outlineView.selectRowIndexes(indexesToSelect, byExtendingSelection: false)

		checkLoadCompletionHandlers()
	}

	// The four counters. `flag ? 1 : 0` rather than a plain increment because
	// AppKit sends these for every item in an expand-all, and only the outermost
	// one carries the flag.

	@objc(outlineView:willExpandItem:expandChildren:)
	func outlineView(_ outlineView: NSOutlineView, willExpandItem item: FileItem?, expandChildren flag: Bool) {
		expandingChildrenCounter += flag ? 1 : 0
	}

	@objc(outlineView:didExpandItem:expandChildren:)
	func outlineView(_ outlineView: NSOutlineView, didExpandItem item: FileItem?, expandChildren flag: Bool) {
		expandingChildrenCounter -= flag ? 1 : 0
	}

	@objc(outlineView:willCollapseItem:collapseChildren:)
	func outlineView(_ outlineView: NSOutlineView, willCollapseItem someItem: Any?, collapseChildren flag: Bool) {
		collapsingChildrenCounter += flag ? 1 : 0
	}

	@objc(outlineView:didCollapseItem:collapseChildren:)
	func outlineView(_ outlineView: NSOutlineView, didCollapseItem someItem: Any?, collapseChildren flag: Bool) {
		collapsingChildrenCounter -= flag ? 1 : 0
	}

	@objc(outlineViewItemWillCollapse:)
	func outlineViewItemWillCollapse(_ aNotification: Notification) {
		let item = aNotification.userInfo?["NSObject"] as? FileItem
		if nestedCollapsingChildrenCounter == 0 || collapsingChildrenCounter > 0 {
			if let url = item?.URL {
				pendingExpandedURLs?.remove(url)
			}
		}

		nestedCollapsingChildrenCounter += 1
	}

	@objc(outlineViewItemDidCollapse:)
	func outlineViewItemDidCollapse(_ aNotification: Notification) {
		nestedCollapsingChildrenCounter -= 1

		if nestedCollapsingChildrenCounter == 0 {
			invalidateRestorableState()
		}
	}

	@objc(outlineViewSelectionDidChange:)
	func outlineViewSelectionDidChange(_ aNotification: Notification) {
		invalidateRestorableState()
	}
}
