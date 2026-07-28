// A flat solid-colour view used for the tab bar's separators and backgrounds.
//
// Keeps both drawing paths from the original: layer-backed via updateLayer when
// the view is layer-backed (cheap, no redraw), and drawRect: otherwise.
import AppKit

@objc(OakBox) final class OakBox: NSView {
	@objc var fillColor: NSColor? {
		didSet { needsDisplay = true }
	}

	override var wantsUpdateLayer: Bool { true }

	override func updateLayer() {
		layer?.backgroundColor = fillColor?.cgColor
	}

	override func draw(_ dirtyRect: NSRect) {
		fillColor?.set()
		NSBezierPath.fill(dirtyRect)
	}
}
