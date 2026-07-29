// One tab in the bar: an NSView carrying a single OakTabItem, drawing its
// title, close and overflow buttons and the hairline borders. It is the
// clickable/​draggable surface — clicks and drags are forwarded to the parent
// OakTabBarView through target/action.
//
// Ported from OakTabBarView.mm (2026-07-28). Internal to the framework; the
// only external types it touches are the Swift OakTabItem/OakBox (same module)
// and OakRolloverButton (OakAppKit, via the bridging header).
import AppKit

// Implicit animation is off inside this block. Used for the one-shot appearance
// setup in init and for the mouse-inside flip when a tab is un-hidden, so those
// don't animate the way the tracking-area driven changes deliberately do.
private func disableImplicitAnimation(_ handler: @escaping () -> Void) {
	NSAnimationContext.runAnimationGroup({ context in
		context.allowsImplicitAnimation = false
		handler()
	}, completionHandler: nil)
}

// Not declared `NSAccessibilityRadioButton` — under Swift 6 that conformance
// crosses main-actor isolation. The radio-button role is established at runtime
// via setAccessibilityRole(.radioButton) plus the accessibility* overrides
// below, which is what VoiceOver actually reads; the marker protocol added
// nothing on top of that.
final class OakTabView: NSView {
	weak var tabBarView: OakTabBarView?

	weak var target: AnyObject?
	var action: Selector?
	var doubleAction: Selector?
	var dragAction: Selector?

	// KVO tokens for the current tabItem's title/path/modified/selected. Rebuilt
	// whenever tabItem changes; they invalidate themselves when replaced or when
	// this view is deallocated, which is why there is no deinit teardown (a
	// @MainActor class cannot touch its own state from deinit under Swift 6).
	private var tabItemObservations: [NSKeyValueObservation] = []
	private var voiceOverObservation: NSKeyValueObservation?

	// closeButtonAlphaValue depends on these (see the KVO dependent-key method
	// below), and the close button's alpha is bound to it — so they must be
	// `dynamic` for the binding to update.
	@objc dynamic var tabItem: OakTabItem? {
		didSet {
			tabItemObservations = []
			if let item = tabItem {
				// Read the new value from self.tabItem inside the isolated region
				// rather than from the observed object the @Sendable handler is
				// passed — forwarding that non-Sendable object across isolation is
				// a data race, and self.tabItem is the same object anyway (tokens
				// are rebuilt whenever tabItem changes). Mirrors the ObjC
				// observeValue:, which also read from self.tabItem.
				tabItemObservations = [
					item.observe(\.title, options: [.initial]) { [weak self] _, _ in
						MainActor.assumeIsolated { self?.updateTitle() }
					},
					item.observe(\.path, options: [.initial]) { [weak self] _, _ in
						MainActor.assumeIsolated { self?.updateToolTip() }
					},
					item.observe(\.modified, options: [.initial]) { [weak self] _, _ in
						MainActor.assumeIsolated { self?.updateModifiedFromItem() }
					},
					item.observe(\.selected, options: [.initial]) { [weak self] _, _ in
						MainActor.assumeIsolated { self?.updateSelectedFromItem() }
					},
				]

				setAccessibilityElement(true)
				closeButton.cell?.setAccessibilityElement(true)
				overflowButton.cell?.setAccessibilityElement(true)
			} else {
				setAccessibilityElement(false)
				closeButton.cell?.setAccessibilityElement(false)
				overflowButton.cell?.setAccessibilityElement(false)

				textField.alphaValue      = 0.0
				backgroundView.alphaValue  = 0.1
				topBorderView.alphaValue   = 1
				overflowButtonVisible      = false
			}
		}
	}

	@objc dynamic var selected: Bool = false {
		didSet {
			guard oldValue != selected else { return }
			textField.alphaValue     = selected ? 1 : 0.5
			backgroundView.alphaValue = selected ? 0 : (mouseInside ? 0.2 : 0.1)
			topBorderView.alphaValue  = selected ? 0 : 1
		}
	}

	@objc dynamic var modified: Bool = false {
		didSet { updateCloseButtonImage() }
	}

