// Registered by name; BundleProperties.xib binds the contact e-mail field
// through "OakRot13Transformer". rot13 is its own inverse, so both directions
// are the same call.
import Foundation

@objc(OakRot13Transformer) final class OakRot13Transformer: ValueTransformer {
	@objc static func register() {
		ValueTransformer.setValueTransformer(OakRot13Transformer(), forName: NSValueTransformerName("OakRot13Transformer"))
	}

	override class func transformedValueClass() -> AnyClass { NSString.self }
	override class func allowsReverseTransformation() -> Bool { true }

	override func transformedValue(_ value: Any?) -> Any? { BERot13(value as? String) }
	override func reverseTransformedValue(_ value: Any?) -> Any? { BERot13(value as? String) }
}
