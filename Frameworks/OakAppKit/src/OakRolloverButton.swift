import AppKit

// Ported from OakRolloverButton.mm. Six images, two booleans, and one derived
// pair of outputs.
//
// The notification names did not come with it: Swift cannot export an `extern`
// constant (rule 19), so they stayed in OakRolloverButtonConstants.mm and this
// file posts them by the names the importer gives them. The class's ObjC face is
// the hand declaration in OakRolloverButton.h (rule 23), which is why every
// member below is `@objc dynamic` (rule 50).
//
// What the port is not allowed to tidy is in `updateImage`, and
// t_rollover_button.mm — written against the ObjC++ before this file existed —
// holds it in place.

private enum OakImageState: Int, CaseIterable {
	case regular = 0
	case pressed
	case rollover
	case inactiveRegular
	case inactivePressed
	case inactiveRollover
}

@objc(OakRolloverButton)
class OakRolloverButton: NSButton {
	// The ObjC++ held these in a C array ivar, `NSImage* _images[OakImageStateCount]`,
	// indexed by the same enum.
	private var images = [NSImage?](repeating: nil, count: OakImageState.allCases.count)
	private var currentTrackingArea: NSTrackingArea?

	// MARK: - The two booleans everything is a function of

	// Neither is public: callers set images and the button works out the rest.
	// Both are reachable from ObjC because the tests drive them through a
	// category (OakAppKitTesting.h) — the same arrangement OakFinderTag uses.
	@objc dynamic var active: Bool = false {
		didSet {
			guard oldValue != active else { return }
			updateImage()
		}
	}

	@objc dynamic var mouseInside: Bool = false {
		didSet {
			guard oldValue != mouseInside else { return }
			updateImage()
			NotificationCenter.default.post(name: mouseInside ? .OakRolloverButtonMouseDidEnter : .OakRolloverButtonMouseDidLeave, object: self)
		}
	}

	// MARK: - The six image slots

	@objc dynamic var regularImage: NSImage? {
		get { images[OakImageState.regular.rawValue] }
		set { setImage(newValue, forState: .regular) }
	}

	@objc dynamic var pressedImage: NSImage? {
		get { images[OakImageState.pressed.rawValue] }
		set { setImage(newValue, forState: .pressed) }
	}

	@objc dynamic var rolloverImage: NSImage? {
		get { images[OakImageState.rollover.rawValue] }
		set { setImage(newValue, forState: .rollover) }
	}

	@objc dynamic var inactiveRegularImage: NSImage? {
		get { images[OakImageState.inactiveRegular.rawValue] }
		set { setImage(newValue, forState: .inactiveRegular) }
	}

	@objc dynamic var inactivePressedImage: NSImage? {
		get { images[OakImageState.inactivePressed.rawValue] }
		set { setImage(newValue, forState: .inactivePressed) }
	}

	@objc dynamic var inactiveRolloverImage: NSImage? {
		get { images[OakImageState.inactiveRollover.rawValue] }
		set { setImage(newValue, forState: .inactiveRollover) }
	}

	@objc dynamic var disableWindowOrderingForFirstMouse: Bool = false

