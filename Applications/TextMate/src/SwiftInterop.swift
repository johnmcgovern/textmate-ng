// Phase 3 proof-of-life: the first Swift in the tree, calling both layers the
// migration cares about — a C++ core API (text::pad, via the TMText Clang
// module) and an ObjC API (OakNotEmptyString, via the bridging header).
// AppController logs the result once at startup; no user-visible behavior.
import Foundation
import TMText

@objc(TMSwiftInterop) final class SwiftInterop: NSObject {
	@objc static func interopDescription() -> String {
		// C++ layer: text::pad(42, 4) → "␠␠42" (figure-space padded, 4 digits wide)
		let padded = String(text.pad(42, 4))
		let cxx = padded.hasSuffix("42") && padded.count == 4
			? "c++ ok (text::pad → “\(padded)”)"
			: "c++ BROKEN (text::pad → “\(padded)”)"
		// ObjC layer: OakFoundation's empty-string predicate, both branches
		let objc = OakNotEmptyString("swift") && !OakNotEmptyString(nil)
			? "objc ok (OakNotEmptyString)"
			: "objc BROKEN (OakNotEmptyString)"
		return "swift⇄interop: \(cxx); \(objc)"
	}
}
