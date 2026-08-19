import AppKit

// The splitter that arranges a project window: the document view in the middle,
// the file browser pinned to one side, and HTML output either beside it or
// underneath. The dividers between them are draggable, which is done here by
// hand rather than with NSSplitView.
//
// The only C++ in the ObjC++ was three `std::max<CGFloat>`, which is Swift's
// `max` — so this file needed no support file, the FFResultsViewController shape
// rather than the FindSupport one.
//
// The two grab strips (-fileBrowserResizeRect / -htmlOutputResizeRect) are the
// part with real coverage, because everything about dragging depends on them and
// nothing about them is visible to a build: get them wrong and the divider stops
// being draggable while the window still lays out perfectly. Their 3pt/4pt
// asymmetry is deliberate — see t_project_layout.mm.

private let kUserDefaultsFileBrowserWidthKey = "fileBrowserWidth"
private let kUserDefaultsHTMLOutputSizeKey   = "htmlOutputSize"

@objc(ProjectLayoutView)
class ProjectLayoutView: NSView, @preconcurrency OakUserDefaultsObserver {

	// +initialize has no Swift spelling. Registering on first construction is
	// equivalent here because nothing reads these keys before a layout view
	// exists — they are not declared in any header, and were file-scope `const`
	// in the ObjC++, which is internal linkage in C++ and so was never exported
	// in the first place.
	private static let registerDefaults: Void = {
		UserDefaults.standard.register(defaults: [
			kUserDefaultsFileBrowserWidthKey: 250,
			kUserDefaultsHTMLOutputSizeKey:   NSStringFromSize(NSSize(width: 200, height: 200)),
		])
	}()

	private var fileBrowserDivider: NSView?
	@objc private(set) var htmlOutputDivider: NSView?
	private var fileBrowserWidthConstraint: NSLayoutConstraint?
	private var htmlOutputSizeConstraint: NSLayoutConstraint?
	private var myConstraints: [NSLayoutConstraint] = []
	private var mouseDownRecursionGuard = false

	@objc var documentView: NSView? {
		didSet {
			documentView = replaceView(oldValue, with: documentView)
			updateKeyViewLoop()
		}
	}

	@objc var fileBrowserView: NSView? {
		didSet {
			fileBrowserDivider = replaceView(fileBrowserDivider, with: fileBrowserView != nil ? createDivider(alongYAxis: true) : nil)
			fileBrowserView    = replaceView(oldValue, with: fileBrowserView)
			updateKeyViewLoop()
		}
	}

	@objc var htmlOutputView: NSView? {
		didSet {
			htmlOutputDivider = replaceView(htmlOutputDivider, with: htmlOutputView != nil ? createDivider(alongYAxis: htmlOutputOnRight) : nil)
			htmlOutputView    = replaceView(oldValue, with: htmlOutputView)
			updateKeyViewLoop()
		}
	}

	@objc var fileBrowserWidth: CGFloat = 0
	@objc var htmlOutputSize: NSSize = .zero

	@objc var fileBrowserOnRight: Bool = false {
		didSet {
			guard fileBrowserOnRight != oldValue else { return }
			if fileBrowserView != nil {
				needsUpdateConstraints = true
			}
		}
	}

	@objc var htmlOutputOnRight: Bool = false {
		didSet {
			guard htmlOutputOnRight != oldValue else { return }
			// Re-runs the view setter, which rebuilds the divider — required due to
			// <rdar://13093498>, since a reused divider keeps its old axis. Assigning
			// the same value still runs `didSet`, which is what makes this work; the
			// temporary is only because Swift rejects the literal self-assignment the
			// ObjC++ wrote.
			let view = htmlOutputView
			htmlOutputView = view
		}
	}

	override init(frame frameRect: NSRect) {
		_ = ProjectLayoutView.registerDefaults
		super.init(frame: frameRect)

		fileBrowserWidth = CGFloat(UserDefaults.standard.integer(forKey: kUserDefaultsFileBrowserWidthKey))
		htmlOutputSize   = NSSizeFromString(UserDefaults.standard.string(forKey: kUserDefaultsHTMLOutputSizeKey) ?? "")

		userDefaultsDidChange(nil)
		OakObserveUserDefaults(self)
	}

