// A panel that refuses to look inactive, used for tooltip and pop-up chrome
// that has to stay visibly live while the real key window is elsewhere.
//
// Pinned by t_appkit_leaves.mm.
import AppKit

@objc(OakBorderlessPanel)
class OakBorderlessPanel: NSPanel {

	// The ObjC++ read as two operations — OR in Borderless, mask out Titled — but
	// **NSWindowStyleMaskBorderless is 0**, so the first was a no-op and always had
	// been. Borderless is the *absence* of Titled, not a bit beside it. Only the
	// mask-out is kept, because only the mask-out ever did anything; a test
	// written against the ObjC++ asserted the intent, failed, and is now written
	// against this.
	override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing backingType: NSWindow.BackingStoreType, defer flag: Bool) {
		var styleMask = styleMask
		styleMask.remove(.titled)
		super.init(contentRect: contentRect, styleMask: styleMask, backing: backingType, defer: flag)
	}

	override var isKeyWindow: Bool { true }
}
