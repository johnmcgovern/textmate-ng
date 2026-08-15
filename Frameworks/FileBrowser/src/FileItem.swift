import AppKit
import Quartz
import os.log

// The file browser's model node: one URL and the file-system facts derived from
// it, plus the scheme→class registry that picks the right subclass. Ported to
// Swift; the ObjC++ subclasses (SCMStatusFileItem, MountedVolumesFileItem) still
// inherit this via the hand-written FileItem.h, and the FileItem(Observer)
// category in FileItemObserver.mm still extends it.
//
// KVO is load-bearing here — the row cell binds to objectValue.displayName /
// canRename / toolTip / finderTags / editingAndDisplayName — so the stored
// properties those depend on (URL, disambiguationSuffix, hiddenExtension,
// toolTip, finderTags) are `@objc dynamic`, and the computed ones publish their
// dependencies through +keyPathsForValuesAffecting…. That is the same rule 1
// that drove FileItemTableCellView, one layer down.
//
// editingAndDisplayName was a separate FileItem(FileItemWrapper) category
// (FileItemEditingName); it folds in here now that FileItem is Swift.
@objc(FileItem)
class FileItem: NSObject, QLPreviewItem {
	// ============
	// = Registry =
	// ============

	// The ObjC++ original was a plain unsynchronized static NSMutableDictionary;
	// the registry is only ever touched on the main thread, so this keeps that
	// contract rather than adding isolation the callers (ObjC++) can't express.
	nonisolated(unsafe) private static var schemeToClass: [String: AnyClass] = [:]

	// Replaces the three +load self-registrations; runs once, lazily, before the
	// first lookup. NSClassFromString reaches the subclasses without a shared
	// header, and -ObjC keeps them linked.
	private static let registerBuiltinClasses: Void = {
		FileItem.register(FileItem.self, forURLScheme: "file")
		if let klass = NSClassFromString("SCMStatusFileItem") {
			FileItem.register(klass, forURLScheme: "scm")
		}
		if let klass = NSClassFromString("MountedVolumesFileItem") {
			FileItem.register(klass, forURLScheme: "computer")
		}
	}()

	@objc(registerClass:forURLScheme:)
	class func register(_ klass: AnyClass, forURLScheme urlScheme: String) {
		schemeToClass[urlScheme] = klass
	}

	@objc(classForURL:)
	class func classForURL(_ url: NSURL) -> AnyClass? {
		_ = registerBuiltinClasses
		return schemeToClass[url.scheme ?? ""]
	}

	@objc(fileItemWithURL:)
	class func fileItem(withURL url: NSURL) -> FileItem? {
		guard let klass = classForURL(url) as? FileItem.Type else { return nil }
		return klass.init(URL: url)
	}

	// The watcher behind addObserverToDirectory (FileItemObserver.swift). The
	// default handles file:// URLs; the scm/computer subclasses override it. In
	// the class body rather than an extension so those overrides are legal.
	@MainActor
	@objc(makeObserverForURL:usingBlock:)
	class func makeObserver(forURL url: NSURL, usingBlock handler: @escaping ([URL]) -> Void) -> Any? {
		return url.isFileURL ? FileSystemObserver(URL: url, usingBlock: handler) : nil
	}

	// ==============
	// = Properties =
	// ==============

	@objc dynamic var URL: NSURL! {
		didSet {
			if !(URL === oldValue) && !(oldValue?.isEqual(URL) ?? false) {
				_localizedName = nil

				for child in children ?? [] {
					if child.URL.isFileURL && URL.isFileURL {
						child.URL = URL.appendingPathComponent(child.URL.lastPathComponent ?? "", isDirectory: child.URL.hasDirectoryPath) as NSURL?
					}
				}
			}

			fileReferenceURL = URL?.fileReferenceURL() as NSURL?
		}
	}

	@objc private(set) var fileReferenceURL: NSURL?

	@objc var toolTip: String?
	@objc dynamic var disambiguationSuffix: String?
	@objc dynamic var finderTags: [OakFinderTag]?

	@objc var children: [FileItem]?
	@objc var arrangedChildren: NSMutableArray?

	// These keep the ObjC getter/setter spellings (getter=isX / hasX, setter=setX:)
	// and their bare property names, because consumers reach them both ways —
	// FileBrowserViewController writes `item.hidden`, FileBrowserDiskOperations
	// `item.missing` (the property name, resolved through the isX getter). Rule 4:
	// annotate the accessors, not the property.
	private var _missing = false
	@objc var missing: Bool {
		@objc(isMissing) get { _missing }
		@objc(setMissing:) set { _missing = newValue }
	}

	private var _hidden = false
	@objc var hidden: Bool {
		@objc(isHidden) get { _hidden }
		@objc(setHidden:) set { _hidden = newValue }
	}

	private var _symbolicLink = false
	@objc var symbolicLink: Bool {
		@objc(isSymbolicLink) get { _symbolicLink }
		@objc(setSymbolicLink:) set { _symbolicLink = newValue }
	}

	private var _package = false
	@objc var package: Bool {
		@objc(isPackage) get { _package }
		@objc(setPackage:) set { _package = newValue }
	}

	private var _linkToPackage = false
	@objc var linkToPackage: Bool {
		@objc(isLinkToPackage) get { _linkToPackage }
		@objc(setLinkToPackage:) set { _linkToPackage = newValue }
	}