	required init?(coder: NSCoder) {
		fatalError("ProjectLayoutView is built in code, not loaded from a nib")
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	@objc func userDefaultsDidChange(_ aNotification: Notification!) {
		htmlOutputOnRight = UserDefaults.standard.string(forKey: kUserDefaultsHTMLOutputPlacementKey) == "right"
	}

	// Returns the view that ended up installed, so a caller can assign it back —
	// the ObjC++ idiom, kept because the setters above rely on it to leave the
	// stored property holding what is actually in the hierarchy.
	private func replaceView(_ oldView: NSView?, with newView: NSView?) -> NSView? {
		if newView == oldView {
			return oldView
		}

		oldView?.removeFromSuperview()
		if let newView {
			OakAddAutoLayoutViewsToSuperview([ newView ], self)
		}

		needsUpdateConstraints = true
		return newView
	}

	private func updateKeyViewLoop() {
		OakSetupKeyViewLoop([ documentView, htmlOutputView, fileBrowserView ].compactMap { $0 })
	}

	private func createDivider(alongYAxis flag: Bool) -> NSView {
		let res = OakCreateNSBoxSeparator()!
		res.translatesAutoresizingMaskIntoConstraints = false
		res.addConstraint(NSLayoutConstraint(item: res, attribute: flag ? .width : .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 1))
		res.addConstraint(NSLayoutConstraint(item: res, attribute: flag ? .height : .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 2))
		return res
	}

	// =================
	// = Constraints   =
	// =================

	override func updateConstraints() {
		removeConstraints(myConstraints)
		myConstraints.removeAll()
		super.updateConstraints()

		// NSNull stands in for an absent view, as in the ObjC++: the format strings
		// below only name a view when the branch that uses it is taken, so the
		// placeholder is never actually resolved.
		let views: [String: Any] = [
			"documentView":       documentView       ?? NSNull(),
			"fileBrowserView":    fileBrowserView    ?? NSNull(),
			"fileBrowserDivider": fileBrowserDivider ?? NSNull(),
			"htmlOutputView":     htmlOutputView     ?? NSNull(),
			"htmlOutputDivider":  htmlOutputDivider  ?? NSNull(),
		]

		func constrain(_ format: String, _ options: NSLayoutConstraint.FormatOptions = []) {
			myConstraints.append(contentsOf: NSLayoutConstraint.constraints(withVisualFormat: format, options: options, metrics: nil, views: views))
		}

		// ========================
		// = Anchor Document View =
		// ========================

		// top
		constrain("V:|[documentView]")

		// bottom
		if htmlOutputView != nil && !htmlOutputOnRight {
			constrain("V:[documentView][htmlOutputDivider]")
		} else {
			constrain("V:[documentView]|")
		}

		// left
		if fileBrowserView != nil && !fileBrowserOnRight {
			constrain("H:[fileBrowserDivider][documentView]")
		} else {
			constrain("H:|[documentView]")
		}

		// right
		if htmlOutputView != nil && htmlOutputOnRight {
			constrain("H:[documentView][htmlOutputDivider]")
		} else if fileBrowserView != nil && fileBrowserOnRight {
			constrain("H:[documentView][fileBrowserDivider]")
		} else {
			constrain("H:[documentView]|")
		}

		// =======================
		// = Anchor File Browser =
		// =======================

		if let fileBrowserView {
			// width
			let widthConstraint = NSLayoutConstraint(item: fileBrowserView, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: fileBrowserWidth)
			widthConstraint.priority = .dragThatCannotResizeWindow
			fileBrowserWidthConstraint = widthConstraint
			myConstraints.append(widthConstraint)

			// top
			constrain("V:|[fileBrowserDivider]")
			constrain("V:|[fileBrowserView]")

			// bottom
			if htmlOutputView != nil && !htmlOutputOnRight {
				constrain("V:[fileBrowserView][htmlOutputDivider]")
				constrain("V:[fileBrowserDivider][htmlOutputDivider]")
			} else {
				constrain("V:[fileBrowserView]|")
				constrain("V:[fileBrowserDivider]|")
			}

			// left
			if fileBrowserOnRight && htmlOutputView != nil && htmlOutputOnRight {
				constrain("H:[htmlOutputView][fileBrowserDivider][fileBrowserView]")
			} else if fileBrowserOnRight {
				constrain("H:[documentView][fileBrowserDivider][fileBrowserView]")
			} else {
				constrain("H:|[fileBrowserView][fileBrowserDivider]")
			}

			// right
			if fileBrowserOnRight {
				constrain("H:[fileBrowserView]|")
			} else {
				constrain("H:[fileBrowserDivider][documentView]")
			}
		}

		// ===========================
		// = Anchor HTML Output View =
		// ===========================

		if let htmlOutputView {
			// size (either width or height)
			let sizeConstraint = htmlOutputOnRight
				? NSLayoutConstraint(item: htmlOutputView, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: htmlOutputSize.width)
				: NSLayoutConstraint(item: htmlOutputView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: htmlOutputSize.height)
			sizeConstraint.priority = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.dragThatCannotResizeWindow.rawValue - 1)
			htmlOutputSizeConstraint = sizeConstraint
			myConstraints.append(sizeConstraint)

			if htmlOutputOnRight {
				// top + bottom
				constrain("V:|[htmlOutputView]|")
				constrain("V:|[htmlOutputDivider]|")

				// left + right
				if fileBrowserView != nil && fileBrowserOnRight {
					constrain("H:[documentView][htmlOutputDivider][htmlOutputView][fileBrowserDivider]")
				} else {
					constrain("H:[documentView][htmlOutputDivider][htmlOutputView]|")
				}
			} else {
				// top + bottom
				constrain("V:[documentView][htmlOutputDivider][htmlOutputView]|")

				// left + right
				constrain("H:|[htmlOutputView]|")
				constrain("H:|[htmlOutputDivider]|")
			}
		}

		addConstraints(myConstraints)
		window?.invalidateCursorRects(for: self)
	}

