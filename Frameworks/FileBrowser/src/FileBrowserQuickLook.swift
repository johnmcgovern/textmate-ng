import AppKit
import Quartz

// Quick Look: taking control of the shared preview panel, feeding it the
// selection, and letting the arrow keys move through the browser while it is
// open.
//
// Sixth section peeled off the controller, and the first that the ivar
// promotion (`2b34881a`) unblocked — every method here but one used to touch
// `_previewItems` and so could not leave the .mm at all.
//
// -previewableItems stayed behind at the time, as the getter of a property
// declared on the class extension, and was readable from here only because
// FileBrowserViewControllerInternal.h re-declared it. Both that header and the
// class extension went at the flip; it is an ordinary computed property on the
// Swift class now.
//
// The conformances are declared here rather than in that header, per rule 42 —
// re-stating them where Swift can see them would break these witnesses instead
// of enabling them. QLPreviewPanelDataSource's two requirements are both below;
// QLPreviewPanelDelegate is all-optional.
//
// **`override public` on the three panel-control methods, and it is not
// boilerplate.** They are not protocol methods at all: QuickLook declares them
// in `@interface NSObject (QLPreviewPanelController)`, an informal protocol, so
// every object *inherits* them and defining one here is an override. Rule 31
// says a Swift extension cannot override an inherited method — and the
// refinement this section found is that it can when the inherited method comes
// from an imported ObjC category that only declares it. `-presentError:`, a
// real NSResponder method with a real implementation, still cannot, which is
// why it is still sitting in FileBrowserDiskOperationsSupport.mm. `public` is
// forced by the same rule as the NSTextFieldDelegate witness: the imported
// declaration is public, so the override must be at least as accessible.
//
// `@preconcurrency` on both conformances is rule 26's Swift-6 half: the class
// is main-actor isolated (NSViewController), the QuickLook protocols are not,
// and without it the conformance is an error rather than a warning. Same
// spelling DocumentWindowController.swift already uses for FileBrowserDelegate.
extension FileBrowserViewController: @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
	@objc(toggleQuickLookPreview:)
	func toggleQuickLookPreview(_ sender: Any?) {
		if QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible {
			QLPreviewPanel.shared().orderOut(nil)
		} else {
			QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
		}
	}

	@objc(acceptsPreviewPanelControl:)
	override public func acceptsPreviewPanelControl(_ previewPanel: QLPreviewPanel!) -> Bool {
		return true
	}

	@objc(beginPreviewPanelControl:)
	override public func beginPreviewPanelControl(_ previewPanel: QLPreviewPanel!) {
		previewItems = previewableItems
		previewPanel.delegate = self
		previewPanel.dataSource = self
	}

	@objc(endPreviewPanelControl:)
	override public func endPreviewPanelControl(_ previewPanel: QLPreviewPanel!) {
		previewItems = nil
	}

	public func numberOfPreviewItems(in previewPanel: QLPreviewPanel!) -> Int {
		return previewItems?.count ?? 0
	}

	public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
		// The ObjC++ subscripted a possibly-nil array and answered nil rather
		// than trapping (rule 33); the panel only asks within the count it was
		// given, but "only asks" is what that rule is about.
		guard let previewItems, index < previewItems.count else { return nil }
		return previewItems[index]
	}

	public func previewPanel(_ previewPanel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
		return imageRect(of: item as? FileItem)
	}

	@objc(imageRectOfItem:)
	func imageRect(of item: FileItem?) -> NSRect {
		let row = outlineView.row(forItem: item)
		if row != -1 {
			if let view = outlineView.view(atColumn: 0, row: row, makeIfNecessary: true) as? FileItemTableCellView,
			   let imageButton = view.openButton {
				let imageRect = NSIntersectionRect(imageButton.convert(imageButton.bounds, to: nil),
				                                   outlineView.convert(outlineView.visibleRect, to: nil))
				return NSIsEmptyRect(imageRect) ? NSZeroRect : (view.window?.convertToScreen(imageRect) ?? NSZeroRect)
			}
		}
		return NSZeroRect
	}

	public func previewPanel(_ previewPanel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
		let eventString = FileBrowserViewControllerSupport.eventString(for: event)
		let upArrow     = String(format: "%C", NSUpArrowFunctionKey)
		let downArrow   = String(format: "%C", NSDownArrowFunctionKey)
		if (event.type == .keyUp || event.type == .keyDown) && (eventString == upArrow || eventString == downArrow) {
			view.window?.sendEvent(event)
			previewItems = previewableItems
			previewPanel.reloadData()
			return true
		}
		return false
	}
}
