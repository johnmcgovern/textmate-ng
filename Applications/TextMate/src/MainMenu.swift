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

	// The four submenus MBMenuItem's `.submenuRef` used to write back through an
	// `NSMenu* __strong*`. AppController keeps them as ivars and -menuNeedsUpdate:
	// dispatches on identity, so losing one is a silently dead menu rather than an
	// error — which is why t_app_controller.mm asserts all four come back non-nil.
	@objc(TMMainMenuRefs) class MainMenuRefs: NSObject {
		@objc let bundlesMenu: NSMenu?
		@objc let themesMenu: NSMenu?
		@objc let spellingMenu: NSMenu?
		@objc let wrapColumnMenu: NSMenu?

		init(bundles: NSMenu?, themes: NSMenu?, spelling: NSMenu?, wrapColumn: NSMenu?) {
			bundlesMenu    = bundles
			themesMenu     = themes
			spellingMenu   = spelling
			wrapColumnMenu = wrapColumn
		}
	}

	// -[AppController mainMenu], 248 items across 12 top-level menus.
	//
	// Translated from the MBMenu literal mechanically rather than retyped, in the
	// spirit of rule 6: a throwaway parser read the C++ aggregate and emitted these
	// MenuSpecs, so no title, selector or key equivalent passed through a human.
	// t_app_controller.mm then compares the result against a MBDumpMenu golden taken
	// from the ObjC++ before any of this existed. **That golden is the
	// specification. Do not regenerate it to match a change here.**
	//
	// `appName` comes from CFBundleName so the fork's name lives in one place, and
	// `target` is only used where the responder chain cannot be relied on.
	@objc(buildMainMenuInto:target:appName:)
	class func buildMainMenu(into existingMenu: NSMenu, target: AnyObject, appName: String) -> MainMenuRefs {
		var spellingMenu: NSMenu?
		var wrapColumnMenu: NSMenu?
		var themesMenu: NSMenu?
		var bundlesMenu: NSMenu?

		// The three Find tags are FFSearchTargetDocument, FFSearchTargetProject and
		// FFSearchTargetOther. They are literals because <Find/FindTypes.h> cannot
		// enter this target's bridging header — it pulls <text/types.h> and then
		// oak/algorithm.h, which needs the full prelude. Pinned by static_assert and
		// by test, the same treatment find::options_t already has (rule 5).
		let items: [MenuSpec] = [
			MenuSpec(title: appName, submenu: [
				MenuSpec(title: "About \(appName)", action: Selector(("orderFrontAboutPanel:"))),
				separatorSpec(),
				MenuSpec(title: "Preferences…", action: Selector(("showPreferences:")), keyEquivalent: ","),
				MenuSpec(title: "Check for Update", action: Selector(("performSoftwareUpdateCheck:"))),
				MenuSpec(title: "Check for Test Build", action: Selector(("performSoftwareUpdateCheck:")), modifierFlags: [.command, .option], alternate: true),
				separatorSpec(),
				MenuSpec(title: "Services", systemMenu: .services),
				separatorSpec(),
				MenuSpec(title: "Hide \(appName)", action: Selector(("hide:")), keyEquivalent: "h"),
				MenuSpec(title: "Hide Others", action: Selector(("hideOtherApplications:")), keyEquivalent: "h", modifierFlags: [.command, .option]),
				MenuSpec(title: "Show All", action: Selector(("unhideAllApplications:"))),
				separatorSpec(),
				MenuSpec(title: "Quit \(appName)", action: Selector(("terminate:")), keyEquivalent: "q"),
			]),
			MenuSpec(title: "File", submenu: [
				MenuSpec(title: "New", action: Selector(("newDocument:")), keyEquivalent: "n"),
				MenuSpec(title: "New File Browser", action: Selector(("newFileBrowser:")), keyEquivalent: "n", modifierFlags: [.command, .option, .control], alternate: true),
				MenuSpec(title: "New Tab", action: Selector(("newDocumentInTab:")), keyEquivalent: "n", modifierFlags: [.command, .option]),
				separatorSpec(),
				MenuSpec(title: "Open…", action: Selector(("openDocument:")), keyEquivalent: "o"),
				MenuSpec(title: "Open Quickly…", action: Selector(("goToFile:")), keyEquivalent: "t"),
				MenuSpec(title: "Open Recent", systemMenu: .openRecent, submenu: [
					MenuSpec(title: "Clear Menu", action: Selector(("clearRecentDocuments:"))),
				]),
				MenuSpec(title: "Open Recent Project…", action: Selector(("openFavorites:")), keyEquivalent: "O"),
				separatorSpec(),
				MenuSpec(title: "Close", action: Selector(("performClose:")), keyEquivalent: "w"),
				MenuSpec(title: "Close Window", action: Selector(("performCloseWindow:")), keyEquivalent: "W"),
				MenuSpec(title: "Close All Tabs", action: Selector(("performCloseAllTabs:")), keyEquivalent: "w", modifierFlags: [.command, .option, .control]),
				MenuSpec(title: "Close Other Tabs", action: Selector(("performCloseOtherTabsXYZ:")), keyEquivalent: "w", modifierFlags: [.command, .control]),
				MenuSpec(title: "Close Tabs to the Right", action: Selector(("performCloseTabsToTheRight:"))),
				MenuSpec(title: "Close Tabs to the Left", action: Selector(("performCloseTabsToTheLeft:")), modifierFlags: [.command, .option], alternate: true),
				separatorSpec(),
				MenuSpec(title: "Sticky", action: Selector(("toggleSticky:"))),
				separatorSpec(),
				MenuSpec(title: "Save", action: Selector(("saveDocument:")), keyEquivalent: "s"),
				MenuSpec(title: "Save As…", action: Selector(("saveDocumentAs:")), keyEquivalent: "S"),
				MenuSpec(title: "Save All", action: Selector(("saveAllDocuments:")), keyEquivalent: "s", modifierFlags: [.command, .option]),
				MenuSpec(title: "Revert", action: Selector(("revertDocumentToSaved:"))),
				separatorSpec(),
				MenuSpec(title: "Page Setup…", action: Selector(("runPageLayout:")), target: NSApp.delegate),
				MenuSpec(title: "Print…", action: Selector(("printDocument:")), keyEquivalent: "p"),
			]),
			MenuSpec(title: "Edit", submenu: [
				MenuSpec(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"),
				MenuSpec(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"),
				separatorSpec(),
				MenuSpec(title: "Cut", action: Selector(("cut:")), keyEquivalent: "x"),
				MenuSpec(title: "Copy", action: Selector(("copy:")), keyEquivalent: "c"),
				MenuSpec(title: "Paste", submenu: [
					MenuSpec(title: "Paste", action: Selector(("paste:")), keyEquivalent: "v"),
					MenuSpec(title: "Paste Without Indenting", action: Selector(("pasteWithoutReindent:")), keyEquivalent: "v", modifierFlags: [.command, .control], alternate: true),
					MenuSpec(title: "Paste Next", action: Selector(("pasteNext:")), keyEquivalent: "v", modifierFlags: [.command, .option]),
					MenuSpec(title: "Paste Previous", action: Selector(("pastePrevious:")), keyEquivalent: "V"),
					separatorSpec(),
					MenuSpec(title: "Show History", action: Selector(("showClipboardHistory:")), keyEquivalent: "v", modifierFlags: [.command, .option, .control]),
				]),
				MenuSpec(title: "Delete", action: Selector(("delete:")), key: NSBackspaceCharacter),
				separatorSpec(),
				MenuSpec(title: "Macros", submenu: [
					MenuSpec(title: "Start Recording", action: Selector(("toggleMacroRecording:")), keyEquivalent: "m", modifierFlags: [.command, .option]),
					MenuSpec(title: "Replay Macro", action: Selector(("playScratchMacro:")), keyEquivalent: "M"),
					MenuSpec(title: "Save Macro…", action: Selector(("saveScratchMacro:")), keyEquivalent: "m", modifierFlags: [.command, .control]),
				]),
				separatorSpec(),
				MenuSpec(title: "Select", submenu: [
					MenuSpec(title: "Word", action: Selector(("selectWord:"))),
					MenuSpec(title: "Line", action: Selector(("selectHardLine:"))),
					MenuSpec(title: "Paragraph", action: Selector(("selectParagraph:"))),
					MenuSpec(title: "Current Scope", action: Selector(("selectCurrentScope:"))),
					MenuSpec(title: "Enclosing Typing Pairs", action: Selector(("selectBlock:")), keyEquivalent: "B"),
					MenuSpec(title: "All", action: Selector(("selectAll:")), keyEquivalent: "a"),
					separatorSpec(),
					MenuSpec(title: "Toggle Column Selection", action: Selector(("toggleColumnSelection:")), modifierFlags: [.option]),
				]),
				MenuSpec(title: "Find", submenu: [
					MenuSpec(title: "Find and Replace…", action: Selector(("orderFrontFindPanel:")), keyEquivalent: "f", tag: 0),
					MenuSpec(title: "Find in Project…", action: Selector(("orderFrontFindPanel:")), keyEquivalent: "F", tag: 3),
					MenuSpec(title: "Find in Folder…", action: Selector(("orderFrontFindPanel:")), tag: 5),
					separatorSpec(),
					MenuSpec(title: "Show Find History", action: Selector(("showFindHistory:")), keyEquivalent: "f", modifierFlags: [.command, .option, .control]),
					separatorSpec(),
					MenuSpec(title: "Incremental Search", action: Selector(("incrementalSearch:")), keyEquivalent: "s", modifierFlags: [.control]),
					MenuSpec(title: "Incremental Search Previous", action: Selector(("incrementalSearchPrevious:")), keyEquivalent: "S", modifierFlags: [.control]),
					separatorSpec(),
					MenuSpec(title: "Find Next", action: Selector(("findNext:")), keyEquivalent: "g"),
					MenuSpec(title: "Find Previous", action: Selector(("findPrevious:")), keyEquivalent: "G"),
					MenuSpec(title: "Find All", action: Selector(("findAllInSelection:")), keyEquivalent: "f", modifierFlags: [.command, .option]),
					separatorSpec(),
					MenuSpec(title: "Find Options", submenu: [
						MenuSpec(title: "Ignore Case", action: Selector(("toggleFindOption:")), keyEquivalent: "c", modifierFlags: [.command, .option], tag: 2),
						MenuSpec(title: "Regular Expression", action: Selector(("toggleFindOption:")), keyEquivalent: "r", modifierFlags: [.command, .option], tag: 8),
						MenuSpec(title: "Ignore Whitespace", action: Selector(("toggleFindOption:")), tag: 4),
						MenuSpec(title: "Wrap Around", action: Selector(("toggleFindOption:")), keyEquivalent: "a", modifierFlags: [.command, .option], tag: 128),
					]),
					separatorSpec(),
					MenuSpec(title: "Replace", action: Selector(("replace:")), keyEquivalent: "g", modifierFlags: [.command, .option]),
					MenuSpec(title: "Replace & Find", action: Selector(("replaceAndFind:"))),
					MenuSpec(title: "Replace All", action: Selector(("replaceAll:")), keyEquivalent: "g", modifierFlags: [.command, .control]),
					MenuSpec(title: "Replace All in Selection", action: Selector(("replaceAllInSelection:")), keyEquivalent: "G", modifierFlags: [.command, .control]),
					separatorSpec(),
					MenuSpec(title: "Use Selection for Find", action: Selector(("copySelectionToFindPboard:")), keyEquivalent: "e"),
					MenuSpec(title: "Use Selection for Replace", action: Selector(("copySelectionToReplacePboard:")), keyEquivalent: "E"),
				]),
				MenuSpec(title: "Spelling", submenuRef: { spellingMenu = $0 }, submenu: [
					MenuSpec(title: "Spelling…", action: Selector(("showGuessPanel:")), keyEquivalent: ":"),
					MenuSpec(title: "Check Document Now", action: Selector(("checkSpelling:")), keyEquivalent: ";"),
					separatorSpec(),
					MenuSpec(title: "Check Spelling While Typing", action: Selector(("toggleContinuousSpellChecking:")), keyEquivalent: ";", modifierFlags: [.command, .option]),
					separatorSpec(),
				]),
			]),
			MenuSpec(title: "View", submenu: [
				MenuSpec(title: "Font", systemMenu: .font, submenu: [
					MenuSpec(title: "Show Fonts", action: Selector(("orderFrontFontPanel:")), target: NSFontManager.shared),
					separatorSpec(),
					MenuSpec(title: "Bigger", action: Selector(("makeTextLarger:")), keyEquivalent: "+"),
					MenuSpec(title: "Smaller", action: Selector(("makeTextSmaller:")), keyEquivalent: "-"),
					MenuSpec(title: "Default Size", action: Selector(("makeTextStandardSize:")), keyEquivalent: "0"),
				]),
				MenuSpec(title: "Show File Browser", action: Selector(("toggleFileBrowser:")), keyEquivalent: "d", modifierFlags: [.command, .option, .control]),
				MenuSpec(title: "Show HTML Output", action: Selector(("toggleHTMLOutput:")), keyEquivalent: "h", modifierFlags: [.command, .option, .control]),
				MenuSpec(title: "Show Line Numbers", action: Selector(("toggleLineNumbers:")), keyEquivalent: "l", modifierFlags: [.command, .option]),
				separatorSpec(),
				MenuSpec(title: "Show Invisibles", action: Selector(("toggleShowInvisibles:")), keyEquivalent: "i", modifierFlags: [.command, .option]),
				separatorSpec(),
				MenuSpec(title: "Enable Soft Wrap", action: Selector(("toggleSoftWrap:")), keyEquivalent: "w", modifierFlags: [.command, .option]),
				MenuSpec(title: "Show Wrap Column", action: Selector(("toggleShowWrapColumn:"))),
				MenuSpec(title: "Show Indent Guides", action: Selector(("toggleShowIndentGuides:"))),
				MenuSpec(title: "Wrap Column", submenuRef: { wrapColumnMenu = $0 }, submenu: [
					MenuSpec(title: "Use Window Frame", action: Selector(("takeWrapColumnFrom:"))),
					separatorSpec(),
					MenuSpec(title: "40", action: Selector(("takeWrapColumnFrom:")), tag: 40),
					MenuSpec(title: "80", action: Selector(("takeWrapColumnFrom:")), tag: 80),
					separatorSpec(),
					MenuSpec(title: "Other…", action: Selector(("takeWrapColumnFrom:")), tag: -1),
				]),
				separatorSpec(),
				MenuSpec(title: "Tab Size", submenu: [
					MenuSpec(title: "2", action: Selector(("takeTabSizeFrom:")), tag: 2),
					MenuSpec(title: "3", action: Selector(("takeTabSizeFrom:")), tag: 3),
					MenuSpec(title: "4", action: Selector(("takeTabSizeFrom:")), tag: 4),
					MenuSpec(title: "5", action: Selector(("takeTabSizeFrom:")), tag: 5),
					MenuSpec(title: "6", action: Selector(("takeTabSizeFrom:")), tag: 6),
					MenuSpec(title: "7", action: Selector(("takeTabSizeFrom:")), tag: 7),
					MenuSpec(title: "8", action: Selector(("takeTabSizeFrom:")), tag: 8),
					separatorSpec(),
					MenuSpec(title: "Other…", action: Selector(("showTabSizeSelectorPanel:"))),
				]),
				MenuSpec(title: "Theme", submenuRef: { themesMenu = $0 }),
				separatorSpec(),
				MenuSpec(title: "Fold Current Block", action: Selector(("toggleCurrentFolding:")), modifierFlags: [], key: NSF1FunctionKey),
				MenuSpec(title: "Toggle Foldings at Level", submenu: [
					MenuSpec(title: "All Levels", action: Selector(("takeLevelToFoldFrom:")), keyEquivalent: "0", modifierFlags: [.command, .option]),
					MenuSpec(title: "1", action: Selector(("takeLevelToFoldFrom:")), keyEquivalent: "1", modifierFlags: [.command, .option], tag: 1),
					MenuSpec(title: "2", action: Selector(("takeLevelToFoldFrom:")), keyEquivalent: "2", modifierFlags: [.command, .option], tag: 2),
					MenuSpec(title: "3", action: Selector(("takeLevelToFoldFrom:")), keyEquivalent: "3", modifierFlags: [.command, .option], tag: 3),
					MenuSpec(title: "4", action: Selector(("takeLevelToFoldFrom:")), keyEquivalent: "4", modifierFlags: [.command, .option], tag: 4),
					MenuSpec(title: "5", action: Selector(("takeLevelToFoldFrom:")), keyEquivalent: "5", modifierFlags: [.command, .option], tag: 5),
					MenuSpec(title: "6", action: Selector(("takeLevelToFoldFrom:")), keyEquivalent: "6", modifierFlags: [.command, .option], tag: 6),
					MenuSpec(title: "7", action: Selector(("takeLevelToFoldFrom:")), keyEquivalent: "7", modifierFlags: [.command, .option], tag: 7),
					MenuSpec(title: "8", action: Selector(("takeLevelToFoldFrom:")), keyEquivalent: "8", modifierFlags: [.command, .option], tag: 8),
					MenuSpec(title: "9", action: Selector(("takeLevelToFoldFrom:")), keyEquivalent: "9", modifierFlags: [.command, .option], tag: 9),
				]),
				separatorSpec(),
				MenuSpec(title: "Toggle Scroll Past End", action: Selector(("toggleScrollPastEnd:"))),
				separatorSpec(),
				MenuSpec(title: "View Source", action: Selector(("viewSource:")), keyEquivalent: "u", modifierFlags: [.command, .option]),
				MenuSpec(title: "Enter Full Screen", action: Selector(("toggleFullScreen:")), keyEquivalent: "f", modifierFlags: [.command, .control]),
				separatorSpec(),
				MenuSpec(title: "Customize Touch Bar…", action: Selector(("toggleTouchBarCustomizationPalette:"))),
			]),
			MenuSpec(title: "Navigate", submenu: [
				MenuSpec(title: "Jump to Line…", action: Selector(("orderFrontGoToLinePanel:")), keyEquivalent: "l"),
				MenuSpec(title: "Jump to Symbol…", action: Selector(("showSymbolChooser:")), keyEquivalent: "T"),
				MenuSpec(title: "Jump to Selection", action: Selector(("centerSelectionInVisibleArea:")), keyEquivalent: "j"),
				separatorSpec(),
				MenuSpec(title: "Set Bookmark", action: Selector(("toggleCurrentBookmark:")), key: NSF2FunctionKey),
				MenuSpec(title: "Jump to Next Bookmark", action: Selector(("goToNextBookmark:")), modifierFlags: [], key: NSF2FunctionKey),
				MenuSpec(title: "Jump to Previous Bookmark", action: Selector(("goToPreviousBookmark:")), modifierFlags: [.shift], key: NSF2FunctionKey),
				MenuSpec(title: "Jump to Bookmark", delegate: MBMenuDelegate.delegate(using: Selector(("updateBookmarksMenu:")))),
				separatorSpec(),
				MenuSpec(title: "Jump to Next Mark", action: Selector(("jumpToNextMark:")), modifierFlags: [], key: NSF3FunctionKey),
				MenuSpec(title: "Jump to Previous Mark", action: Selector(("jumpToPreviousMark:")), modifierFlags: [.shift], key: NSF3FunctionKey),
				separatorSpec(),
				MenuSpec(title: "Scroll", submenu: [
					MenuSpec(title: "Line Up", action: Selector(("scrollLineUp:")), modifierFlags: [.command, .option, .control], key: NSUpArrowFunctionKey),
					MenuSpec(title: "Line Down", action: Selector(("scrollLineDown:")), modifierFlags: [.command, .option, .control], key: NSDownArrowFunctionKey),
					MenuSpec(title: "Column Left", action: Selector(("scrollColumnLeft:")), modifierFlags: [.command, .option, .control], key: NSLeftArrowFunctionKey),
					MenuSpec(title: "Column Right", action: Selector(("scrollColumnRight:")), modifierFlags: [.command, .option, .control], key: NSRightArrowFunctionKey),
				]),
				separatorSpec(),
				MenuSpec(title: "Go to Related File", action: Selector(("goToRelatedFile:")), modifierFlags: [.command, .option], key: NSUpArrowFunctionKey),
				separatorSpec(),
				MenuSpec(title: "Move Focus to File Browser", action: Selector(("moveFocus:")), modifierFlags: [.command, .option], key: NSTabCharacter),
			]),
			MenuSpec(title: "Text", submenu: [
				MenuSpec(title: "Transpose", action: Selector(("transpose:"))),
				separatorSpec(),
				MenuSpec(title: "Move Selection", submenu: [
					MenuSpec(title: "Up", action: Selector(("moveSelectionUp:")), modifierFlags: [.command, .control], key: NSUpArrowFunctionKey),
					MenuSpec(title: "Down", action: Selector(("moveSelectionDown:")), modifierFlags: [.command, .control], key: NSDownArrowFunctionKey),
					MenuSpec(title: "Left", action: Selector(("moveSelectionLeft:")), modifierFlags: [.command, .control], key: NSLeftArrowFunctionKey),
					MenuSpec(title: "Right", action: Selector(("moveSelectionRight:")), modifierFlags: [.command, .control], key: NSRightArrowFunctionKey),
				]),
				separatorSpec(),
				MenuSpec(title: "Toggle Case of Character / Selection", action: Selector(("changeCaseOfLetter:"))),
				MenuSpec(title: "Toggle Case of Word / Selection", action: Selector(("changeCaseOfWord:"))),
				separatorSpec(),
				MenuSpec(title: "Uppercase Word / Selection", action: Selector(("uppercaseWord:"))),
				MenuSpec(title: "Lowercase Word / Selection", action: Selector(("lowercaseWord:"))),
				MenuSpec(title: "Titlecase Line / Selection", action: Selector(("capitalizeWord:"))),
				separatorSpec(),
				MenuSpec(title: "Shift Left", action: Selector(("shiftLeft:")), keyEquivalent: "["),
				MenuSpec(title: "Shift Right", action: Selector(("shiftRight:")), keyEquivalent: "]"),
				MenuSpec(title: "Indent Line / Selection", action: Selector(("indent:"))),
				separatorSpec(),
				MenuSpec(title: "Reformat Text", action: Selector(("reformatText:"))),
				MenuSpec(title: "Reformat Text and Justify", action: Selector(("reformatTextAndJustify:"))),
				MenuSpec(title: "Unwrap Paragraph", action: Selector(("unwrapText:"))),
				separatorSpec(),
				MenuSpec(title: "Filter Through Command…", action: Selector(("orderFrontRunCommandWindow:")), keyEquivalent: "|"),
			]),
			MenuSpec(title: "File Browser", submenu: [
				MenuSpec(title: "New File", action: Selector(("newDocumentInDirectory:")), keyEquivalent: "n", modifierFlags: [.command, .control]),
				MenuSpec(title: "New Folder", action: Selector(("newFolder:")), keyEquivalent: "N"),
				separatorSpec(),
				MenuSpec(title: "Back", action: Selector(("goBack:"))),
				MenuSpec(title: "Forward", action: Selector(("goForward:"))),
				MenuSpec(title: "Enclosing Folder", action: Selector(("goToParentFolder:")), key: NSUpArrowFunctionKey),
				separatorSpec(),
				MenuSpec(title: "Select Document", action: Selector(("revealFileInProject:")), keyEquivalent: "r", modifierFlags: [.command, .control]),
				MenuSpec(title: "Select None", action: Selector(("deselectAll:")), keyEquivalent: "A"),
				separatorSpec(),
				MenuSpec(title: "Project Folder", action: Selector(("goToProjectFolder:")), keyEquivalent: "P"),
				MenuSpec(title: "SCM Status", action: Selector(("goToSCMDataSource:")), keyEquivalent: "Y"),
				MenuSpec(title: "Computer", action: Selector(("goToComputer:")), keyEquivalent: "C"),
				MenuSpec(title: "Home", action: Selector(("goToHome:")), keyEquivalent: "H"),
				MenuSpec(title: "Desktop", action: Selector(("goToDesktop:")), keyEquivalent: "D"),
				MenuSpec(title: "Favorites", action: Selector(("goToFavorites:"))),
				separatorSpec(),
				MenuSpec(title: "Go to Folder…", action: Selector(("orderFrontGoToFolder:"))),
				MenuSpec(title: "Reload", action: Selector(("reload:"))),
			]),
			MenuSpec(title: "Bundles", submenuRef: { bundlesMenu = $0 }, submenu: [
				MenuSpec(title: "Select Bundle Item…", action: Selector(("showBundleItemChooser:")), keyEquivalent: "t", modifierFlags: [.command, .control]),
				MenuSpec(title: "Edit Bundles…", action: Selector(("showBundleEditor:")), keyEquivalent: "b", modifierFlags: [.command, .option, .control]),
				separatorSpec(),
			]),
			MenuSpec(title: "Window", systemMenu: .windows, submenu: [
				MenuSpec(title: "Minimize", action: Selector(("miniaturize:")), keyEquivalent: "m"),
				MenuSpec(title: "Zoom", action: Selector(("performZoom:"))),
				separatorSpec(),
				MenuSpec(title: "Show Previous Tab", action: Selector(("selectPreviousTab:")), modifierFlags: [.control, .shift], key: NSTabCharacter),
				MenuSpec(title: "Show Next Tab", action: Selector(("selectNextTab:")), modifierFlags: [.control], key: NSTabCharacter),
				MenuSpec(title: "Show Previous Tab", action: Selector(("selectPreviousTab:")), modifierFlags: [.option, .command], key: NSLeftArrowFunctionKey, hidden: true),
				MenuSpec(title: "Show Next Tab", action: Selector(("selectNextTab:")), modifierFlags: [.option, .command], key: NSRightArrowFunctionKey, hidden: true),
				MenuSpec(title: "Show Previous Tab", action: Selector(("selectPreviousTab:")), keyEquivalent: "{", hidden: true),
				MenuSpec(title: "Show Next Tab", action: Selector(("selectNextTab:")), keyEquivalent: "}", hidden: true),
				MenuSpec(title: "Show Tab", delegate: MBMenuDelegate.delegate(using: Selector(("updateShowTabMenu:")))),
				separatorSpec(),
				MenuSpec(title: "Move Tab to New Window", action: Selector(("moveDocumentToNewWindow:"))),
				MenuSpec(title: "Merge All Windows", action: Selector(("mergeAllWindows:"))),
				separatorSpec(),
				MenuSpec(title: "Bring All to Front", action: Selector(("arrangeInFront:"))),
			]),
			MenuSpec(title: "Help", systemMenu: .help, submenu: [
				MenuSpec(title: "TextMate Help", action: Selector(("showHelp:")), keyEquivalent: "?"),
			]),
		]
		makeMenu(items, into: existingMenu)

		return MainMenuRefs(bundles: bundlesMenu, themes: themesMenu, spelling: spellingMenu, wrapColumn: wrapColumnMenu)
	}

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