	// =================
	// = Grab strips   =
	// =================

	@objc var fileBrowserResizeRect: NSRect {
		guard let fileBrowserView else { return .zero }
		let r = fileBrowserView.frame
		return NSRect(x: fileBrowserOnRight ? NSMinX(r) - 3 : NSMaxX(r) - 4, y: NSMinY(r), width: 10, height: NSHeight(r))
	}

	@objc var htmlOutputResizeRect: NSRect {
		guard let htmlOutputView else { return .zero }
		let r = htmlOutputView.frame
		return htmlOutputOnRight
			? NSRect(x: NSMinX(r) - 3, y: NSMinY(r), width: 10, height: NSHeight(r))
			: NSRect(x: NSMinX(r), y: NSMaxY(r) - 4, width: NSWidth(r), height: 10)
	}

	override func resetCursorRects() {
		addCursorRect(fileBrowserResizeRect, cursor: .resizeLeftRight)
		addCursorRect(htmlOutputResizeRect, cursor: htmlOutputOnRight ? .resizeLeftRight : .resizeUpDown)
	}

	override var mouseDownCanMoveWindow: Bool { false }

	override func hitTest(_ aPoint: NSPoint) -> NSView? {
		if let superview {
			let point = convert(aPoint, from: superview)
			if NSMouseInRect(point, fileBrowserResizeRect, isFlipped) { return self }
			if NSMouseInRect(point, htmlOutputResizeRect, isFlipped) { return self }
		}
		return super.hitTest(aPoint)
	}

