// The document tab bar. Implemented in Swift as @objc(OakTabBarView); the public
// ObjC surface stays hand-written in OakTabBarView.h (the module name equals the
// class name, so the generated *-Swift.h cannot be exported — same pattern as
// Preferences.h). Ported from OakTabBarView.mm (2026-07-28), together with
// OakTabView and OakTabFrame, which are mutually coupled and could not be split.
import AppKit
import QuartzCore

private let kUserDefaultsTabItemMinWidthKey = "tabItemMinWidth"
private let kUserDefaultsTabItemMaxWidthKey = "tabItemMaxWidth"

// ===============
// = OakTabFrame =
// ===============

// A layout value object: one tab item and the width it should occupy. NSObject
// (not a Swift struct) because layouts round-trip through the animator's
// NSInvocation forwarding as NSArray<OakTabFrame>, and because reloadData
// compares two layouts with -isEqual: element by element.
final class OakTabFrame: NSObject {
	let tabItem: OakTabItem
	var width: CGFloat

	init(tabItem: OakTabItem, width: CGFloat) {
		self.tabItem = tabItem
		self.width   = width
	}

	override func isEqual(_ object: Any?) -> Bool {
		guard let other = object as? OakTabFrame else { return false }
		return width == other.width && tabItem.identifier == other.tabItem.identifier
	}
}

// =================
// = OakTabBarView =
// =================

// NSAccessibilityGroup omitted deliberately (Swift-6 main-actor isolation, as on
// OakTabView) — the tab-group role is set at runtime via setAccessibilityRole.
// NSDraggingSource is kept: it is required to pass self to beginDraggingSession.
@objc(OakTabBarView)
final class OakTabBarView: NSView, NSDraggingSource {
	@objc weak var delegate: (any OakTabBarViewDelegate)?
	@objc weak var dataSource: (any OakTabBarViewDataSource)?

	// Fixed 2026-07-29. In OakTabBarView.mm this was a readonly @property with no
	// getter implementation — an auto-synthesized ivar nothing ever assigned, so
	// it always returned 0. The port preserved that verbatim; it is now assigned
	// from the layout pass (see makeLayout).
	//
	// The consumer is DocumentWindowController's tab auto-close, which computes
	// `documents.count - max(countOfVisibleTabs, 8)`. With the old constant 0 it
	// always closed down to 8 tabs; it now keeps whatever is actually on screen
	// when that is more than 8, which is what the max() was plainly there for.
	@objc private(set) var countOfVisibleTabs: Int = 0

	@objc var neverHideLeftBorder: Bool = false // public but referenced nowhere; kept for surface parity

	private var minimumTabSize: Int = 0
	private var maximumTabSize: Int = 0

	private var _tag: Int = 0
	override var tag: Int { _tag }

	private var tabItems: [OakTabItem] = []

	private var _draggedTabIndex: Int = -1
	var draggedTabIndex: Int {
		get { _draggedTabIndex }
		set {
			guard _draggedTabIndex != newValue else { return }
			if _draggedTabIndex != -1 { tabItems[_draggedTabIndex].tabView?.isHidden = false }
			_draggedTabIndex = newValue
			if _draggedTabIndex != -1 { tabItems[_draggedTabIndex].tabView?.isHidden = true }
			updateToLayout(makeLayout())
		}
	}

	private var _dropTabAtIndex: Int = -1
	@objc dynamic var dropTabAtIndex: Int {
		get { _dropTabAtIndex }
		set {
			guard _dropTabAtIndex != newValue else { return }
			_dropTabAtIndex = newValue
			updateToLayout(makeLayout())
		}
	}

	private var freezeTabFramesLeftOfIndex: Int = 0
	private var trackingArea: NSTrackingArea?
	var dragging: Bool = false

	private var fromLayout: [OakTabFrame] = []
	private var toLayout: [OakTabFrame] = []

	private var tabLayoutAnimationProgressOffset: CGFloat = 0
	@objc dynamic var tabLayoutAnimationProgress: CGFloat = 0 {
		didSet {
			guard oldValue != tabLayoutAnimationProgress else { return }
			currentLayout = interpolatedLayout(fromLayout, withFraction: tabLayoutAnimationProgress - tabLayoutAnimationProgressOffset, ofLayout: toLayout)
		}
	}

