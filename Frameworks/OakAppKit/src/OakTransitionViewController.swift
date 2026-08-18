// A container that swaps one subview for another, resizing its window to match
// and cross-fading between them. The Find window's results pane and the
// select-grammar strip are hosted in these.
//
// The only C++ was a `std::set<NSView*>` guarding the key-view-loop walk against
// a cycle; that is a Set of ObjectIdentifier here, which is the same identity
// comparison a pointer set was doing.
import AppKit

// **Not `final`, and that is a bug fix rather than a style choice.** This class
// is exported to ObjC through a hand-written OakTransitionViewController.h
// (rule 23), and Preferences' bridging header imports it — so
// PreferencesViewController subclasses what its module sees as an ordinary ObjC
// class. ObjC has no `final`, so nothing stopped it, and Swift meanwhile
// compiled the initialisers on the assumption that no subclass could exist.
//
// The result was an unbounded recursion between
// `init(nibName:bundle:)` and its own @objc thunk — 58,000 frames and a
// segfault the moment anyone opened Settings, in every build from alpha.10
// onwards. `final` on a class that ObjC can see is only true if nothing ever
// subclasses it, and nothing enforces that.
@objc(OakTransitionViewController)
class OakTransitionViewController: NSViewController {

	private var animationCounter: UInt = 0
	private var viewFrameConstraints: [NSLayoutConstraint]?
	private var hostedSubviews: [NSView] = []

	@objc var subview: NSView? {
		get { _subview }
		set { setSubview(newValue) }
	}
	private var _subview: NSView?

	override func loadView() {
		view = NSView(frame: .zero)
		let constraints = [ view.heightAnchor.constraint(equalToConstant: 0) ]
		NSLayoutConstraint.activate(constraints)
		viewFrameConstraints = constraints
	}

	private func setSubview(_ newView: NSView?) {
		if _subview === newView {
			return
		}

		let window = view.window
		if let subview = _subview, let responder = window?.firstResponder as? NSView, responder.isDescendant(of: subview) {
			window?.makeFirstResponder(window)
		}

		if let newView = newView {
			if NSEqualSizes(.zero, newView.frame.size) {
				newView.frame = NSRect(origin: .zero, size: newView.fittingSize)
			}

			newView.translatesAutoresizingMaskIntoConstraints = false
			newView.wantsLayer = true
			newView.alphaValue = 0

			view.addSubview(newView)
			hostedSubviews.append(newView)
		}

		// Only update the key view loop if we are part of it
		if view.nextKeyView != nil {
			var avoidLoop = Set<ObjectIdentifier>()

			var lastOldView: NSView = view
			var walk = _subview
			while let v = walk, v.isDescendant(of: view), avoidLoop.insert(ObjectIdentifier(v)).inserted {
				lastOldView = v
				walk = v.nextKeyView
			}

			var lastNewView: NSView?
			walk = newView
			while let v = walk, v.isDescendant(of: view), avoidLoop.insert(ObjectIdentifier(v)).inserted {
				lastNewView = v
				walk = v.nextKeyView
			}

			if newView != nil {
				lastNewView?.nextKeyView = lastOldView.nextKeyView
			}
			view.nextKeyView = newView ?? lastOldView.nextKeyView
			if lastOldView !== view {
				lastOldView.nextKeyView = nil
			}
		}

		let oldSize = view.frame.size
		let newSize = newView?.frame.size ?? NSSize(width: oldSize.width, height: 0)
		var newFrame = NSOffsetRect(NSInsetRect(window?.frame ?? .zero, (oldSize.width - newSize.width) / 2, (oldSize.height - newSize.height) / 2), (newSize.width - oldSize.width) / 2, (oldSize.height - newSize.height) / 2)

		// Keep the resized window on screen: nudge it back inside, then clip.
		let screenFrame = (view.window?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
		if NSMinX(newFrame) < NSMinX(screenFrame) {
			newFrame.origin.x += NSMinX(screenFrame) - NSMinX(newFrame)
		} else if NSMaxX(newFrame) > NSMaxX(screenFrame) {
			newFrame.origin.x -= NSMaxX(newFrame) - NSMaxX(screenFrame)
		}
		if NSMinY(newFrame) < NSMinY(screenFrame) {
			newFrame.origin.y += NSMinY(screenFrame) - NSMinY(newFrame)
		} else if NSMaxY(newFrame) > NSMaxY(screenFrame) {
			newFrame.origin.y -= NSMaxY(newFrame) - NSMaxY(screenFrame)
		}
		newFrame = NSIntersectionRect(newFrame, screenFrame)

		var newConstraints: [NSLayoutConstraint] = []
		for view in hostedSubviews {
			guard let superview = view.superview else { continue }
			newConstraints.append(contentsOf: [
				view.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
				view.topAnchor.constraint(equalTo: superview.topAnchor),
				view.widthAnchor.constraint(equalToConstant: NSWidth(view.frame)),
				view.heightAnchor.constraint(equalToConstant: NSHeight(view.frame)),
			])
		}

		if let viewFrameConstraints = viewFrameConstraints {
			NSLayoutConstraint.deactivate(viewFrameConstraints)
		}
		viewFrameConstraints = newConstraints
		NSLayoutConstraint.activate(newConstraints)

		animationCounter += 1
		let animationCounter = self.animationCounter

		let animationBody = { [self] (animated: Bool) in
			_subview?.alphaValue = 0
			_subview = newView
			newView?.alphaValue = 1
			if animated {
				window?.setFrame(newFrame, display: true, animate: true)
			} else {
				window?.setFrame(newFrame, display: true)
			}
		}

		let animationCompletion = { [self] in
			// A second swap started while this one was running: leave the newer one's
			// constraints alone.
			guard animationCounter == self.animationCounter else { return }

			if let viewFrameConstraints = viewFrameConstraints {
				NSLayoutConstraint.deactivate(viewFrameConstraints)
			}
			viewFrameConstraints = nil

			for view in hostedSubviews where view !== newView {
				view.removeFromSuperview()
			}
			hostedSubviews.removeAll()

			if let newView = newView, let superview = newView.superview {
				hostedSubviews.append(newView)

				let constraints = [
					newView.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
					newView.bottomAnchor.constraint(equalTo: superview.bottomAnchor),
					newView.topAnchor.constraint(equalTo: superview.topAnchor),
					newView.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
				]
				NSLayoutConstraint.activate(constraints)
				viewFrameConstraints = constraints
			} else {
				let constraints = [ view.heightAnchor.constraint(equalToConstant: 0) ]
				NSLayoutConstraint.activate(constraints)
				viewFrameConstraints = constraints
			}
		}

		if let window = window, window.isVisible {
			NSAnimationContext.runAnimationGroup({ context in
				context.allowsImplicitAnimation = true
				context.duration                = 0.2
				// `false`, not `true` — the ObjC++ passes NO here even inside the
				// animation group, leaving the frame change to the implicit animation
				// rather than -setFrame:display:animate:.
				animationBody(false)
			}, completionHandler: animationCompletion)
		} else {
			animationBody(false)
			animationCompletion()
		}
	}
}
