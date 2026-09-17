import AppKit

// Ported from FFFolderMenu.mm — the delegate behind the folder rows of Find's
// "In:" pop-up: a lazily-populated submenu of a directory's subfolders, each
// with a submenu of its own if it has subfolders, and on the root menu only an
// "Enclosing Folders" section walking up to "/". Pinned by t_folder_menu.mm,
// written against the ObjC++ first.
//
// No hand-written header (rule 23 does not apply): Find.swift is the only
// consumer and it is in this module, so the class is visible directly and
// FFFolderMenu.h is gone along with its line in Find-Bridging-Header.h, where
// it would now collide with the generated Find-Swift.h (rule 43). The tests
// reach it through FindTesting.h, which is what pins the ObjC spellings.
//
// The original's three lines of C++ — path::entries over a "*" glob,
// path::join and to_s — are FileManager.contentsOfDirectory(atPath:) and lstat
// here. Two things the glob did implicitly are explicit now: it skipped
// dot-entries (path::glob_t's matchDotFiles defaults to false), and scandir's
// filter skipped "." and "..", which contentsOfDirectory omits as well. The
// d_type == DT_DIR test is folded into the lstat: a symlink is S_IFLNK there,
// so it is skipped the same way DT_LNK was.

@objc(FFFolderMenu)
@MainActor
class FFFolderMenu: NSObject, NSMenuDelegate {
	@objc static let sharedInstance = FFFolderMenu()

	// Neither selector has a method in this module to point #selector at. -nop:
	// is the caption convention used throughout (OTVStatusBar, DocumentWindow);
	// -goToParentFolder: is found up the responder chain, on Find.
	private static let nop              = NSSelectorFromString("nop:")
	private static let goToParentFolder = NSSelectorFromString("goToParentFolder:")

	@objc(addSubmenuForDirectoryAtPath:toMenuItem:)
	static func addSubmenuForDirectory(atPath path: String, to menuItem: NSMenuItem) {
		sharedInstance.addSubmenuForDirectory(atPath: path, to: menuItem)
	}

	@objc(addSubmenuForDirectoryAtPath:toMenuItem:)
	func addSubmenuForDirectory(atPath path: String, to menuItem: NSMenuItem) {
		menuItem.representedObject = path
		menuItem.submenu = NSMenu()
		menuItem.submenu?.delegate = self
	}

	// MARK: - Listing

	private static func folders(atPath folder: String) -> [String] {
		assert(!folder.isEmpty)

		var isDirectory: ObjCBool = false
		guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue else {
			return []
		}

		// scandir failing was a perror and an empty listing; so is a throw here.
		guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder) else {
			return []
		}

		var res: [String] = []
		for name in entries where !name.hasPrefix(".") {
			let path = (folder as NSString).appendingPathComponent(name)

			var buf = stat()
			guard lstat(path, &buf) == 0 else {
				continue
			}
			if (buf.st_mode & S_IFMT) != S_IFDIR || (buf.st_flags & UInt32(UF_HIDDEN)) != 0 {
				continue
			}

			if !NSWorkspace.shared.isFilePackage(atPath: path) {
				res.append(path)
			}
		}

		// The descriptors are the original's, verbatim: Finder order on the
		// stem, then the extension. Both halves are pinned.
		let displayNameSort = NSSortDescriptor(key: "stringByDeletingPathExtension", ascending: true, selector: #selector(NSString.localizedStandardCompare(_:)))
		let extensionSort   = NSSortDescriptor(key: "pathExtension", ascending: true, selector: #selector(NSString.compare(_:)))
		return (res as NSArray).sortedArray(using: [ displayNameSort, extensionSort ]) as? [String] ?? res
	}

	// MARK: - NSMenuDelegate

	func menuNeedsUpdate(_ menu: NSMenu) {
		if menu.numberOfItems > 0 {
			return
		}

		// The item this menu hangs off. ObjC nil-messaging made a missing
		// supermenu harmless (rule 33); the index guard keeps it so.
		var parentItem: NSMenuItem?
		if let supermenu = menu.supermenu {
			let index = supermenu.indexOfItem(withSubmenu: menu)
			if index != -1 {
				parentItem = supermenu.item(at: index)
			}
		}

		let folder = parentItem?.representedObject as? String ?? NSHomeDirectory()
		for path in Self.folders(atPath: folder) {
			let menuItem = menu.addItem(withTitle: FileManager.default.displayName(atPath: path), action: parentItem?.action, keyEquivalent: "")
			menuItem.target = parentItem?.target
			menuItem.setIconForFile(path)
			menuItem.representedObject = path

			if !Self.folders(atPath: path).isEmpty {
				addSubmenuForDirectory(atPath: path, to: menuItem)
			}
		}

		if parentItem?.parent == nil && folder != "/" { // Add enclosing folders to root menu
			if menu.numberOfItems > 0 {
				menu.addItem(NSMenuItem.separator())
			}
			menu.addItem(withTitle: "Enclosing Folders", action: Self.nop, keyEquivalent: "")

			var immediateParent = true
			var path = (folder as NSString).deletingLastPathComponent
			while !path.isEmpty {
				let shortcut = immediateParent ? "\u{F700}" : ""
				let action   = immediateParent ? Self.goToParentFolder : parentItem?.action
				let target   = immediateParent ? nil : parentItem?.target

				let menuItem = menu.addItem(withTitle: FileManager.default.displayName(atPath: path), action: action, keyEquivalent: shortcut)
				menuItem.target = target
				menuItem.representedObject = path
				menuItem.setIconForFile(path)

				if path == "/" {
					break
				}

				immediateParent = false
				path = (path as NSString).deletingLastPathComponent
			}
		}
	}

	// Answering false is what keeps AppKit from populating every folder submenu
	// on each key press to look for a matching key equivalent.
	func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>, action: UnsafeMutablePointer<Selector?>) -> Bool {
		return false
	}
}