	var overflowButtonVisible: Bool = false {
		didSet {
			overflowButton.isHidden = !overflowButtonVisible
			if overflowButtonVisible {
				NSLayoutConstraint.activate(overflowButtonConstraints)
			} else {
				NSLayoutConstraint.deactivate(overflowButtonConstraints)
			}
		}
	}

	@objc dynamic var mouseInside: Bool = false {
		didSet {
			guard oldValue != mouseInside else { return }
			if !selected, tabItem != nil {
				backgroundView.alphaValue = mouseInside ? 0.2 : 0.1
			}
		}
	}

	@objc dynamic var voiceOverEnabled: Bool = false

	private var overflowButtonConstraints: [NSLayoutConstraint] = []

	let backgroundView = OakBox(frame: .zero)
	let topBorderView  = OakBox(frame: .zero)
	let leftBorderView = OakBox(frame: .zero)
	let textField: NSTextField

	private var _closeButton: OakRolloverButton?
	var closeButton: OakRolloverButton {
		if let button = _closeButton { return button }
		let button = OakRolloverButton(frame: .zero)
		button.setAccessibilityLabel("Close tab")
		button.action = #selector(didClickCloseButton(_:))
		button.target = self
		button.disableWindowOrderingForFirstMouse = true
		_closeButton = button
		updateCloseButtonImage()
		return button
	}

	private var _overflowButton: OakRolloverButton?
	var overflowButton: OakRolloverButton {
		if let button = _overflowButton { return button }
		let button = OakRolloverButton(frame: .zero)
		button.sendAction(on: .leftMouseDown)
		button.setAccessibilityLabel("Show tab overflow menu")
		button.action = #selector(didClickOverflorButton(_:))
		button.target = self
		button.regularImage = tabImage("TabOverflowThinTemplate")
		_overflowButton = button
		return button
	}

	private var trackingArea: NSTrackingArea?
	private var mouseDownLocation: NSPoint = .zero

	// Route implicit animations through the OakAnimatorProxy, which wraps the
	// standard animator in an allowsImplicitAnimation group. The proxy is an
	// NSProxy typed as OakTabView so `.mouseInside = …` dispatches (mouseInside
	// is `dynamic`, which forces objc_msgSend and reaches the proxy's
	// -forwardInvocation:). Only this class calls it, on itself.
	private var oakAnimator: OakTabView {
		unsafeBitCast(OakAnimatorProxy(realObject: self.animator()), to: OakTabView.self)
	}

	@objc class func keyPathsForValuesAffectingCloseButtonAlphaValue() -> Set<String> {
		["tabItem", "mouseInside", "modified", "voiceOverEnabled"]
	}

	init(frame frameRect: NSRect, tabItem: OakTabItem?, parent tabBarView: OakTabBarView?) {
		self.textField = OakCreateLabel("", nil, .left, .byTruncatingMiddle)
		super.init(frame: frameRect)

		setAccessibilityRole(.radioButton)
		setAccessibilityRoleDescription("Tab")

		self.tabBarView = tabBarView

		disableImplicitAnimation {
			self.backgroundView.fillColor  = NSColor.textColor
			self.backgroundView.alphaValue = self.selected ? 0 : (self.mouseInside ? 0.2 : 0.1)
			self.topBorderView.fillColor   = NSColor(calibratedWhite: 0.0, alpha: 0.25)
			self.leftBorderView.fillColor  = NSColor(calibratedWhite: 0.0, alpha: 0.25)

			self.textField.textColor  = NSColor.secondaryLabelColor
			self.textField.alphaValue = self.selected ? 1 : 0.5
		}

		let subviews: [NSView] = [backgroundView, topBorderView, leftBorderView, textField, closeButton, overflowButton]
		for view in subviews {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view, positioned: .above, relativeTo: nil)
		}

		overflowButton.isHidden = true

