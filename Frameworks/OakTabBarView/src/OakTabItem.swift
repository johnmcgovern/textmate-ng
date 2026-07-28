// The tab bar's model object: one open document's tab.
//
// It is also the drag payload — OakTabBarView drags tabs between windows, so
// OakTabItem is an NSPasteboardWriting and round-trips through a plist. The
// pasteboard type string is a wire format shared with the *reading* side
// (OakTabBarView.mm's drop handling), so it stays exactly as it was.
import AppKit
import UniformTypeIdentifiers

@objc(OakTabItem) final class OakTabItem: NSObject, NSPasteboardWriting {
	/// Wire format. Changing this breaks drags from an older build of the app
	/// into a newer one; it also carries the bundle id, which moved to
	/// com.j23software during Stream 3.
	@objc static let pasteboardType = NSPasteboard.PasteboardType("com.j23software.TextMate.tabItem")

	@objc private(set) var identifier: String?
	@objc var path: String?

	// ObjC's `getter=isModified` keeps the setter as -setModified:. Swift's
	// @objc(isModified) on the *property* is NOT the same thing — it renames the
	// property, yielding -setIsModified:, and OakTabBarView.mm's `item.modified =`
	// then dies with "unrecognized selector". Annotating each accessor separately
	// is the only spelling that reproduces the ObjC pair. (Caught at runtime, not
	// by the build: the crash is on opening a second tab.)
	private var _modified: Bool
	@objc var modified: Bool {
		@objc(isModified) get { _modified }
		@objc(setModified:) set { _modified = newValue }
	}

	private var _selected = false
	@objc var selected: Bool {
		@objc(isSelected) get { _selected }
		@objc(setSelected:) set { _selected = newValue }
	}

	@objc var fittingWidth: CGFloat = 0
	@objc var needsLayout: Bool
	@objc weak var tabView: OakTabView?

	@objc var title: String? {
		didSet {
			guard title != oldValue else { return }
			needsLayout = true
		}
	}

	@objc init(title: String?, path: String?, identifier: String?, modified: Bool) {
		self.title = title
		self.path = path
		self.identifier = identifier
		self._modified = modified
		self.needsLayout = true
		super.init()
	}

	@objc(tabItemWithTitle:path:identifier:modified:)
	static func tabItem(title: String?, path: String?, identifier: String?, modified: Bool) -> OakTabItem {
		OakTabItem(title: title, path: path, identifier: identifier, modified: modified)
	}

	@objc(tabItemFromPasteboardItem:)
	static func tabItem(from pasteboardItem: NSPasteboardItem) -> OakTabItem? {
		guard let plist = pasteboardItem.propertyList(forType: pasteboardType) as? [String: Any] else { return nil }
		return OakTabItem(title: plist["title"] as? String,
		                  path: plist["path"] as? String,
		                  identifier: plist["identifier"] as? String,
		                  modified: (plist["modified"] as? Bool) ?? false)
	}

	override var description: String {
		"<\(type(of: self)): \(title ?? "")>"
	}

	// =====================
	// = NSPasteboardWriting =
	// =====================

	func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
		// A tab with no file on disk is only draggable within the app; one with a
		// path also writes a file URL so it can be dropped on Finder or elsewhere.
		guard let path, !path.isEmpty else { return [Self.pasteboardType] }
		return [Self.pasteboardType, NSPasteboard.PasteboardType(UTType.fileURL.identifier)]
	}

	func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
		[]
	}

	func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
		if type.rawValue == UTType.fileURL.identifier {
			guard let path else { return nil }
			return URL(fileURLWithPath: path).absoluteString
		}

		// Nil entries are omitted rather than written as NSNull, matching the
		// original's `dict[key] = value ?: nil` idiom — the reader treats a
		// missing "modified" as false and a missing "path" as an untitled tab.
		var dict: [String: Any] = [:]
		dict["identifier"] = identifier
		dict["title"] = title
		if let path, !path.isEmpty { dict["path"] = path }
		if modified { dict["modified"] = true }
		return dict
	}
}
