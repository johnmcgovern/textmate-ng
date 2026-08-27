import AppKit

// Ported from OTVHUD.mm — the grey rounded overlay showing the line number while
// the scroller is dragged. C++-free, so no boundary file.
//
// Two things are load-bearing and invisible when lost, both pinned in
// t_otv_hud.mm: the HUD is *cached* per view rather than rebuilt, and its label
// is sized from a dummy "88888" at construction so later numbers do not make it
// jump.
//
// The class's ObjC face is the hand declaration in OTVHUD.h (rule 23).

private class OTVHUDView: NSView {
	override func draw(_ aRect: NSRect) {
		NSColor(calibratedWhite: 0.5, alpha: 0.5).set()
		NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
	}
}

@objc(OTVHUD)
class OTVHUD: NSWindowController {
	private var textField: NSTextField!
	private var requestID: UInt = 0

	@objc weak var lastView: NSView?

	@objc(initWithView:)
	init?(view aView: NSView) {
		let kWidth:  CGFloat = 100
		let kHeight: CGFloat = 30

		// A view with no window still builds a HUD, at a nonsense position. That is
		// what the ObjC++ did — messaging nil for a struct return yields a zeroed
		// NSRect — and bailing out here instead would be a behaviour change no test
		// covers, since every caller passes a hosted view.
		let viewRect = aView.convert(aView.visibleRect, to: nil)
		var aRect = aView.window.map { $0.convertToScreen(viewRect) } ?? .zero
		aRect = aRect.insetBy(dx: 10, dy: 10)
		aRect = NSRect(x: aRect.maxX - kWidth, y: aRect.maxY - kHeight, width: kWidth, height: kHeight)

		// The ObjC++'s `if(!window) return nil;` is unreachable here: NSWindow's
		// initialiser is non-optional in Swift. The initialiser stays failable so the
		// ObjC signature keeps its nullability rather than widening it.
		let window = NSWindow(contentRect: aRect, styleMask: .borderless, backing: .buffered, defer: false)

		super.init(window: window)

		lastView = aView

		window.ignoresMouseEvents = true
		window.backgroundColor    = NSColor.clear
		window.isOpaque           = false
		window.level              = .popUpMenu

		let contentView = OTVHUDView(frame: aRect)
		window.contentView = contentView

		textField = OakCreateLabel("", NSFont.systemFont(ofSize: 20), .left, .byTruncatingMiddle)
		// Sized from a dummy that is as wide as any line number it will show, so the
		// label does not resize as the number changes.
		setStringValue("88888")

		textField.sizeToFit()
		let textHeight = textField.frame.height
		textField.frame = NSRect(x: 0, y: round((kHeight - textHeight) / 2), width: kWidth, height: textHeight)

		contentView.addSubview(textField)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	// A setter with no getter, as it was: nothing reads it back.
	@objc(setStringValue:)
	func setStringValue(_ someText: String) {
		let pStyle = NSMutableParagraphStyle()
		pStyle.alignment = .center

		let shadow = NSShadow()
		shadow.shadowColor      = NSColor.darkGray
		shadow.shadowOffset     = NSSize(width: 1, height: -1)
		shadow.shadowBlurRadius = 1.2

		textField.objectValue = NSMutableAttributedString(string: someText, attributes: [
			.paragraphStyle:  pStyle,
			.foregroundColor: NSColor.white,
			.shadow:          shadow,
		])
	}

	@objc func fadeOut(_ sender: Any?) {
		// Captured by value: a later -showWindow: bumps the counter, and the fade
		// that was already in flight then finds itself stale and leaves the window
		// open rather than closing one that has just been reused.
		let requestID = self.requestID

		NSAnimationContext.beginGrouping()
		NSAnimationContext.current.completionHandler = { [weak self] in
			MainActor.assumeIsolated {
				guard let self, requestID == self.requestID else {
					return
				}
				self.close()
			}
		}
		window?.animator().alphaValue = 0
		NSAnimationContext.endGrouping()
	}

	override func showWindow(_ sender: Any?) {
		requestID += 1
		NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(fadeOut(_:)), object: nil)

		NSAnimationContext.beginGrouping()
		NSAnimationContext.current.duration = 0
		window?.animator().alphaValue = 1
		NSAnimationContext.endGrouping()

		super.showWindow(sender)

		perform(#selector(fadeOut(_:)), with: nil, afterDelay: 1)
	}

	// Weak, so the cache never keeps a HUD (or its window) alive on its own.
	private static weak var lastHUD: OTVHUD?

	@objc(showHudForView:withText:)
	class func showHud(forView aView: NSView, withText someText: String) -> OTVHUD? {
		var res = lastHUD
		// Rebuilt when the view changed, because the window's position is computed
		// from that view at construction and never again.
		if res == nil || res?.lastView !== aView {
			res = OTVHUD(view: aView)
			lastHUD = res
		}

		res?.setStringValue(someText)
		res?.showWindow(self)
		return res
	}
}