		voiceOverObservation = NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: [.initial]) { [weak self] workspace, _ in
			let enabled = workspace.isVoiceOverEnabled
			MainActor.assumeIsolated { self?.voiceOverEnabled = enabled }
		}

		let views: [String: Any] = [
			"background": backgroundView,
			"topBorder":  topBorderView,
			"leftBorder": leftBorderView,
			"close":      closeButton,
			"title":      textField,
			"overflow":   overflowButton,
		]

		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[leftBorder(==1@75)][topBorder]|", options: .alignAllTop, metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[topBorder(==1@75)][background]|", options: [.alignAllLeft, .alignAllRight], metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[leftBorder]|", options: [], metrics: nil, views: views))

		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(3@53)-[close]-(>=3@53)-[title]-(>=6@53)-|", options: [], metrics: nil, views: views))

		overflowButtonConstraints = NSLayoutConstraint.constraints(withVisualFormat: "H:[title]-(>=3@53)-[overflow]", options: [], metrics: nil, views: views)
		NSLayoutConstraint.deactivate(overflowButtonConstraints)
		addConstraints(overflowButtonConstraints)

		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:[overflow]|", options: [], metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[close]-(4)-|", options: [], metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[title]-(3)-|", options: [], metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[overflow]|", options: [], metrics: nil, views: views))

		textField.setContentHuggingPriority(.required, for: .horizontal)
		textField.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.fittingSizeCompression.rawValue + 2), for: .horizontal)

		let centerTitleConstraint = NSLayoutConstraint(item: textField, attribute: .centerX, relatedBy: .equal, toItem: self, attribute: .centerX, multiplier: 1, constant: 0)
		centerTitleConstraint.priority = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.fittingSizeCompression.rawValue + 1)
		addConstraint(centerTitleConstraint)

		self.tabItem = tabItem
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private func tabImage(_ name: String) -> NSImage? {
		Bundle(for: OakTabView.self).image(forResource: NSImage.Name(name))
	}

	private func updateTitle() {
		textField.stringValue = tabItem?.title ?? ""
	}

	private func updateToolTip() {
		if let path = tabItem?.path {
			toolTip = (path as NSString).abbreviatingWithTildeInPath
		} else {
			toolTip = nil
		}
	}

	private func updateModifiedFromItem() {
		modified = tabItem?.modified ?? false
	}

	private func updateSelectedFromItem() {
		selected = tabItem?.selected ?? false
	}

	override var isHidden: Bool {
		didSet {
			guard oldValue != isHidden, !isHidden else { return }
			disableImplicitAnimation {
				if let window = self.window {
					self.mouseInside = NSMouseInRect(self.convert(window.mouseLocationOutsideOfEventStream, from: nil), self.visibleRect, self.isFlipped)
				}
			}
		}
	}

	private func updateCloseButtonImage() {
		guard let button = _closeButton else { return }
		if modified {
			button.regularImage  = tabImage("TabCloseThin_Modified_Template")
			button.pressedImage  = tabImage("TabCloseThin_ModifiedPressed_Template")
			button.rolloverImage = tabImage("TabCloseThin_ModifiedRollover_Template")
		} else {
			button.regularImage  = tabImage("TabCloseThinTemplate")
			button.pressedImage  = tabImage("TabCloseThin_Pressed_Template")
			button.rolloverImage = tabImage("TabCloseThin_Rollover_Template")
		}
	}

	@objc dynamic var closeButtonAlphaValue: CGFloat {
		tabItem != nil && (mouseInside || modified || voiceOverEnabled) ? 1 : 0
	}

	// MARK: - Accessibility

	override func accessibilityLabel() -> String? {
		guard let tabItem else { return nil }
		return tabItem.modified ? (tabItem.title ?? "") + " (modified)" : tabItem.title
	}

	override func accessibilityValue() -> Any? {
		NSNumber(value: selected)
	}

	override func accessibilityPerformPress() -> Bool {
		guard let action else { return false }
		return NSApp.sendAction(action, to: target, from: self)
	}

	override func accessibilityPerformShowMenu() -> Bool {
		guard let event = NSApp.currentEvent else { return false }
		menu(for: event)?.popUp(positioning: nil, at: .zero, in: self)
		return true
	}

	// MARK: - Window activation

	override func viewWillMove(toWindow newWindow: NSWindow?) {
		if let window = window {
			// Break retain-cycle when view is removed from window
			closeButton.unbind(NSBindingName("alphaValue"))

			NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeMainNotification, object: window)
			NotificationCenter.default.removeObserver(self, name: NSWindow.didResignMainNotification, object: window)
			NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
			NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
		}

		if let newWindow {
			closeButton.bind(NSBindingName("alphaValue"), to: self, withKeyPath: "closeButtonAlphaValue", options: nil)

			for name: NSNotification.Name in [NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
				NotificationCenter.default.addObserver(self, selector: #selector(windowDidChangeMainOrKey(_:)), name: name, object: newWindow)
			}
		}
	}

	@objc func windowDidChangeMainOrKey(_ notification: Notification) {
		let isActive = (window?.isKeyWindow ?? false) || (window?.isMainWindow ?? false) || isInFullScreenMode
		textField.textColor = isActive ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor
	}

	// MARK: - Hit testing & mouse

	override func hitTest(_ point: NSPoint) -> NSView? {
		// This is required to receive menuForEvent: when control-clicking the text field (right click works)
		let result = super.hitTest(point)
		return result == textField ? self : result
	}

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
		true
	}

	override func shouldDelayWindowOrdering(for event: NSEvent) -> Bool {
		true
	}

	override func mouseEntered(with event: NSEvent) {
		oakAnimator.mouseInside = true
	}

	override func mouseExited(with event: NSEvent) {
		oakAnimator.mouseInside = false
	}

	override func mouseDown(with event: NSEvent) {
		mouseDownLocation = event.locationInWindow
	}

	override func otherMouseDown(with event: NSEvent) {
		tabBarView?.didClickCloseButton(for: self)
	}

	override func mouseDragged(with event: NSEvent) {
		if let dragAction, mouseDownLocation != .zero, hypot(mouseDownLocation.x - event.locationInWindow.x, mouseDownLocation.y - event.locationInWindow.y) >= 2.5 {
			NSApp.sendAction(dragAction, to: target, from: self)
			mouseDownLocation = .zero
		}
	}

	override func mouseUp(with event: NSEvent) {
		if mouseDownLocation == .zero { // Ignore mouse up after a dragging session
			return
		} else if event.clickCount == 1, !selected, hypot(mouseDownLocation.x - event.locationInWindow.x, mouseDownLocation.y - event.locationInWindow.y) < 2.5 {
			if let action { NSApp.sendAction(action, to: target, from: self) }
		} else if event.clickCount == 2 {
			if let doubleAction { NSApp.sendAction(doubleAction, to: target, from: self) }
		}
	}

	@objc func didClickCloseButton(_ sender: Any?) {
		tabBarView?.didClickCloseButton(for: self)
	}

	@objc func didClickOverflorButton(_ sender: Any?) {
		tabBarView?.didClickOverflowButton(for: self)
	}

	override func menu(for event: NSEvent) -> NSMenu? {
		tabBarView?.menu(for: self, with: event)
	}

	// MARK: - Tracking areas

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea {
			removeTrackingArea(trackingArea)
		}

		var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
		if tabBarView?.dragging != true {
			var isInside = false
			if let window {
				isInside = NSMouseInRect(convert(window.mouseLocationOutsideOfEventStream, from: nil), visibleRect, isFlipped)
			}
			if isInside {
				options.insert(.assumeInside)
			}
			if mouseInside != isInside {
				oakAnimator.mouseInside = isInside
			}
		}

		let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
		addTrackingArea(area)
		trackingArea = area
	}

	// MARK: - Drag image

	var dragImage: NSImage? {
		let boundsRect = backgroundView.frame
		if boundsRect.isEmpty {
			return nil
		}

		let image = NSImage(size: boundsRect.size)
		image.lockFocusFlipped(isFlipped)

		overflowButton.isHidden    = true
		textField.alphaValue       = 1.0
		backgroundView.alphaValue  = 0.1
		topBorderView.alphaValue   = 1

		displayIgnoringOpacity(boundsRect, in: NSGraphicsContext.current!)

		overflowButton.isHidden    = !overflowButtonVisible
		textField.alphaValue       = selected ? 1 : 0.5
		backgroundView.alphaValue  = selected ? 0 : (mouseInside ? 0.2 : 0.1)
		topBorderView.alphaValue   = selected ? 0 : 1

		image.unlockFocus()
		return image
	}
}