	// MARK: - Construction

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)

		setButtonType(.momentaryChange)
		isBordered = false

		// All four Required, so the button never stretches or squeezes inside the
		// stack views that hold it.
		setContentCompressionResistancePriority(.required, for: .horizontal)
		setContentCompressionResistancePriority(.required, for: .vertical)
		setContentHuggingPriority(.required, for: .horizontal)
		setContentHuggingPriority(.required, for: .vertical)
	}

	// The ObjC++ configured itself in -initWithFrame: only, so a coder-loaded
	// button was never configured either. Kept that way rather than quietly
	// fixed: nothing in this tree loads one from a nib, and making the two paths
	// agree is a behaviour change, not a translation.
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	// MARK: - Deriving -image and -alternateImage

	private func setImage(_ image: NSImage?, forState state: OakImageState) {
		guard images[state.rawValue] !== image else { return }
		images[state.rawValue] = image
		updateImage()
	}

	private func updateImage() {
		var image    = images[OakImageState.regular.rawValue]
		var altImage = images[OakImageState.pressed.rawValue]

		if mouseInside {
			image = images[OakImageState.rollover.rawValue] ?? image
			if !active {
				image = images[OakImageState.inactiveRollover.rawValue] ?? image
			}
			// Note what does *not* happen here: the alternate stays the active
			// pressed image. An inactive button under the pointer shows
			// `pressedImage` while it is held, never `inactivePressedImage`,
			// because that assignment lives in the branch below that this one has
			// already claimed.
		}
		else if !active {
			image    = images[OakImageState.inactiveRegular.rawValue] ?? image
			// `?? image`, not `?? altImage` — and `image` was just reassigned on
			// the line above. With no inactive artwork the alternate becomes the
			// *regular* image and the button stops visibly reacting to a click,
			// which is what an inactive window's close button is supposed to do.
			altImage = images[OakImageState.inactivePressed.rawValue] ?? image
		}

		self.image          = image
		self.alternateImage = altImage
	}

	// MARK: - First-mouse ordering and the context-menu forward

	override func shouldDelayWindowOrdering(for event: NSEvent) -> Bool {
		return disableWindowOrderingForFirstMouse
	}

	override func menu(for event: NSEvent) -> NSMenu? {
		// Control-clicks are not sent to superview <rdar://20200363>
		return superview?.menu(for: event)
	}

	override func mouseDown(with event: NSEvent) {
		if disableWindowOrderingForFirstMouse {
			NSApp.preventWindowOrdering()
		}
		super.mouseDown(with: event)
	}

	// MARK: - Following the pointer

	override var isHidden: Bool {
		get { super.isHidden }
		set {
			super.isHidden = newValue
			// `!newValue &&` first: hiding always clears the flag without
			// consulting the hit test, so the button cannot come back rolled-over
			// after being hidden under the pointer.
			mouseInside = !newValue && NSMouseInRect(convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil), visibleRect, isFlipped)
		}
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()

		mouseInside = NSMouseInRect(convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil), visibleRect, isFlipped)

		if let currentTrackingArea {
			removeTrackingArea(currentTrackingArea)
		}

		var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
		if mouseInside {
			options.insert(.assumeInside)
		}

		let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
		addTrackingArea(area)
		currentTrackingArea = area
	}

	override func mouseEntered(with event: NSEvent) {
		mouseInside = true
	}

	override func mouseExited(with event: NSEvent) {
		mouseInside = false
	}

	// MARK: - Following the window

	// No super call, as in the ObjC++. NSView's implementation does nothing here
	// and adding the call would be a change this port is not making.
	override func viewWillMove(toWindow newWindow: NSWindow?) {
		if let window {
			for name in Self.windowActivationNotifications {
				NotificationCenter.default.removeObserver(self, name: name, object: window)
			}
		}

		if let newWindow {
			for name in Self.windowActivationNotifications {
				NotificationCenter.default.addObserver(self, selector: #selector(windowDidChangeMainOrKey(_:)), name: name, object: newWindow)
			}
		}

		active = Self.isActive(newWindow)
	}

	@objc private dynamic func windowDidChangeMainOrKey(_ notification: Notification) {
		active = Self.isActive(window)
	}

	private static let windowActivationNotifications: [NSNotification.Name] = [
		NSWindow.didBecomeMainNotification,
		NSWindow.didResignMainNotification,
		NSWindow.didBecomeKeyNotification,
		NSWindow.didResignKeyNotification,
	]

	// Full screen counts as active even though such a window is often neither
	// main nor key while another space has focus.
	private static func isActive(_ window: NSWindow?) -> Bool {
		guard let window else { return false }
		return window.styleMask.contains(.fullScreen) || window.isMainWindow || window.isKeyWindow
	}
}
