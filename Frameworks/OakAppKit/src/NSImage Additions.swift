// +imageNamed:inSameBundleAsClass: — load an image from the bundle a class came
// from, rather than the main bundle. Every framework here ships its own gfx, so
// +imageNamed: alone finds nothing.
//
// Pinned by t_appkit_leaves.mm for the two nil paths.
import AppKit

extension NSImage {

	// The cache is keyed by "<bundle identifier>.<name>" so two frameworks
	// shipping an image of the same name do not collide. Main-actor isolated
	// rather than `nonisolated(unsafe)` because every caller is drawing code.
	@MainActor private static var bundleImageCache: [String: NSImage] = [:]

	@objc(imageNamed:inSameBundleAsClass:)
	@MainActor class func imageNamed(_ aName: String?, inSameBundleAsClass aClass: Any?) -> NSImage? {
		guard let aName = aName else {
			return nil
		}

		let bundle = Bundle(for: type(of: aClass as AnyObject) as! AnyClass)
		let name = "\(bundle.bundleIdentifier ?? "").\(aName)"

		if let res = bundleImageCache[name] {
			return res
		}

		if let image = bundle.image(forResource: aName) {
			bundleImageCache[name] = image
			return image
		}

		return nil
	}
}