	private var _linkToDirectory = false
	@objc var linkToDirectory: Bool {
		@objc(isLinkToDirectory) get { _linkToDirectory }
		@objc(setLinkToDirectory:) set { _linkToDirectory = newValue }
	}

	// The one boolean that participates in KVO: localizedName depends on it, so
	// the setter must be swizzlable (dynamic); setting it drops the cached name.
	private var _hiddenExtension = false
	@objc dynamic var hiddenExtension: Bool {
		@objc(hasHiddenExtension) get { _hiddenExtension }
		@objc(setHiddenExtension:) set {
			if _hiddenExtension != newValue {
				_hiddenExtension = newValue
				_localizedName = nil
			}
		}
	}

	private var _localizedName: String?

	// =============
	// = Lifecycle =
	// =============

	@objc(initWithURL:)
	required init(URL url: NSURL) {
		super.init()
		self.URL = url
		updateFileProperties()
	}

	@objc var canRename: Bool {
		guard URL.isFileURL, !missing else { return false }
		let isVolume = (try? (URL as Foundation.URL).resourceValues(forKeys: [.isVolumeKey]))?.isVolume ?? false
		return !isVolume
	}

	@objc func updateFileProperties() {
		guard URL.isFileURL else { return }

		let values = try? (URL as Foundation.URL).resourceValues(forKeys: [.isHiddenKey, .hasHiddenExtensionKey, .isSymbolicLinkKey, .isPackageKey])
		hidden          = values?.isHidden ?? false
		hiddenExtension = values?.hasHiddenExtension ?? false
		symbolicLink    = values?.isSymbolicLink ?? false
		package         = !symbolicLink && (values?.isPackage ?? false)

		let resolved = try? (resolvedURL as Foundation.URL).resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
		linkToDirectory = symbolicLink && (resolved?.isDirectory ?? false)
		linkToPackage   = symbolicLink && (resolved?.isPackage ?? false)

		finderTags = OakFinderTagManager.finderTags(for: URL as Foundation.URL)
		missing    = missing && !FileManager.default.fileExists(atPath: URL.path ?? "")
	}

	override var description: String {
		return "<\(type(of: self)): \(URL?.description ?? "(null)"))>"
	}

	// ================
	// = QLPreviewItem =
	// ================

	var previewItemURL: Foundation.URL? {
		return missing ? nil : resolvedURL.filePathURL
	}

	var previewItemTitle: String? {
		return localizedName
	}

	// =======================
	// = Computed Properties =
	// =======================

	private var alwaysShowFileExtension: Bool {
		return UserDefaults.standard.bool(forKey: kUserDefaultsShowFileExtensionsKey)
	}

	@objc var isDirectory: Bool {
		return URL.hasDirectoryPath
	}

	@objc var displayName: String {
		return localizedName + (disambiguationSuffix ?? "")
	}

	@objc dynamic var localizedName: String! {
		get {
			if _localizedName == nil {
				var name: String?
				if URL.isFileURL {
					do {
						if let localized = try (URL as Foundation.URL).resourceValues(forKeys: [.localizedNameKey]).localizedName {
							name = localized
							if hiddenExtension && alwaysShowFileExtension && OakNotEmptyString(URL.pathExtension) {
								name = (localized as NSString).appendingPathExtension(URL.pathExtension ?? "")
							}
						}
					} catch {
						os_log(.error, "No NSURLLocalizedNameKey for %{public}@: %{public}@", URL, error as NSError)
					}
				}
				_localizedName = name ?? URL.lastPathComponent
			}
			return _localizedName ?? URL.lastPathComponent
		}
		set {
			_localizedName = newValue
		}
	}

	@objc var resolvedURL: NSURL {
		var url = URL as Foundation.URL
		if symbolicLink {
			// For /{etc,tmp,var} we get /{etc,tmp,var}/ instead of /private/{etc,tmp,var}/
			url = url.resolvingSymlinksInPath()

			if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
				if let path = try? FileManager.default.destinationOfSymbolicLink(atPath: URL.path ?? "") {
					url = (URL as Foundation.URL).deletingLastPathComponent().appendingPathComponent(path)
				}
			}
		}
		return url as NSURL
	}

	@objc var parentURL: NSURL? {
		if URL.isFileURL {
			let values = try? (URL as Foundation.URL).resourceValues(forKeys: [.isVolumeKey, .parentDirectoryURLKey])
			if values?.isVolume == true {
				return kURLLocationComputer as NSURL
			} else if let parent = values?.parentDirectory {
				return parent as NSURL
			}
		}
		return nil
	}

	@objc var isApplication: Bool {
		guard URL.isFileURL else { return false }
		return (try? (URL as Foundation.URL).resourceValues(forKeys: [.isApplicationKey]))?.isApplication ?? false
	}

	// The [filename, displayName] pair the cell's text field binds to; the setter
	// is a no-op (the two-way binding writes back, but the rename is driven from
	// the controller's text-field delegate).
	@objc var editingAndDisplayName: [String] {
		get { return [URL.lastPathComponent ?? "", displayName] }
		set { }
	}

	// ==========================================
	// = KVO dependencies                        =
	// ==========================================

	@objc class func keyPathsForValuesAffectingDisplayName() -> Set<String> {
		return ["localizedName", "disambiguationSuffix"]
	}

	@objc class func keyPathsForValuesAffectingLocalizedName() -> Set<String> {
		return ["URL", "hiddenExtension"]
	}

	@objc class func keyPathsForValuesAffectingEditingAndDisplayName() -> Set<String> {
		return ["URL", "displayName"]
	}
}
