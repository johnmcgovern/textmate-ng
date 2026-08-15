import AppKit

// The "computer://" data source: the host as a folder whose children are the
// mounted volumes. A FileItem subclass plus an observer that reloads on
// mount/unmount/rename. No C++ — the +load registration already moved to
// FileItem.registerBuiltinClasses, so this is a straight port.
//
// Both classes are reached only dynamically (the registry resolves
// MountedVolumesFileItem via NSClassFromString; the observer is made by
// +makeObserverForURL:usingBlock:), so neither needs a hand-written header.
// makeObserverForURL: is not declared on FileItem, so this is a fresh @objc
// class method rather than an override; it wins by ObjC dynamic dispatch over the
// default still in FileItemObserver.mm.
@objc(MountedVolumesFileItem)
final class MountedVolumesFileItem: FileItem {
	@MainActor
	@objc(makeObserverForURL:usingBlock:)
	override class func makeObserver(forURL url: NSURL, usingBlock handler: @escaping ([URL]) -> Void) -> Any? {
		return MountedVolumesObserver(block: handler)
	}

	override var localizedName: String! {
		get { return Host.current().localizedName }
		set { super.localizedName = newValue }
	}
}

@objc(MountedVolumesObserver)
final class MountedVolumesObserver: NSObject {
	private let handler: ([URL]) -> Void

	@objc init(block handler: @escaping ([URL]) -> Void) {
		self.handler = handler
		super.init()

		let center = NSWorkspace.shared.notificationCenter
		center.addObserver(self, selector: #selector(workspaceDidChangeVolumeList(_:)), name: NSWorkspace.didMountNotification, object: NSWorkspace.shared)
		center.addObserver(self, selector: #selector(workspaceDidChangeVolumeList(_:)), name: NSWorkspace.didUnmountNotification, object: NSWorkspace.shared)
		center.addObserver(self, selector: #selector(workspaceDidChangeVolumeList(_:)), name: NSWorkspace.didRenameVolumeNotification, object: NSWorkspace.shared)

		workspaceDidChangeVolumeList(nil)
	}

	deinit {
		NSWorkspace.shared.notificationCenter.removeObserver(self)
	}

	@objc func workspaceDidChangeVolumeList(_ notification: Notification?) {
		let volumeURLs = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.localizedNameKey, .effectiveIconKey], options: .skipHiddenVolumes) ?? []
		handler(volumeURLs)
	}
}
