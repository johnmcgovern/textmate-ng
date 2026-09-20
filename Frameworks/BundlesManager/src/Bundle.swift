import Foundation

// Ported from Bundle.mm — a tmbundle as the bundle index describes it, plus what
// the local index and the disk add. Pinned by t_bundle.mm, written first.
//
// `@objc(Bundle)` keeps the ObjC name every consumer and every nib-free binding
// uses; the Swift name is TMBundle, as Bundle.h's NS_SWIFT_NAME already told
// Swift consumers, so that it does not collide with Foundation's Bundle.
//
// Bundle.h stays as the hand-written declaration (rule 23) for the ObjC++
// consumers — OakDocument, AboutBundlesSupport, InstallBundleItems, the tests —
// and for the four bridging headers that import BundlesManager.h.
//
// Every stored property is `@objc dynamic` (rule 1): the Preferences table binds
// columns to `name`, `downloadLastUpdated` and `textSummary`, the manager
// filters with KVC predicates, and BundlesPreferences declares a KVO dependency
// on `installed`.
//
// The five `getter =` properties are rule 64, five times: a stored property
// spelled the KVO way, and a computed one carrying the getter selector. KVC
// reaches both — "installed" through the stored property, "isInstalled" through
// the getter, which is what the predicates spell.
@objc(Bundle)
class TMBundle: NSObject {
	@objc dynamic var identifier: UUID?
	@objc dynamic var name: String?
	@objc dynamic var minimumAppVersion: String? // E.g. ‘2.0-alpha.9519’
	@objc dynamic var category: String?
	@objc dynamic var htmlURL: URL?
	@objc dynamic var summary: String?
	@objc dynamic var contactName: String?
	@objc dynamic var contactEmail: String?
	@objc dynamic var downloadURL: URL?
	@objc dynamic var downloadLastUpdated: Date?
	// sha256 of the payload, from the signed index. This is what replaced the
	// per-archive signature that used to arrive in S3 object metadata: the index
	// is signed, the index names the digest, so the payload needs no signature
	// of its own and can be served by anything.
	@objc dynamic var downloadSHA256: String?
	@objc dynamic var downloadSize: Int = 0
	@objc dynamic var mandatory: Bool = false
	@objc var isMandatory: Bool { mandatory }
	@objc dynamic var recommended: Bool = false
	@objc var isRecommended: Bool { recommended }
	@objc dynamic var grammars: [BundleGrammar]?
	@objc dynamic var dependencies: [TMBundle]?

	// From local index
	@objc dynamic var installed: Bool = false
	@objc var isInstalled: Bool { installed }
	@objc dynamic var path: String?
	@objc dynamic var lastUpdated: Date?
	@objc dynamic var dependency: Bool = false // Another bundle depends on us
	@objc var isDependency: Bool { dependency }

	@objc override init() {
		super.init()
	}

	@objc(initWithIdentifier:)
	init(identifier: UUID?) {
		super.init()
		self.identifier = identifier
	}

	// MARK: - Identity

	// -installBundles: collects into an NSMutableSet and filters with
	// `SELF IN %@`, so equality and hash are the identifier's. `[nil isEqual:x]`
	// answered NO, so two bundles without identifiers are not equal.
	override func isEqual(_ object: Any?) -> Bool {
		guard let other = object as? TMBundle, let identifier else {
			return false
		}
		return (identifier as NSUUID).isEqual(other.identifier)
	}

	override var hash: Int {
		return (identifier as NSUUID?)?.hash ?? 0
	}

	override var description: String {
		let location = installed && path != nil ? ", " + (path ?? "") : ""
		return "<\(NSStringFromClass(type(of: self))): \(name ?? "(null)") by \(contactName ?? "(null)")\(location)>"
	}

	// MARK: - Derived values

	@objc class func keyPathsForValuesAffectingHasUpdate() -> Set<String> {
		return ["downloadLastUpdated", "lastUpdated"]
	}

	@objc class func keyPathsForValuesAffectingCompatible() -> Set<String> {
		return ["minimumAppVersion"]
	}

	@objc class func keyPathsForValuesAffectingTextSummary() -> Set<String> {
		return ["summary"]
	}

	@objc var textSummary: String? {
		return BundlesManagerSupport.textSummary(for: summary)
	}

	// The original was `[download laterDate:local] != local`, a pointer
	// comparison whose answer for two *equal* dates depended on whether NSDate
	// had handed back the same tagged pointer twice. Its pin (equal dates → NO)
	// passes because plist dates of this size are tagged; this is that answer
	// spelled as the value comparison it always meant.
	@objc var hasUpdate: Bool {
		guard let downloadLastUpdated, let lastUpdated else {
			return false
		}
		return downloadLastUpdated > lastUpdated
	}

	// Works with current version of TextMate
	@objc var isCompatible: Bool {
		let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
		return OakCompareVersionStrings(appVersion, minimumAppVersion) != .orderedAscending
	}
}

@objc(BundleGrammar)
class BundleGrammar: NSObject {
	// weak, as the ObjC was (rule 27): the bundle owns its grammars.
	@objc dynamic weak var bundle: TMBundle?
	@objc dynamic var identifier: UUID?
	@objc dynamic var name: String?
	@objc dynamic var fileType: String?       // E.g. ‘source.ruby’
	@objc dynamic var filePatterns: [String]? // Array of extensions or file globs
	@objc dynamic var firstLineMatch: String? // E.g. ‘^#!/.*\bruby’

	@objc override init() {
		super.init()
	}

	override var description: String {
		return "<\(NSStringFromClass(type(of: self))): \(name ?? "(null)") (\(fileType ?? "(null)"))>"
	}
}