	// The trailing empty tab that fills the bar to the right of the last real
	// tab; it is also the double-click-to-open-a-new-tab target.
	private var backgroundView: OakTabView!

	private var _createNewTabButton: NSButton?
	private var createNewTabButton: NSButton {
		if let button = _createNewTabButton { return button }
		let button = NSButton(frame: NSMakeRect(0, 2, 26, 20))
		button.setAccessibilityLabel("Create new tab")
		button.image      = NSImage(named: NSImage.addTemplateName)
		button.isBordered  = false
		button.setButtonType(.momentaryChange)
		button.toolTip    = "Create new tab"
		button.action     = #selector(newTab(_:))
		button.target     = self
		_createNewTabButton = button
		return button
	}

	private var oakAnimator: OakTabBarView {
		unsafeBitCast(OakAnimatorProxy(realObject: self.animator()), to: OakTabBarView.self)
	}

	// MARK: - Init

	private static let registerDefaults: Void = {
		UserDefaults.standard.register(defaults: [
			kUserDefaultsTabItemMinWidthKey: 120,
			kUserDefaultsTabItemMaxWidthKey: 250,
		])
	}()

	override init(frame frameRect: NSRect) {
		Self.registerDefaults
		super.init(frame: frameRect)

		setAccessibilityRole(.tabGroup)
		setAccessibilityLabel("Open files")

		minimumTabSize = UserDefaults.standard.integer(forKey: kUserDefaultsTabItemMinWidthKey)
		maximumTabSize = UserDefaults.standard.integer(forKey: kUserDefaultsTabItemMaxWidthKey)

		backgroundView = OakTabView(frame: .zero, tabItem: nil, parent: nil)
		backgroundView.target       = self
		backgroundView.doubleAction = #selector(newTab(_:))
		addSubview(backgroundView, positioned: .below, relativeTo: nil)

		addSubview(createNewTabButton, positioned: .above, relativeTo: nil)

		registerForDraggedTypes([OakTabItem.pasteboardType])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override var intrinsicContentSize: NSSize {
		NSMakeSize(NSView.noIntrinsicMetric, 23)
	}

	override var mouseDownCanMoveWindow: Bool { false }

	override class func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
		if key == "tabLayoutAnimationProgress" {
			return CABasicAnimation()
		}
		return super.defaultAnimation(forKey: key)
	}

	// MARK: - Selection

	// UInt, not Int, to match the NSUInteger in OakTabBarView.h. This is load
	// bearing: DocumentWindowController passes expressions like
	// `MIN(_selectedTabIndex, _documents.count-1)`, which is NSUIntegerMax when
	// the document list is empty. As NSUInteger that fails the `< count` guard
	// harmlessly, exactly as the ObjC original did; as Int it would arrive as -1,
	// *pass* the guard, and index the array out of bounds. Same trap as the
	// BundlesPreferences.selectedIndex crash — keep bounds checks unsigned.
	@objc var selectedTabIndex: UInt {
		get { tabItems.firstIndex { $0.selected }.map(UInt.init) ?? UInt(NSNotFound) }
		set {
			for i in 0..<tabItems.count {
				tabItems[i].selected = (UInt(i) == newValue)
			}
			if newValue < UInt(tabItems.count) {
				let index = Int(newValue)
				if tabItems[index].tabView == nil || NSWidth(tabItems[index].tabView!.frame) == 0 {
					updateToLayout(makeLayout())
				}
			}
		}
	}

	// MARK: - Reload

