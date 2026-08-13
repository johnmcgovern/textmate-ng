// The "found it" flash TextMate draws over a match: a borderless child window
// holding a yellow rounded rect and a snapshot image, which grows, fades, and
// closes itself.
//
// `OakShowPopOutAnimation` stays in OakPopOutAnimation.mm and is three lines
// long. It cannot move here: it is a C++ free function with a default argument
// (`BOOL hidePrevious = YES`), Swift has no way to declare a global function
// visible to ObjC at all, and OakTextView.mm calls it both with and without the
// last argument. Changing that signature would be a change to a public API for
// the convenience of the port, which is the wrong trade — so the entry point
// keeps its exact shape and forwards here.
//
// Pinned by t_pop_out.mm, which was written against the ObjC++ and is unchanged
// by this port: five tests covering the degenerate-rect no-op, the child-window
// bookkeeping, hide-previous vs keep-previous, and dismissal on scroll.
import AppKit
import QuartzCore

private let kExtendWidth:  CGFloat = 4
private let kExtendHeight: CGFloat = 1
private let kRectXRadius:  CGFloat = 2
private let kRectYRadius:  CGFloat = 2
private let kMaxScale:     CGFloat = 1.3
private let kShadowRadius: CGFloat = 2

private let kGrowStartTime:  Double = 0.00
private let kGrowFinishTime: Double = 0.10
private let kFadeStartTime:  Double = 0.35
private let kFadeFinishTime: Double = 0.70

@objc(OakPopOutView)
final class OakPopOutView: NSView, @preconcurrency CAAnimationDelegate {

	// A file-static NSMutableSet in the ObjC++. Main-actor rather than
	// `nonisolated(unsafe)` because every path that touches it is AppKit calling
	// back on the main thread, and saying so is checkable where "unsafe" is not.
	@MainActor private static var previousViews: Set<OakPopOutView> = []

	// `dispatch_once` in the ObjC++, and the comment there is the reason it is
	// shared at all: animations are *copied* when added to a layer, so one group
	// serves every pop-out. A `static let` is Swift's once.
	@MainActor private static let animationGroup: CAAnimationGroup = {
		let grow = CABasicAnimation(keyPath: "transform.scale")
		grow.beginTime = kGrowStartTime
		grow.duration = (kGrowFinishTime - kGrowStartTime) / 2
		grow.fromValue = 1
		grow.toValue = kMaxScale
		grow.autoreverses = true
		grow.timingFunction = CAMediaTimingFunction(name: .easeIn)

		let fade = CABasicAnimation(keyPath: "opacity")
		fade.beginTime = kFadeStartTime
		fade.duration = kFadeFinishTime - kFadeStartTime
		fade.fromValue = 1
		fade.toValue = 0
		fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

		let group = CAAnimationGroup()
		group.animations = [ grow, fade ]
		group.duration = kFadeFinishTime
		group.fillMode = .forwards
		group.isRemovedOnCompletion = false
		return group
	}()

	private var imageLayer: CALayer!
	private var shapeLayer: CAShapeLayer!

	@objc var contentImage: NSImage?

	// What OakShowPopOutAnimation forwards to. The degenerate-rect guard is first
	// and returns without creating anything, which is the documented no-op:
	// OakTextView asks for a pop-out over whatever rect a match occupies, and an
	// empty match must not flash a window.
	@objc(showInParentView:popOutRect:image:hidePrevious:)
	class func show(inParentView parentView: NSView, popOutRect: NSRect, image: NSImage, hidePrevious: Bool) {
		var popOutRect = popOutRect
		if popOutRect.size.width == 0 || popOutRect.size.height == 0 {
			return
		}

		if hidePrevious {
			// Sending -animationDidStop:finished: by hand, with a nil animation, is
			// how the ObjC++ tore these down; the method ignores both arguments.
			for view in previousViews {
				view.animationDidStop(CAAnimation(), finished: true)
			}
			previousViews.removeAll()
		}

