// One file row: path, SCM status, and whether it is included in the commit.
// Properties are @objc dynamic because the table reaches them through Cocoa
// bindings ("objectValue.path" etc.) and the controller KVO-observes
// "arrangedObjects.commit" — both need the ObjC KVC/KVO machinery.
import Foundation

@objc(CWItem) class CWItem: NSObject, NSCopying {
	@objc dynamic var path: String
	@objc dynamic var commit: Bool
	@objc dynamic var scmStatus: String

	@objc init(path: String, scmStatus: String, commit: Bool) {
		self.path = (path as NSString).standardizingPath
		self.scmStatus = scmStatus
		self.commit = commit
	}

	func copy(with zone: NSZone? = nil) -> Any {
		CWItem(path: path, scmStatus: scmStatus, commit: commit)
	}

	@objc func compare(_ item: CWItem) -> ComparisonResult {
		(path as NSString).compare(item.path)
	}
}
