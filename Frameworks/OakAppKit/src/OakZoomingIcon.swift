// The icon that flies out and fades when a file is dragged away or revealed —
// a borderless window holding one layer, which animates itself and then closes.
//
// Pinned by t_appkit_leaves.mm, which asserts the window configuration rather
// than the animation: the window closes itself ~0.25s in, so what is worth
// testing is how it was built.
import AppKit
import QuartzCore

@objc(OakZoomingIcon)
final class OakZoomingIcon: NSWindow {

	@objc(zoomIcon:fromRect:)
	class func zoomIcon(_ icon: NSImage, fromRect aRect: NSRect) -> OakZoomingIcon {
		return OakZoomingIcon(icon: icon, rect: aRect)
	}

	init(icon: NSImage, rect aRect: NSRect) {
		// 56 points of slack on every side is the room the zoom needs to grow into.
		super.init(contentRect: NSInsetRect(aRect, -56, -56), styleMask: .borderless, backing: .buffered, defer: false)

		isReleasedWhenClosed = false
		ignoresMouseEvents   = true
		backgroundColor      = .clear
		isOpaque             = false
		level                = .popUpMenu

		guard let view = contentView else { return }
		view.wantsLayer = true

		let layer = CALayer()
		view.layer?.addSublayer(layer)

		guard let image = icon.copy() as? NSImage else { return }
		image.size = view.bounds.size

		layer.bounds   = CGRect(origin: .zero, size: aRect.size)
		layer.position = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
		layer.contents = image

		orderFront(self)

		// Layer properties changed in this run loop cycle will not be animated
		perform(#selector(runAnimation(_:)), with: layer, afterDelay: 0)
	}

	@objc func runAnimation(_ layer: CALayer) {
		// Holding Shift slows it tenfold — a debugging affordance from upstream,
		// kept because it costs nothing and someone will want it again.
		let duration = 0.25 * ((NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false) ? 10.0 : 1.0)

		CATransaction.begin()
		CATransaction.setAnimationDuration(duration)
		CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeIn))

		CATransaction.setCompletionBlock { [self] in
			close()
		}

		layer.bounds  = contentView?.bounds ?? .zero
		layer.opacity = 0

		CATransaction.commit()
	}
}
