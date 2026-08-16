import AppKit

// The row views: making (and reusing) a FileItemTableCellView, the two buttons
// it carries — open in the editor, close the open document — and committing a
// rename when its text field stops editing.
//
// The second section peeled off FileBrowserViewController, on the same terms as
// FileBrowserOutlineViewDataSource: the class is still ObjC++, this is a Swift
// extension on it, and every entry point keeps its exact ObjC selector because
// all four are reached by selector rather than by call — AppKit for the two
// delegate methods, and the buttons' target/action for the other two, which are
// wired up right here.
extension FileBrowserViewController {
	@objc(outlineView:viewForTableColumn:item:)
	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: FileItem) -> NSView? {
		// The delegate declares tableColumn nullable and the ObjC++ read
		// .identifier off it unguarded, which would have handed makeView a nil
		// identifier. AppKit passes the outline column here in practice; this
		// answers "no view" instead of reproducing that, and it is the only
		// behavioural difference in this file.
		guard let identifier = tableColumn?.identifier else { return nil }

		if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? FileItemTableCellView {
			return reused
		}

		let res = FileItemTableCellView()
		res.identifier = identifier
		// Optional-chained rather than force-unwrapped: these import as IUOs from
		// FileItemTableCellView, and rule 33's lesson from the data source is that
		// an IUO on a path AppKit drives is a trap waiting for one nil.
		res.openButton?.target  = self
		res.openButton?.action  = #selector(takeItemToOpenFrom(_:))
		res.closeButton?.target = self
		res.closeButton?.action = #selector(takeItemToCloseFrom(_:))
		res.textField?.delegate = self
		return res
	}

	@objc(takeItemToOpenFrom:)
	func takeItemToOpenFrom(_ sender: Any) {
		guard let view = sender as? NSView else { return }
		let row = outlineView.row(for: view)
		if row != -1, let item = outlineView.item(atRow: row) as? FileItem {
			openItems([ item ], animate: true)
		}
	}

	@objc(takeItemToCloseFrom:)
	func takeItemToCloseFrom(_ sender: Any) {
		guard let view = sender as? NSView else { return }
		let row = outlineView.row(for: view)
		if row != -1, let item = outlineView.item(atRow: row) as? FileItem {
			// Two importer surprises in one call, and neither is fixable here.
			// `-fileBrowser:closeURL:` arrives as `fileBrowser(_:close:)` — the
			// trailing URL is trimmed, while the sibling `-fileBrowser:openURLs:`
			// keeps its name (rule 28, exactly the inconsistency it warns about).
			// And the NSURL* bridges to a `URL` struct, so this converts where the
			// ObjC++ passed the object straight through.
			//
			// Not worth an NS_SWIFT_NAME on FileBrowserTypes.h: DocumentWindow's
			// Swift already conforms to this protocol and spells it `close:`
			// (DocumentWindowController.swift:1575), so pinning the name here
			// would break a consumer to tidy a call site.
			delegate?.fileBrowser(self, close: item.URL as URL)
		}
	}

}

// The conformance is declared *here* rather than in the internal header, and
// that is load-bearing. The class extension in the .mm already declares it, but
// re-stating it in an ObjC header makes it visible to Swift, and then this
// method stops compiling — the imported NSControlTextEditingDelegate member
// counts as a previous declaration of the same selector. Letting the Swift
// extension own the conformance makes this a witness instead of a clash, and
// the duplicate in the ObjC metadata is harmless.
extension FileBrowserViewController: NSTextFieldDelegate {
	// `public` is required rather than chosen: an imported ObjC class is public
	// in Swift, so a witness to a requirement of a public protocol has to be too.
	// It widens nothing — the class and its selectors were already reachable from
	// ObjC, and nothing in this framework is exported to other Swift modules. The
	// alternative (leave the conformance in the .mm and cast `self` at the
	// assignment) compiles without it, but turns a missing conformance into a
	// silent nil delegate at run time instead of an error here.
	public func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
		let row = outlineView.row(for: control)
		if row == -1 {
			return false
		}

		guard let item = outlineView.item(atRow: row) as? FileItem,
		      let parent = item.URL.deletingLastPathComponent else {
			return false
		}

		let newURL = parent.appendingPathComponent(fieldEditor.string, isDirectory: item.isDirectory) as NSURL

		// -[NSURL isEqual:], not Swift's URL ==, which normalises (rule 33). These
		// are compared against a FileItem's own URL, so the ObjC semantics are the
		// ones that decide whether a rename happened at all.
		if !item.URL.isEqual(newURL) {
			// Because of the animation we need to run this after field editor has been removed
			DispatchQueue.main.async {
				// The ObjC++ discarded the result too — the rename's effect on the
				// tree is applied by performOperation itself.
				_ = self.performOperation(.rename, withURLs: [ item.URL: newURL ], unique: false, select: true)
			}
		}

		return true
	}
}
