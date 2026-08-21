import AppKit

// Ported from ui/TableView.mm (2026-08-20). OakFilterList's first Swift file, the
// leaf the framework is being ported from: the row view OakChooser's table uses to
// keep an active (dark) selection while the chooser window is a subordinate child of
// its parent. @objc(OakInactiveTableRowView) and the -drawAsHighlighted surface are
// pinned by t_tableview.mm (rule 18); +new and -setDrawAsHighlighted: are called from
// OakChooser.mm, still ObjC++, through the hand-declaration in ui/TableView.h. The
// original had no C++, so this is a straight translation.
//
// -updateDrawAsHighlighted keeps the respondsToSelector duck-typing of the original:
// a table cell view carries -setBackgroundStyle: directly, a plain control carries it
// on its -cell, and both need the dark style so their text draws light-on-dark.
@objc(OakInactiveTableRowView)
class OakInactiveTableRowView: NSTableRowView {
	@objc var drawAsHighlighted = false {
		didSet { updateDrawAsHighlighted() }
	}

	private var effectiveDrawAsHighlighted = false

	private func updateDrawAsHighlighted() {
		let flag = isSelected && drawAsHighlighted && (window?.isKeyWindow ?? false)
		if effectiveDrawAsHighlighted == flag {
			return
		}
		effectiveDrawAsHighlighted = flag

		for view in subviews {
			if view.responds(to: #selector(setter: NSTableCellView.backgroundStyle)) {
				(view as? NSTableCellView)?.backgroundStyle = interiorBackgroundStyle
			}
			if view.responds(to: #selector(getter: NSControl.cell)) {
				(view as? NSControl)?.cell?.backgroundStyle = interiorBackgroundStyle
			}
		}

		needsDisplay = true
	}

	override var isSelected: Bool {
		didSet { updateDrawAsHighlighted() }
	}

	override var isEmphasized: Bool {
		didSet { updateDrawAsHighlighted() }
	}

	override var interiorBackgroundStyle: NSView.BackgroundStyle {
		effectiveDrawAsHighlighted ? .dark : super.interiorBackgroundStyle
	}

	override func drawSelection(in dirtyRect: NSRect) {
		if !effectiveDrawAsHighlighted {
			super.drawSelection(in: dirtyRect)
			return
		}

		NSColor.alternateSelectedControlColor.set()
		bounds.insetBy(dx: 0, dy: 0.5).offsetBy(dx: 0, dy: -0.5).intersection(dirtyRect).fill()
	}
}