	// The drag, run as a modal event loop rather than through mouseDragged: —
	// carried over as-is. `didDrag` and the 2.5pt threshold together are what let
	// a click on the divider fall through to whatever is underneath.
	override func mouseDown(with anEvent: NSEvent) {
		if mouseDownRecursionGuard { return }
		mouseDownRecursionGuard = true
		defer { mouseDownRecursionGuard = false }

		var event = anEvent
		var view: NSView?
		let mouseDownPos = convert(anEvent.locationInWindow, from: nil)
		if NSMouseInRect(mouseDownPos, fileBrowserResizeRect, isFlipped) {
			view = fileBrowserView
		} else if NSMouseInRect(mouseDownPos, htmlOutputResizeRect, isFlipped) {
			view = htmlOutputView
		}

		guard let view, anEvent.type == .leftMouseDown else {
			super.mouseDown(with: anEvent)
			return
		}

		if let fileBrowserView {
			fileBrowserWidthConstraint?.constant = NSWidth(fileBrowserView.frame)
			fileBrowserWidthConstraint?.priority = .dragThatCannotResizeWindow
		}

		if let htmlOutputView {
			htmlOutputSizeConstraint?.constant = htmlOutputOnRight ? NSWidth(htmlOutputView.frame) : NSHeight(htmlOutputView.frame)
			htmlOutputSizeConstraint?.priority = .dragThatCannotResizeWindow
		}

		let mouseDownEvent = anEvent
		let initialFrame = view.frame

		var didDrag = false
		while event.type != .leftMouseUp {
			guard let next = NSApp.nextEvent(matching: [ .leftMouseDragged, .leftMouseDown, .leftMouseUp ], until: .distantFuture, inMode: .eventTracking, dequeue: true) else { break }
			event = next
			if event.type != .leftMouseDragged { break }

			let mouseCurrentPos = convert(event.locationInWindow, from: nil)
			if !didDrag && hypot(mouseDownPos.x - mouseCurrentPos.x, mouseDownPos.y - mouseCurrentPos.y) < 2.5 {
				continue
			}

			if view == htmlOutputView {
				if htmlOutputOnRight {
					let width = NSWidth(initialFrame) + (mouseCurrentPos.x - mouseDownPos.x) * -1
					htmlOutputSize.width = max(50, width.rounded())
					htmlOutputSizeConstraint?.constant = width
				} else {
					let height = NSHeight(initialFrame) + (mouseCurrentPos.y - mouseDownPos.y)
					htmlOutputSize.height = max(50, height.rounded())
					htmlOutputSizeConstraint?.constant = height
				}
				htmlOutputSizeConstraint?.priority = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.dragThatCannotResizeWindow.rawValue - 1)

				UserDefaults.standard.set(NSStringFromSize(htmlOutputSize), forKey: kUserDefaultsHTMLOutputSizeKey)
			} else if view == fileBrowserView {
				let width = NSWidth(initialFrame) + (mouseCurrentPos.x - mouseDownPos.x) * (fileBrowserOnRight ? -1 : +1)
				fileBrowserWidth = max(50, width.rounded())
				fileBrowserWidthConstraint?.constant = fileBrowserWidth
				fileBrowserWidthConstraint?.priority = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.dragThatCannotResizeWindow.rawValue - 1)

				UserDefaults.standard.set(Int(fileBrowserWidth), forKey: kUserDefaultsFileBrowserWidthKey)
			}

			window?.invalidateCursorRects(for: self)
			didDrag = true
		}

		if !didDrag, let superview {
			let hit = super.hitTest(superview.convert(mouseDownEvent.locationInWindow, from: nil))
			if let hit, hit != self {
				NSApp.postEvent(event, atStart: false)
				hit.mouseDown(with: mouseDownEvent)
			}
		}

		fileBrowserWidthConstraint?.priority = .dragThatCannotResizeWindow
		htmlOutputSizeConstraint?.priority   = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.dragThatCannotResizeWindow.rawValue - 1)
	}

	@objc func performClose(_ sender: Any?) {
		let responder = window?.firstResponder
		if let view = responder as? NSView, let htmlOutputView, view.isDescendant(of: htmlOutputView) {
			NSApp.sendAction(Selector(("performCloseSplit:")), to: nil, from: htmlOutputView)
		} else if let delegate = window?.delegate, delegate.responds(to: #selector(performClose(_:))) {
			delegate.perform(#selector(performClose(_:)), with: sender)
		} else {
			NSSound.beep()
		}
	}
}