	@objc func reloadData() {
		guard let dataSource else { return }

		// Int(exactly:) rather than Int(): this NSUInteger crosses a protocol
		// boundary, so its value is not ours to trust, and a checked Int() traps on
		// anything above Int.max where the ObjC++ original just kept it unsigned.
		// No real data source can produce that — DocumentWindowController returns
		// `_documents.count` — but "convert a foreign integer defensively" is the
		// rule this framework has already been bitten by three times.
		let newCount = Int(exactly: dataSource.numberOfRows(in: self)) ?? 0
		if newCount > tabItems.count {
			freezeTabFramesLeftOfIndex = 0
		}

		let draggedTabItem = _draggedTabIndex != -1 ? tabItems[_draggedTabIndex] : nil
		let droppedTabItem = (_dropTabAtIndex != -1 && _dropTabAtIndex < tabItems.count) ? tabItems[_dropTabAtIndex] : nil

		var oldTabItems: [String: OakTabItem] = [:]
		for tabItem in tabItems {
			if let identifier = tabItem.identifier { oldTabItems[identifier] = tabItem }
		}

		var newTabItems: [OakTabItem] = []
		for i in 0..<newCount {
			let index = UInt(i)
			let identifier = dataSource.tabBarView(self, uuidFor: index).uuidString
			if let tabItem = oldTabItems[identifier] {
				tabItem.title    = dataSource.tabBarView(self, titleFor: index)
				tabItem.path     = dataSource.tabBarView(self, pathFor: index)
				tabItem.modified = dataSource.tabBarView(self, isEditedAt: index)
				oldTabItems[identifier] = nil
				newTabItems.append(tabItem)
			} else {
				let tabItem = OakTabItem(title: dataSource.tabBarView(self, titleFor: index), path: dataSource.tabBarView(self, pathFor: index), identifier: identifier, modified: dataSource.tabBarView(self, isEditedAt: index))
				newTabItems.append(tabItem)
			}
		}

		tabItems = newTabItems

		if let draggedTabItem {
			let idx = tabItems.firstIndex(of: draggedTabItem) ?? NSNotFound
			_draggedTabIndex = idx == NSNotFound ? -1 : idx
		} else {
			_draggedTabIndex = -1
		}

		if let droppedTabItem {
			let idx = tabItems.firstIndex(of: droppedTabItem) ?? NSNotFound
			_dropTabAtIndex = idx == NSNotFound ? -1 : idx
		} else {
			_dropTabAtIndex = _dropTabAtIndex == -1 ? -1 : tabItems.count
		}

		let newLayout = makeLayout()
		if !(toLayout as NSArray).isEqual(newLayout) {
			updateToLayout(newLayout)
		}
	}

	// MARK: - Tracking areas

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea {
			removeTrackingArea(trackingArea)
		}
		var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
		if let window, NSMouseInRect(convert(window.mouseLocationOutsideOfEventStream, from: nil), visibleRect, isFlipped) {
			options.insert(.assumeInside)
		}
		let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseEntered(with event: NSEvent) {
	}

	override func mouseExited(with event: NSEvent) {
		if freezeTabFramesLeftOfIndex > 0 {
			freezeTabFramesLeftOfIndex = 0
			oakAnimator.updateToLayout(makeLayout())
		}
	}

