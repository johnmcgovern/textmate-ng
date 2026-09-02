import AppKit

// The application's menus, in Swift.
//
// MenuBuilder's API is a C++ DSL — `typedef std::vector<MBMenuItem> MBMenu`,
// populated with designated-initialiser aggregate syntax and written through
// `NSMenu* __strong*` out-parameters — so Swift cannot call it and cannot import
// its header. Find, DocumentWindowController, CommitWindow, Preferences and
// OTVStatusBar all hand-rolled their menus for this reason, each reproducing
// MBMenuItem's defaults at the call site.
//
// This file does the same thing once, properly: MBMenuItem and MBCreateMenuItem
// are restated as `MenuSpec` and `makeItem`, field for field and branch for
// branch, so the 248-item menu below reads like the DSL it replaces and is
// checked against it. `t_app_controller.mm` compares the built menu to a
// MBDumpMenu golden taken from the ObjC++ *before* this file existed; that
// golden is the specification and must not be regenerated to match a change
// here.
//
// Rule 12 is why the defaults are restated rather than assumed: a nil title
// yields a **separator**, `modifierFlags` defaults to Command and is applied
// whether or not there is a key equivalent, and a non-nil `.delegate` alone is
// enough to create a submenu.

// MARK: - MBMenuItem, restated

enum SystemMenu {
	case regular, services, openRecent, font, windows, help
}

struct MenuSpec {
	var title: String?
	var action: Selector?
	var keyEquivalent: String = ""
	var modifierFlags: NSEvent.ModifierFlags = .command
	var tag: Int = 0
	var indent: Int = 0
	var state: NSControl.StateValue = .off
	var target: AnyObject?
	var delegate: NSMenuDelegate?
	var key: Int = 0
	var separator: Bool = false
	var alternate: Bool = false
	var enabled: Bool = true
	var hidden: Bool = false
	var systemMenu: SystemMenu = .regular
	var representedObject: Any?
	// MBMenuItem's `NSMenu* __strong* submenuRef`, which C++ used to write the
	// caller's variable through a pointer. A closure is the Swift spelling.
	var submenuRef: ((NSMenu) -> Void)?
	var submenu: [MenuSpec] = []
}

/// A separator. MBMenuItem produced one from a nil title, which is easy to
/// misread at a call site, so it gets a name here.
func separatorSpec() -> MenuSpec {
	return MenuSpec(title: nil, separator: true)
}

// MBCreateMenuItem, branch for branch.
private func makeItem(_ spec: MenuSpec) -> NSMenuItem {
	let menuItem: NSMenuItem
	if let title = spec.title, !spec.separator {
		menuItem = NSMenuItem(title: title, action: spec.action, keyEquivalent: spec.keyEquivalent)
	} else {
		menuItem = NSMenuItem.separator()
	}

	menuItem.keyEquivalentModifierMask = spec.modifierFlags
	menuItem.tag                       = spec.tag
	menuItem.target                    = spec.target
	menuItem.isAlternate               = spec.alternate
	menuItem.isEnabled                 = spec.enabled
	menuItem.isHidden                  = spec.hidden
	menuItem.indentationLevel          = spec.indent
	menuItem.state                     = spec.state
	menuItem.representedObject         = spec.representedObject

	if spec.hidden && (spec.keyEquivalent != "" || spec.key != 0) {
		menuItem.allowsKeyEquivalentWhenHidden = true
	}

	if spec.key != 0 {
		menuItem.keyEquivalent = String(format: "%C", unichar(spec.key))
	}

	if !spec.submenu.isEmpty || spec.systemMenu != .regular || spec.delegate != nil || spec.submenuRef != nil {
		let submenu = makeMenu(spec.submenu, into: NSMenu(title: spec.title ?? ""))
		submenu.delegate = spec.delegate
		menuItem.submenu = submenu

		switch spec.systemMenu {
			case .services: NSApp.servicesMenu           = submenu
			case .font:     NSFontManager.shared.setFontMenu(submenu)
			case .windows:  NSApp.windowsMenu            = submenu
			case .help:     NSApp.helpMenu               = submenu

			case .openRecent:
				// Private, and reached by name exactly as the ObjC++ did.
				let sel = Selector(("_setMenuName:"))
				if submenu.responds(to: sel) {
					submenu.perform(sel, with: "NSRecentDocumentsMenu")
				}

			case .regular: break
		}

		spec.submenuRef?(submenu)
	}

	return menuItem
}

// MBCreateMenu.
@discardableResult
func makeMenu(_ items: [MenuSpec], into existingMenu: NSMenu? = nil) -> NSMenu {
	let menu = existingMenu ?? NSMenu(title: "AMainMenu")
	for spec in items {
		menu.addItem(makeItem(spec))
	}
	return menu
}

// MARK: - The menus

// Built and handed back to ObjC++ rather than defined on AppController, because
// AppController is still an ObjC++ class. When it flips, these become methods on
// it and this wrapper goes away.
@objc(TMMenus) class TMMenus: NSObject {

	// -[AppController applicationDockMenu:]. The only place the app sets an
	// explicit `.target`: the dock menu is shown with no key window, so the
	// responder chain cannot be relied on.
	@objc(dockMenuWithTarget:) class func dockMenu(target: AnyObject) -> NSMenu {
		let items: [MenuSpec] = [
			MenuSpec(title: "New File", action: Selector(("newDocumentAndActivate:")),  target: target),
			MenuSpec(title: "Open…",    action: Selector(("openDocumentAndActivate:")), target: target),
		]
		return makeMenu(items)
	}
}