		popOutRect = NSInsetRect(popOutRect, -kExtendWidth, -kExtendHeight)
		var windowRect = popOutRect
		let extraWidth  = ceil((kMaxScale - 1) * (popOutRect.size.width  + 4 * kShadowRadius) / 2)
		let extraHeight = ceil((kMaxScale - 1) * (popOutRect.size.height + 4 * kShadowRadius) / 2)
		windowRect.origin.x -= extraWidth;  popOutRect.origin.x = extraWidth
		windowRect.origin.y -= extraHeight; popOutRect.origin.y = extraHeight
		windowRect.size.width  += 2 * extraWidth
		windowRect.size.height += 2 * extraHeight

		let window = NSWindow(contentRect: windowRect, styleMask: .borderless, backing: .buffered, defer: false)
		// The ObjC++ balanced isReleasedWhenClosed == YES with an explicit CFRetain:
		// the window frees itself on -close, so something has to hold it until then.
		// Unmanaged.passRetained is the same +1 and, unlike CFRetain, says so.
		_ = Unmanaged.passRetained(window)
		window.backgroundColor = .clear
		window.isExcludedFromWindowsMenu = true
		window.ignoresMouseEvents = true
		window.isOpaque = false
		window.contentView?.wantsLayer = true

		guard let contentView = window.contentView else { return }
		let aView = OakPopOutView(frame: contentView.bounds, popOutRect: popOutRect)
		aView.autoresizingMask = [ .width, .height ]

		image.lockFocus()
		NSColor.black.set()
		NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
		image.unlockFocus()

		aView.contentImage = image
		contentView.addSubview(aView)

		if let scrollView = parentView.enclosingScrollView {
			NotificationCenter.default.addObserver(aView, selector: #selector(parentViewBoundsDidChange(_:)), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
		}

		window.setFrame(window.frameRect(forContentRect: windowRect), display: true)
		parentView.window?.addChildWindow(window, ordered: .above)
		previousViews.insert(aView)

		aView.startAnimation(nil)
	}

	init(frame aRect: NSRect, popOutRect: NSRect) {
		super.init(frame: aRect)

		var shapeRect = popOutRect
		shapeRect.origin = .zero
		shapeRect = shapeRect.insetBy(dx: 0.25, dy: 0.25)
		let rectTooSmallToBeRounded = NSWidth(shapeRect) < 2 * kRectXRadius || NSHeight(shapeRect) < 2 * kRectYRadius
		let path = rectTooSmallToBeRounded
			? CGPath(rect: shapeRect, transform: nil)
			: CGPath(roundedRect: shapeRect, cornerWidth: kRectXRadius, cornerHeight: kRectYRadius, transform: nil)

		wantsLayer = true

		shapeLayer = CAShapeLayer()
		shapeLayer.frame = popOutRect
		shapeLayer.fillColor = NSColor.yellow.cgColor
		shapeLayer.strokeColor = NSColor(calibratedWhite: 0, alpha: 0.1).cgColor
		shapeLayer.lineWidth = 0.5
		shapeLayer.path = path
		shapeLayer.shadowOpacity = 0.25
		shapeLayer.shadowRadius = kShadowRadius
		shapeLayer.shadowOffset = CGSize(width: 0, height: -1)
		layer?.addSublayer(shapeLayer)

		imageLayer = CALayer()
		shapeLayer.addSublayer(imageLayer)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidMoveToWindow() {
		let scaleFactor = window?.screen?.backingScaleFactor ?? 0
		if scaleFactor != 0, let contentImage = contentImage {
			imageLayer.contents = contentImage.layerContents(forContentsScale: scaleFactor)
			imageLayer.bounds = CGRect(x: 0, y: 0, width: contentImage.size.width, height: contentImage.size.height)
			imageLayer.position = CGPoint(x: shapeLayer.bounds.midX, y: shapeLayer.bounds.midY)
		}
	}

	@objc func startAnimation(_ sender: Any?) {
		let group = Self.animationGroup
		group.delegate = self // Listen for animationDidStop:finished:
		group.speed = 1
		shapeLayer.add(group, forKey: nil)
		group.delegate = nil
	}

	func animationDidStop(_ theAnimation: CAAnimation, finished flag: Bool) {
		shapeLayer.removeAllAnimations() // Releases the animation which holds a strong reference to its delegate (us)
		window?.close()
	}

	@objc func parentViewBoundsDidChange(_ notification: Notification) {
		shapeLayer.removeAllAnimations() // Releases the animation which holds a strong reference to its delegate (us)
		window?.close()
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}
}
