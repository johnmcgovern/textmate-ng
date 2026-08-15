import AppKit

// The file browser's outline view. Mostly an NSOutlineView with a few overrides:
// it brackets expand/collapse with delegate hooks, adds a handful of action
// methods the key bindings and menus reach, and turns a drag-to-Trash into a
// delegate callback.
//
// The delegate cast is the subtle part. The ObjC++ used -respondsToSelector: —
// structural — so the controller never had to declare conformance. Swift's
// `as? FileBrowserOutlineViewDelegate` is nominal, so FileBrowserViewController
// now declares <FileBrowserOutlineViewDelegate> (it already implements every
// method). The protocol itself lives in FileBrowserOutlineViewDelegate.h so the
// bridging header can see it without seeing this class.
//
// -performKeyEquivalent:'s C++ table stays in FileBrowserOutlineViewKeyBindings.
@objc(FileBrowserOutlineView)
final class FileBrowserOutlineView: NSOutlineView {
	override func expandItem(_ item: Any?, expandChildren: Bool) {
		(delegate as? FileBrowserOutlineViewDelegate)?.outlineView(self, willExpandItem: item as Any, expandChildren: expandChildren)
		super.expandItem(item, expandChildren: expandChildren)
		(delegate as? FileBrowserOutlineViewDelegate)?.outlineView(self, didExpandItem: item as Any, expandChildren: expandChildren)
	}

	override func collapseItem(_ item: Any?, collapseChildren: Bool) {
		(delegate as? FileBrowserOutlineViewDelegate)?.outlineView(self, willCollapseItem: item as Any, collapseChildren: collapseChildren)
		super.collapseItem(item, collapseChildren: collapseChildren)
		(delegate as? FileBrowserOutlineViewDelegate)?.outlineView(self, didCollapseItem: item as Any, collapseChildren: collapseChildren)
	}

	@objc func showContextMenu(_ sender: Any?) {
		guard let menu = self.menu else { return }

		let rect = convert(rect(ofRow: selectedRow != -1 ? selectedRow : 0), to: nil)
		guard let fakeEvent = NSEvent.mouseEvent(
			with: .leftMouseDown,
			location: NSMakePoint(NSMinX(rect) + 10, NSMinY(rect)),
			modifierFlags: [],
			timestamp: NSApp.currentEvent?.timestamp ?? 0,
			windowNumber: window?.windowNumber ?? 0,
			context: nil,
			eventNumber: 0,
			clickCount: 1,
			pressure: 1
		) else { return }

		NSMenu.popUpContextMenu(menu, with: fakeEvent, for: self)
	}

	@objc func performDoubleClick(_ sender: Any?) {
		if let doubleAction = self.doubleAction {
			NSApp.sendAction(doubleAction, to: self.target, from: self)
		}
	}

	@objc func performEditSelectedRow(_ sender: Any?) {
		let row = (clickedRow == -1 && numberOfSelectedRows == 1) ? selectedRow : clickedRow
		if row != -1 {
			window?.makeKey()
			editColumn(0, row: row, with: nil, select: true)
		}
	}

	override func performKeyEquivalent(with event: NSEvent) -> Bool {
		if window?.firstResponder === self {
			if let action = FileBrowserOutlineViewActionForEvent(event) {
				return NSApp.sendAction(action, to: nil, from: self)
			}
		}
		return super.performKeyEquivalent(with: event)
	}

	override func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
		if operation == .delete, let delegate = delegate as? FileBrowserOutlineViewDelegate {
			var urls: [URL] = []
			let pboard = session.draggingPasteboard
			let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
			let paths = pboard.availableType(from: [filenames]) != nil ? (pboard.propertyList(forType: filenames) as? [String] ?? []) : []
			for path in paths {
				urls.append(URL(fileURLWithPath: path))
			}
			delegate.outlineView(self, didTrashURLs: urls)
		}
		super.draggingSession(session, endedAt: screenPoint, operation: operation)
	}
}
