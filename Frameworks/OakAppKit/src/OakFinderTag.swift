// Finder's file tags: the coloured labels shown beside filenames in the file
// browser, read from the `com.apple.metadata:_kMDItemUserTags` extended
// attribute and from Finder's own favourites list.
//
// Pinned by t_appkit_leaves.mm, which covers the label→colour table by value,
// both xattr shapes, and the equality rule. That table is the reason the tests
// were written first: a port that renumbers it compiles, runs, and silently
// recolours every tagged file in the project.
import AppKit

@objc(OakFinderTag)
final class OakFinderTag: NSObject, NSCopying {

	@objc var displayName: String
	@objc private(set) var label: UInt

	@objc init(displayName name: String, label: UInt) {
		self.displayName = name
		self.label = label
	}

	@objc(tagWithDisplayName:label:)
	class func tag(displayName name: String, label: UInt) -> OakFinderTag {
		return OakFinderTag(displayName: name, label: label)
	}

	// `label != 0`, which deliberately does *not* agree with -labelColor for an
	// out-of-range label. Carried over: nothing constructs one, and the tests say
	// so out loud rather than letting a future reader "fix" it.
	@objc func hasLabelColor() -> Bool {
		return label != 0
	}

	@objc var labelColor: NSColor? {
		switch label {
			case 1:  return .systemGray
			case 2:  return .systemGreen
			case 3:  return .systemPurple
			case 4:  return .systemBlue
			case 5:  return .systemYellow
			case 6:  return .systemRed
			case 7:  return .systemOrange
			default: return nil
		}
	}

	func copy(with zone: NSZone? = nil) -> Any {
		return OakFinderTag(displayName: displayName, label: label)
	}

	// Equality is by display name alone, so a tag renamed in Finder still matches
	// one read from an older xattr. The label is not part of it.
	override var hash: Int {
		return (displayName as NSString).hash
	}

	override func isEqual(_ otherObject: Any?) -> Bool {
		guard let other = otherObject as? OakFinderTag else { return false }
		return displayName == other.displayName
	}

	override var description: String {
		return "<\(type(of: self)): \(displayName) (\(label))>"
	}
}

@objc(OakFinderTagManager)
final class OakFinderTagManager: NSObject {

	@objc(finderTagsForURL:)
	class func finderTags(for aURL: URL) -> [OakFinderTag] {
		// The filePathURL guard and the NULL_STR check both live in the shim, which
		// returns nil for "no such attribute" — by far the common case.
		guard let data = OakUserTagsAttributeForURL(aURL) else { return [] }
		return finderTags(from: data)
	}

	// Finder writes an array of strings, each either "Name" or "Name\n<label>";
	// both shapes occur in real files.
	@objc(finderTagsFromData:)
	class func finderTags(from data: Data) -> [OakFinderTag] {
		guard let plist = (try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(), format: nil)) as? [String] else {
			return []
		}

		var finderTags: [OakFinderTag] = []
		for tag in plist {
			let components = tag.components(separatedBy: "\n")
			if components.count == 2 {
				finderTags.append(OakFinderTag(displayName: components[0], label: UInt(components[1]) ?? 0))
			} else {
				finderTags.append(OakFinderTag(displayName: components[0], label: 0))
			}
		}
		return finderTags
	}

	@objc class func favoriteFinderTags() -> [OakFinderTag] {
		// A std::map in the ObjC++; the order is irrelevant because it is only ever
		// a lookup. These are Finder's seven built-in colours by name.
		let labelColors: [String: UInt] = [
			"Gray": 1, "Green": 2, "Purple": 3, "Blue": 4,
			"Yellow": 5, "Red": 6, "Orange": 7,
		]

		let finderDefaults = UserDefaults(suiteName: "com.apple.finder")
		// Without the fallback, a machine that has never customised Finder's
		// favourites would offer no tags at all rather than the standard seven.
		let favoriteTagNames = finderDefaults?.stringArray(forKey: "FavoriteTagNames")
			?? [ "Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray" ]

		var tags: [OakFinderTag] = []
		for name in favoriteTagNames {
			if !OakNotEmptyString(name) {
				continue
			}
			tags.append(OakFinderTag(displayName: name, label: labelColors[name] ?? 0))
		}
		return tags
	}
}
