import AppKit

// The file browser's container view: it builds the header, the outline view
// inside its scroll view, and the bottom actions strip, and lays the three out.
// No logic of its own — FileBrowserViewController creates one lazily as its
// `view` and reaches the three child views by name to wire targets, actions and
// bindings.
//
// The last leaf of the view layer: every view it builds (OFBHeaderView,
// FileBrowserOutlineView, OFBActionsView) is already Swift, so this port needed
// nothing new from the bridging header.
//
// FileBrowserView.h stays as a hand-written ObjC declaration of this class (the
// DocumentWindowController.h arrangement), since FileBrowserViewController.mm
// still imports it.
//
// NSAccessibilityGroup is not declared, matching OakTabBarView: under Swift 6
// that marker conformance crosses main-actor isolation, and the group role is
// what VoiceOver actually reads — it is set at runtime below, exactly as the
// ObjC++ did.

@objc(FileBrowserView)
class FileBrowserView: NSView {
	@objc var headerView: OFBHeaderView!
	@objc var outlineView: NSOutlineView!
	@objc var actionsView: OFBActionsView!

	private var scrollView: NSScrollView!

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)

		setAccessibilityRole(.group)
		setAccessibilityLabel("File browser")

		headerView  = OFBHeaderView(frame: .zero)
		actionsView = OFBActionsView(frame: .zero)

		outlineView = FileBrowserOutlineView(frame: .zero)
		outlineView.setAccessibilityLabel("Files")
		outlineView.allowsMultipleSelection  = true
		outlineView.autoresizesOutlineColumn = false
		outlineView.focusRingType            = .none
		outlineView.headerView               = nil

		outlineView.style = .plain
		outlineView.floatsGroupRows = false

		outlineView.setDraggingSourceOperationMask([ .link, .move, .copy ], forLocal: true)
		outlineView.setDraggingSourceOperationMask(.every, forLocal: false)
		outlineView.registerForDraggedTypes([ NSPasteboard.PasteboardType("NSFilenamesPboardType") ])

		let tableColumn = NSTableColumn()
		outlineView.addTableColumn(tableColumn)
		outlineView.outlineTableColumn = tableColumn
		outlineView.sizeLastColumnToFit()

		scrollView = NSScrollView(frame: .zero)
		scrollView.borderType            = .noBorder
		scrollView.documentView          = outlineView
		scrollView.hasHorizontalScroller = false
		scrollView.hasVerticalScroller   = true
		scrollView.autohidesScrollers    = true

		let views: [String: NSView] = [
			"header":  headerView,
			"files":   scrollView,
			"actions": actionsView,
		]

		OakAddAutoLayoutViewsToSuperview(Array(views.values), self)
		headerView.removeFromSuperview()
		addSubview(headerView, positioned: .above, relativeTo: nil)

		OakSetupKeyViewLoop([ self, headerView, outlineView, actionsView ])

		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[files(==header,==actions)]|", options: [], metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[header]-(>=0)-[actions]",     options: .alignAllLeading, metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[files][actions]|",            options: .alignAllLeading, metrics: nil, views: views))

		var insets = scrollView.contentInsets
		insets.top += headerView.fittingSize.height
		scrollView.automaticallyAdjustsContentInsets = false
		scrollView.contentInsets = insets

		outlineView.backgroundColor = NSColor.clear
		scrollView.drawsBackground  = false
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
