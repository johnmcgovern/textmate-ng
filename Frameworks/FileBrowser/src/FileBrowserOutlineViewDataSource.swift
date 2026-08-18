import AppKit

// The outline view's data source: how many children an item has, which object
// each row is, what is expandable, what is selectable, and what gets written to
// the pasteboard when a row is dragged.
//
// The first section peeled off FileBrowserViewController ahead of the port. The
// class is still ObjC++, so this is a Swift *extension* on it — the same
// arrangement as FileBrowserDiskOperations, and for the same reason: a class
// definition has to flip in one commit, but its methods can leave a section at
// a time, each judged by the suite and the app on its own.
//
// Nothing declares these to ObjC. The conformance to NSOutlineViewDataSource /
// NSOutlineViewDelegate stays on the class extension in the .mm, AppKit calls
// them through it by selector, and — measured before the move — nothing inside
// the framework calls any of the seven directly. So unlike DiskOperations there
// is no category header to keep in step.
//
// Every selector is written out with @objc(...) rather than left to the
// importer. Rule 28: its renaming is not uniform and not predictable. Rule 18:
// a selector that drifts here does not fail to compile, it makes the browser
// quietly empty.
extension FileBrowserViewController {
	// Both of the next two resolve "the item asked about, or the root" — and both
	// have to survive that being **nil**, which is rule 33 in its purest form and
	// is not hypothetical: the first draft of this file wrote
	// `(item ?? fileItem).arrangedChildren` and crashed the suite. `fileItem` is
	// declared without nullability in the ObjC header, so it imports as
	// `FileItem!`; the moment both are nil that expression force-unwraps and
	// traps, where the ObjC++ `(item ?: _fileItem).arrangedChildren.count`
	// messaged nil all the way down and answered 0. The explicit `FileItem?`
	// annotation is what keeps `??` from unwrapping the IUO.
	//
	// A controller whose view has been asked for before a URL is set is exactly
	// that state, which is why -updateMenu: reached it from a test.

	@objc(outlineView:numberOfChildrenOfItem:)
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		let parent: FileItem? = item as? FileItem ?? fileItem
		return parent?.arrangedChildren?.count ?? 0
	}

	@objc(outlineView:child:ofItem:)
	// `-> Any!`, not `-> Any`, even though the protocol requirement is
	// non-optional. An implicitly-unwrapped return still witnesses it, and it is
	// the only spelling that can answer **nil** — which is what the ObjC++ did and
	// what t_file_browser_view_controller.mm pins. Returning NSNull() instead
	// compiles, reads as harmless, and fails that test: rule 33, caught by the one
	// assertion written for it.
	func outlineView(_ outlineView: NSOutlineView, child childIndex: Int, ofItem item: Any?) -> Any! {
		// The ObjC++ subscripted a possibly-nil array and answered nil; a literal
		// translation would trap, so the nil is explicit. AppKit is not supposed
		// to ask out of range — "not supposed to" is what rule 33 is about.
		let parent: FileItem? = item as? FileItem ?? fileItem
		guard let children = parent?.arrangedChildren, childIndex < children.count else {
			return nil
		}
		return children[childIndex]
	}

	@objc(outlineView:isItemExpandable:)
	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		guard let item = item as? FileItem else { return false }
		return item.isDirectory && (canExpandPackages || !item.package) || (canExpandSymbolicLinks && item.linkToDirectory && (canExpandPackages || !item.linkToPackage))
	}

	@objc(outlineView:isGroupItem:)
	func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
		guard let item = item as? FileItem else { return false }
		return item.URL.scheme == "scm"
	}

	@objc(outlineView:shouldSelectItem:)
	func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
		guard let item = item as? FileItem else { return false }
		return item.URL.isFileURL
	}

	@objc(outlineView:objectValueForTableColumn:byItem:)
	func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
		return item
	}

	@objc(outlineView:pasteboardWriterForItem:)
	func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
		// -[NSURL filePathURL] imports as a bridged `URL?`, which is a struct and
		// conforms to nothing; the ObjC++ handed the pasteboard the NSURL itself.
		guard let item = item as? FileItem else { return nil }
		return item.URL.filePathURL as NSURL?
	}
}