	func didClickOverflowButton(for clickedTabView: OakTabView) {
		let menu = NSMenu()
		for i in 0..<tabItems.count {
			let tabItem = tabItems[i]
			if let tabView = tabItem.tabView, !tabView.overflowButtonVisible, NSWidth(tabView.frame) != 0 {
				continue
			}

			let item = menu.addItem(withTitle: tabItem.title ?? "", action: Selector(("takeSelectedTabIndexFrom:")), keyEquivalent: "")
			item.representedObject = tabItem
			item.tag = i

			if let path = tabItem.path, OakNotEmptyString(path) {
				item.image   = TMFileReference.image(for: URL(fileURLWithPath: path), size: NSMakeSize(16, 16))
				item.toolTip = (path as NSString).abbreviatingWithTildeInPath
			} else {
				let icon = NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kUnknownFSObjectIcon)))
				icon.size = NSMakeSize(16, 16)
				item.image = icon
			}

			if tabItem.selected {
				item.state = .on
			} else if tabItem.modified {
				item.setModifiedState(true)
			}
		}
		menu.popUp(positioning: nil, at: NSMakePoint(NSWidth(clickedTabView.overflowButton.frame), 0), in: clickedTabView.overflowButton)
	}

	// MARK: - Actions

	func didClickCloseButton(for tabView: OakTabView) {
		guard let idx = tabView.tabItem.flatMap({ tabItems.firstIndex(of: $0) }) else { return }
		_tag = idx // performCloseTab: asks for [sender tag]

		let closeOther = isAlternateKeyOrMouseEvent()
		if closeOther, delegate?.responds(to: Selector(("performCloseOtherTabsXYZ:"))) == true {
			delegate?.performCloseOtherTabsXYZ?(self)
		} else if delegate?.responds(to: Selector(("performCloseTab:"))) == true {
			freezeTabFramesLeftOfIndex = _tag
			delegate?.performCloseTab?(self)
		}
	}

	@objc func didSingleClickTabView(_ tabView: OakTabView) {
		guard let tabItem = tabView.tabItem, let index = tabItems.firstIndex(of: tabItem) else { return }
		selectedTabIndex = UInt(index)
		delegate?.tabBarView?(self, shouldSelect: UInt(index))
	}

	@objc func didDoubleClickTabView(_ tabView: OakTabView) {
		guard let tabItem = tabView.tabItem, let index = tabItems.firstIndex(of: tabItem) else { return }
		delegate?.tabBarView?(self, didDoubleClick: UInt(index))
	}

	func menu(for tabView: OakTabView, with event: NSEvent) -> NSMenu? {
		guard let tabItem = tabView.tabItem, let idx = tabItems.firstIndex(of: tabItem) else { return nil }
		_tag = idx
		return delegate?.menu?(for: self)
	}

	@objc func newTab(_ sender: Any?) {
		delegate?.tabBarViewDidDoubleClick?(self)
	}

	@objc func performClose(_ sender: Any?) {
		for tabItem in tabItems where tabItem.selected {
			if let idx = tabItems.firstIndex(of: tabItem) {
				_tag = idx // performCloseTab: asks for [sender tag]
			}
			delegate?.performCloseTab?(self)
		}
	}

	private func isAlternateKeyOrMouseEvent() -> Bool {
		guard let event = NSApp.currentEvent else { return false }
		switch event.type {
		case .leftMouseUp, .otherMouseUp, .keyDown:
			return event.modifierFlags.contains(.option)
		default:
			return false
		}
	}

	// MARK: - Drag’n’drop (source)

	@objc func didDragTabView(_ tabView: OakTabView) {
		guard let tabItem = tabView.tabItem else { return }
		let dragItem = NSDraggingItem(pasteboardWriter: tabItem)
		if let dragImage = tabView.dragImage {
			dragItem.setDraggingFrame(convert(tabView.backgroundView.frame, from: tabView), contents: dragImage)
		}

		let idx = tabItems.firstIndex(of: tabItem) ?? NSNotFound
		draggedTabIndex = idx == NSNotFound ? -1 : idx
		dropTabAtIndex  = _draggedTabIndex + 1

		if let event = window?.currentEvent {
			beginDraggingSession(with: [dragItem], event: event, source: self)
		}
	}

	func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
		context == .outsideApplication ? [.copy, .generic] : [.copy, .move, .link]
	}

	func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
		draggedTabIndex = -1
	}

	// MARK: - Drag’n’drop (destination)

	override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
		dragging = true
		return draggingUpdated(sender)
	}

	override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
		var operation = sender.draggingSourceOperationMask
		operation = operation.contains(.move) ? .move : (operation.contains(.copy) ? .copy : [])
		if operation == [] {
			return operation
		}

		let pos = convert(sender.draggingLocation, from: nil)

		var i = 0
		var x: CGFloat = 0
		for tabItem in tabItems {
			if let tabView = tabItem.tabView, !tabView.isHidden {
				let width = NSWidth(tabView.frame)

				if _dropTabAtIndex == -1, pos.x < x + width - 20 {
					break
				} else if _dropTabAtIndex != -1, pos.x < x + width / 2 {
					break
				}

				x += width
			}
			i += 1
		}

		oakAnimator.dropTabAtIndex = i

		return operation
	}

	override func draggingExited(_ sender: (any NSDraggingInfo)?) {
		dragging = false
		oakAnimator.dropTabAtIndex = -1
	}

	override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
		sender.animatesToDestination = true
		return true
	}

	override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
		let sourceTabBar = sender.draggingSource as? OakTabBarView
		let mask = sender.draggingSourceOperationMask
		let fromIndex = sourceTabBar?.draggedTabIndex ?? -1
		let toIndex   = _dropTabAtIndex

		var tabItem: OakTabItem?
		sender.enumerateDraggingItems(options: [], for: self, classes: [NSPasteboardItem.self], searchOptions: [:]) { draggingItem, _, _ in
			let x0 = self._dropTabAtIndex > 0 ? NSMaxX(self.tabItems[self._dropTabAtIndex - 1].tabView?.frame ?? .zero) : NSMinX(self.bounds)
			let x1 = NSMinX((self._dropTabAtIndex < self.tabItems.count ? self.tabItems[self._dropTabAtIndex].tabView : self.backgroundView)?.frame ?? .zero)
			draggingItem.draggingFrame = NSMakeRect(x0, NSMinY(self.bounds), x1 - x0, NSHeight(self.bounds))
			if let pbItem = draggingItem.item as? NSPasteboardItem {
				tabItem = OakTabItem.tabItem(from: pbItem)
			}
		}

		draggedTabIndex = -1
		dropTabAtIndex  = -1

		if sourceTabBar == self, fromIndex == toIndex {
			return false
		}

		guard let identifier = tabItem?.identifier, let uuid = UUID(uuidString: identifier), let sourceTabBar else {
			return false
		}
		let op: NSDragOperation = mask.contains(.move) ? .move : (mask.contains(.copy) ? .copy : [])
		// UInt(bitPattern:) reinterprets the bits like the ObjC NSInteger→NSUInteger
		// cast did (a -1 wraps to NSUIntegerMax); UInt(_:) would trap. Normal drags
		// always pass indices >= 0.
		return delegate?.performDrop?(ofTabItem: uuid, fromTabBar: sourceTabBar, index: UInt(bitPattern: fromIndex), toTabBar: self, index: UInt(bitPattern: toIndex), operation: op) ?? false
	}

	override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
		dragging = false
	}

	// MARK: - Layout

	private struct Tab {
		let tabItem: OakTabItem
		let oldWidth: CGFloat
		let newWidth: CGFloat
		var currentWidth: CGFloat = 0
	}

	private func interpolatedLayout(_ oldLayout: [OakTabFrame], withFraction fraction: CGFloat, ofLayout newLayout: [OakTabFrame]) -> [OakTabFrame] {
		if fraction == 0 {
			return oldLayout
		} else if fraction == 1 {
			return newLayout
		}

		let oldTabIdentifiers = Set(oldLayout.compactMap { $0.tabItem.identifier })
		let newTabIdentifiers = Set(newLayout.compactMap { $0.tabItem.identifier })

		var tabs: [Tab] = []
		var i = 0, j = 0
		while i < oldLayout.count || j < newLayout.count {
			if j == newLayout.count || (i < oldLayout.count && !newTabIdentifiers.contains(oldLayout[i].tabItem.identifier ?? "")) {
				if oldLayout[i].width > 0 {
					tabs.append(Tab(tabItem: oldLayout[i].tabItem, oldWidth: oldLayout[i].width, newWidth: 0))
				}
				i += 1
			} else if i == oldLayout.count || (j < newLayout.count && !oldTabIdentifiers.contains(newLayout[j].tabItem.identifier ?? "")) {
				if newLayout[j].width > 0 {
					tabs.append(Tab(tabItem: newLayout[j].tabItem, oldWidth: 0, newWidth: newLayout[j].width))
				}
				j += 1
			} else if oldLayout[i].tabItem.identifier == newLayout[j].tabItem.identifier {
				if oldLayout[i].width > 0 || newLayout[j].width > 0 {
					tabs.append(Tab(tabItem: oldLayout[i].tabItem, oldWidth: oldLayout[i].width, newWidth: newLayout[j].width))
				}
				i += 1
				j += 1
			} else {
				NSLog("interpolatedLayout *** assertion failure for \(oldLayout[i].tabItem) != \(newLayout[j].tabItem)")
				break
			}
		}

		var oldX0: CGFloat = 0, newX0: CGFloat = 0, x0: CGFloat = 0
		for k in tabs.indices {
			let oldX1 = oldX0 + tabs[k].oldWidth
			let newX1 = newX0 + tabs[k].newWidth

			let x1 = oldX1 + (fraction * (newX1 - oldX1)).rounded()
			tabs[k].currentWidth = x1 - x0

			x0    = x1
			oldX0 = oldX1
			newX0 = newX1
		}

		return tabs.map { OakTabFrame(tabItem: $0.tabItem, width: $0.currentWidth) }
	}

	private func makeLayout(for layoutTabItems: [OakTabItem], inRectOfWidth totalWidthIn: CGFloat) -> [OakTabFrame] {
		let totalWidth = totalWidthIn + 1 // We place leftmost tab at position -1

		var array: [OakTabFrame] = []
		if CGFloat(maximumTabSize) * CGFloat(layoutTabItems.count) <= totalWidth {
			for i in 0..<layoutTabItems.count {
				array.append(OakTabFrame(tabItem: layoutTabItems[i], width: CGFloat(maximumTabSize)))
			}
		} else {
			var supply: CGFloat = 0, demand: CGFloat = 0

			for i in 0..<layoutTabItems.count {
				let x0 = (totalWidth * CGFloat(i + 0) / CGFloat(layoutTabItems.count)).rounded()
				let x1 = (totalWidth * CGFloat(i + 1) / CGFloat(layoutTabItems.count)).rounded()
				let width = x1 - x0

				if width < layoutTabItems[i].fittingWidth {
					demand += layoutTabItems[i].fittingWidth - width
				} else {
					supply += width - layoutTabItems[i].fittingWidth
				}
			}

			var counter: CGFloat = 0
			for i in 0..<layoutTabItems.count {
				let x0 = (totalWidth * CGFloat(i + 0) / CGFloat(layoutTabItems.count)).rounded()
				let x1 = (totalWidth * CGFloat(i + 1) / CGFloat(layoutTabItems.count)).rounded()
				var width = x1 - x0

				if supply != 0, demand != 0 {
					if supply <= demand {
						if layoutTabItems[i].fittingWidth < width {
							width = layoutTabItems[i].fittingWidth
						} else {
							let a0 = (supply * counter / demand).rounded()
							counter += layoutTabItems[i].fittingWidth - width
							let a1 = (supply * counter / demand).rounded()
							width += a1 - a0
						}
					} else if width < layoutTabItems[i].fittingWidth {
						width = layoutTabItems[i].fittingWidth
					} else {
						let a0 = (demand * counter / supply).rounded()
						counter += width - layoutTabItems[i].fittingWidth
						let a1 = (demand * counter / supply).rounded()
						width -= a1 - a0
					}
				}

				array.append(OakTabFrame(tabItem: layoutTabItems[i], width: width))
			}
		}
		return array
	}

	private static let firstTabIdentifier = UUID().uuidString

	private func makeLayout() -> [OakTabFrame] {
		let visibleWidth = NSWidth(bounds) - NSWidth(createNewTabButton.frame)

		// Clamp in the floating-point domain, then convert — never the other way
		// round. `minimumTabSize` is the user default `tabItemMinWidth`, so a zero
		// (or negative) value is reachable, and the division is then ±infinity or
		// NaN. The ObjC++ original ran MIN/MAX first and only narrowed to
		// NSUInteger afterwards, so it tolerated that; Swift's checked Int()
		// conversion traps on a non-representable value and would take the app
		// down at launch. Matches the original for every case, NaN included
		// (MAX(0, NaN) is 0 there, because the NaN comparison is false).
		let slots = (visibleWidth / CGFloat(minimumTabSize)).rounded(.down)
		let visibleTabCount: Int
		if slots.isNaN || slots < 0 {
			visibleTabCount = 0
		} else if slots >= CGFloat(tabItems.count) {
			visibleTabCount = tabItems.count
		} else {
			visibleTabCount = Int(slots)
		}

		var layoutTabItems: [OakTabItem] = []
		var didIncludeSelected = tabItems.filter { $0.selected }.isEmpty
		var visibleCount = 0
		for i in 0...tabItems.count {
			if i == _dropTabAtIndex {
				let identifier = _dropTabAtIndex == 0 ? Self.firstTabIdentifier : (tabItems[_dropTabAtIndex - 1].identifier ?? "") + ".margin"
				layoutTabItems.append(OakTabItem(title: "", path: nil, identifier: identifier, modified: false))
			}

			if i == tabItems.count {
				break
			}

			let tabItem = tabItems[i]
			tabItem.tabView?.overflowButtonVisible = false

			if visibleCount >= visibleTabCount || (tabItems.count > visibleTabCount && visibleCount + 1 == visibleTabCount && !tabItem.selected && !didIncludeSelected) {
				continue
			}

			visibleCount += 1
			didIncludeSelected = didIncludeSelected || tabItem.selected

			if i == _draggedTabIndex {
				continue
			}

			layoutTabItems.append(tabItem)
		}

		// The number of document tabs this layout admits. `visibleCount` includes a
		// tab being dragged out — it still occupies one of the visible slots — but
		// not the dummy margin item inserted at a drop target, which is not a
		// document. See the note on the property for what this used to report.
		countOfVisibleTabs = visibleCount

		var existingTabViews: [String: OakTabView] = [:]
		for tabFrame in currentLayout {
			if let id = tabFrame.tabItem.identifier, let tv = tabFrame.tabItem.tabView {
				existingTabViews[id] = tv
			}
		}

		for tabItem in layoutTabItems {
			if tabItem.tabView == nil {
				if let id = tabItem.identifier, let reused = existingTabViews[id] {
					tabItem.tabView = reused
					existingTabViews[id] = nil
				} else {
					let tabView = OakTabView(frame: .zero, tabItem: tabItem, parent: self)
					tabView.target       = self
					tabView.action       = #selector(didSingleClickTabView(_:))
					tabView.doubleAction = #selector(didDoubleClickTabView(_:))
					tabView.dragAction   = #selector(didDragTabView(_:))

					tabItem.tabView = tabView
					addSubview(tabView)
				}
			}

			if tabItem.needsLayout {
				tabItem.fittingWidth = tabItem.tabView?.fittingSize.width ?? 0
				tabItem.needsLayout = false
			}
		}

		if tabItems.count > visibleTabCount {
			layoutTabItems.last?.tabView?.overflowButtonVisible = true
		}

		let res = makeLayout(for: layoutTabItems, inRectOfWidth: visibleWidth)

		if freezeTabFramesLeftOfIndex > 0 {
			let frozenTabIdentifiers = Set(tabItems.prefix(min(freezeTabFramesLeftOfIndex, tabItems.count)).compactMap { $0.identifier })
			for tabFrame in res {
				if let id = tabFrame.tabItem.identifier, frozenTabIdentifiers.contains(id) {
					if let tabView = tabFrame.tabItem.tabView, NSWidth(tabView.frame) > 0 {
						tabFrame.width = NSWidth(tabView.frame)
					}
				}
			}
		}

		return res
	}

	@objc dynamic func updateToLayout(_ newLayout: [OakTabFrame]) {
		if NSAnimationContext.current.allowsImplicitAnimation {
			fromLayout = currentLayout
			toLayout   = newLayout

			tabLayoutAnimationProgressOffset = tabLayoutAnimationProgress
			oakAnimator.tabLayoutAnimationProgress = tabLayoutAnimationProgress + 1
		} else {
			fromLayout = newLayout
			toLayout   = newLayout
			currentLayout = interpolatedLayout(fromLayout, withFraction: 1, ofLayout: toLayout)
		}
	}

	private var currentLayout: [OakTabFrame] = [] {
		didSet {
			var existingTabViews: [String: OakTabView] = [:]
			for tabFrame in oldValue {
				if let id = tabFrame.tabItem.identifier, let tv = tabFrame.tabItem.tabView {
					existingTabViews[id] = tv
				}
			}

			for tabFrame in currentLayout {
				if let id = tabFrame.tabItem.identifier, let tv = tabFrame.tabItem.tabView, tv == existingTabViews[id] {
					existingTabViews[id] = nil
				}
			}

			for tabView in existingTabViews.values {
				tabView.tabItem?.tabView = nil
				tabView.removeFromSuperview()
			}

			let createNewTabButtonFrame = createNewTabButton.frame
			var x: CGFloat = -1
			let y = NSMinY(bounds) + 1
			let height = NSHeight(bounds) - 1

			for tabFrame in currentLayout {
				tabFrame.tabItem.tabView?.tabItem = tabFrame.tabItem
				tabFrame.tabItem.tabView?.frame = NSMakeRect(x, y, tabFrame.width, height)
				x += tabFrame.width
			}

			backgroundView.frame = NSMakeRect(x, y, NSWidth(bounds) + 2 - x, height)
			createNewTabButton.frame = NSRect(origin: NSMakePoint(x, ((height - NSHeight(createNewTabButtonFrame)) / 2).rounded()), size: createNewTabButtonFrame.size)
		}
	}

	override func resizeSubviews(withOldSize oldSize: NSSize) {
		super.resizeSubviews(withOldSize: oldSize)
		if !NSEqualSizes(bounds.size, oldSize) {
			updateToLayout(makeLayout())
		}
	}
}
