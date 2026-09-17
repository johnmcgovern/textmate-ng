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
// Actions are spelled NSSelectorFromString("…"), not #selector: they are
// dispatched through the responder chain to whatever object answers — text
// views, window controllers, the app delegate, plug-ins — and most are not
// declared in any header this file can see, so #selector has nothing to name.
// (Selector(("…")) said the same thing until Swift started warning on it.)
func separatorSpec() -> MenuSpec {
	return MenuSpec(title: nil, separator: true)
}

// MBCreateMenuItem, branch for branch.
@MainActor private func makeItem(_ spec: MenuSpec) -> NSMenuItem {
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
				let sel = NSSelectorFromString("_setMenuName:")
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
@MainActor func makeMenu(_ items: [MenuSpec], into existingMenu: NSMenu? = nil) -> NSMenu {
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
	@MainActor class func buildMainMenu(into existingMenu: NSMenu, target: AnyObject, appName: String) -> MainMenuRefs {
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
				MenuSpec(title: "About \(appName)", action: NSSelectorFromString("orderFrontAboutPanel:")),
				separatorSpec(),
				MenuSpec(title: "Preferences…", action: NSSelectorFromString("showPreferences:"), keyEquivalent: ","),
				MenuSpec(title: "Check for Update", action: NSSelectorFromString("performSoftwareUpdateCheck:")),
				MenuSpec(title: "Check for Test Build", action: NSSelectorFromString("performSoftwareUpdateCheck:"), modifierFlags: [.command, .option], alternate: true),
				separatorSpec(),
				MenuSpec(title: "Services", systemMenu: .services),
				separatorSpec(),
				MenuSpec(title: "Hide \(appName)", action: NSSelectorFromString("hide:"), keyEquivalent: "h"),
				MenuSpec(title: "Hide Others", action: NSSelectorFromString("hideOtherApplications:"), keyEquivalent: "h", modifierFlags: [.command, .option]),
				MenuSpec(title: "Show All", action: NSSelectorFromString("unhideAllApplications:")),
				separatorSpec(),
				MenuSpec(title: "Quit \(appName)", action: NSSelectorFromString("terminate:"), keyEquivalent: "q"),
			]),
			MenuSpec(title: "File", submenu: [
				MenuSpec(title: "New", action: NSSelectorFromString("newDocument:"), keyEquivalent: "n"),
				MenuSpec(title: "New File Browser", action: NSSelectorFromString("newFileBrowser:"), keyEquivalent: "n", modifierFlags: [.command, .option, .control], alternate: true),
				MenuSpec(title: "New Tab", action: NSSelectorFromString("newDocumentInTab:"), keyEquivalent: "n", modifierFlags: [.command, .option]),
				separatorSpec(),
				MenuSpec(title: "Open…", action: NSSelectorFromString("openDocument:"), keyEquivalent: "o"),
				MenuSpec(title: "Open Quickly…", action: NSSelectorFromString("goToFile:"), keyEquivalent: "t"),
				MenuSpec(title: "Open Recent", systemMenu: .openRecent, submenu: [
					MenuSpec(title: "Clear Menu", action: NSSelectorFromString("clearRecentDocuments:")),
				]),
				MenuSpec(title: "Open Recent Project…", action: NSSelectorFromString("openFavorites:"), keyEquivalent: "O"),
				separatorSpec(),
				MenuSpec(title: "Close", action: NSSelectorFromString("performClose:"), keyEquivalent: "w"),
				MenuSpec(title: "Close Window", action: NSSelectorFromString("performCloseWindow:"), keyEquivalent: "W"),
				MenuSpec(title: "Close All Tabs", action: NSSelectorFromString("performCloseAllTabs:"), keyEquivalent: "w", modifierFlags: [.command, .option, .control]),
				MenuSpec(title: "Close Other Tabs", action: NSSelectorFromString("performCloseOtherTabsXYZ:"), keyEquivalent: "w", modifierFlags: [.command, .control]),
				MenuSpec(title: "Close Tabs to the Right", action: NSSelectorFromString("performCloseTabsToTheRight:")),
				MenuSpec(title: "Close Tabs to the Left", action: NSSelectorFromString("performCloseTabsToTheLeft:"), modifierFlags: [.command, .option], alternate: true),
				separatorSpec(),
				MenuSpec(title: "Sticky", action: NSSelectorFromString("toggleSticky:")),
				separatorSpec(),
				MenuSpec(title: "Save", action: NSSelectorFromString("saveDocument:"), keyEquivalent: "s"),
				MenuSpec(title: "Save As…", action: NSSelectorFromString("saveDocumentAs:"), keyEquivalent: "S"),
				MenuSpec(title: "Save All", action: NSSelectorFromString("saveAllDocuments:"), keyEquivalent: "s", modifierFlags: [.command, .option]),
				MenuSpec(title: "Revert", action: NSSelectorFromString("revertDocumentToSaved:")),
				separatorSpec(),
				MenuSpec(title: "Page Setup…", action: NSSelectorFromString("runPageLayout:"), target: NSApp.delegate),
				MenuSpec(title: "Print…", action: NSSelectorFromString("printDocument:"), keyEquivalent: "p"),
			]),
			MenuSpec(title: "Edit", submenu: [
				MenuSpec(title: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z"),
				MenuSpec(title: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "Z"),
				separatorSpec(),
				MenuSpec(title: "Cut", action: NSSelectorFromString("cut:"), keyEquivalent: "x"),
				MenuSpec(title: "Copy", action: NSSelectorFromString("copy:"), keyEquivalent: "c"),
				MenuSpec(title: "Paste", submenu: [
					MenuSpec(title: "Paste", action: NSSelectorFromString("paste:"), keyEquivalent: "v"),
					MenuSpec(title: "Paste Without Indenting", action: NSSelectorFromString("pasteWithoutReindent:"), keyEquivalent: "v", modifierFlags: [.command, .control], alternate: true),
					MenuSpec(title: "Paste Next", action: NSSelectorFromString("pasteNext:"), keyEquivalent: "v", modifierFlags: [.command, .option]),
					MenuSpec(title: "Paste Previous", action: NSSelectorFromString("pastePrevious:"), keyEquivalent: "V"),
					separatorSpec(),
					MenuSpec(title: "Show History", action: NSSelectorFromString("showClipboardHistory:"), keyEquivalent: "v", modifierFlags: [.command, .option, .control]),
				]),
				MenuSpec(title: "Delete", action: NSSelectorFromString("delete:"), key: NSBackspaceCharacter),
				separatorSpec(),
				MenuSpec(title: "Macros", submenu: [
					MenuSpec(title: "Start Recording", action: NSSelectorFromString("toggleMacroRecording:"), keyEquivalent: "m", modifierFlags: [.command, .option]),
					MenuSpec(title: "Replay Macro", action: NSSelectorFromString("playScratchMacro:"), keyEquivalent: "M"),
					MenuSpec(title: "Save Macro…", action: NSSelectorFromString("saveScratchMacro:"), keyEquivalent: "m", modifierFlags: [.command, .control]),
				]),
				separatorSpec(),
				MenuSpec(title: "Select", submenu: [
					MenuSpec(title: "Word", action: NSSelectorFromString("selectWord:")),
					MenuSpec(title: "Line", action: NSSelectorFromString("selectHardLine:")),
					MenuSpec(title: "Paragraph", action: NSSelectorFromString("selectParagraph:")),
					MenuSpec(title: "Current Scope", action: NSSelectorFromString("selectCurrentScope:")),
					MenuSpec(title: "Enclosing Typing Pairs", action: NSSelectorFromString("selectBlock:"), keyEquivalent: "B"),
					MenuSpec(title: "All", action: NSSelectorFromString("selectAll:"), keyEquivalent: "a"),
					separatorSpec(),
					MenuSpec(title: "Toggle Column Selection", action: NSSelectorFromString("toggleColumnSelection:"), modifierFlags: [.option]),
				]),
				MenuSpec(title: "Find", submenu: [
					MenuSpec(title: "Find and Replace…", action: NSSelectorFromString("orderFrontFindPanel:"), keyEquivalent: "f", tag: 0),
					MenuSpec(title: "Find in Project…", action: NSSelectorFromString("orderFrontFindPanel:"), keyEquivalent: "F", tag: 3),
					MenuSpec(title: "Find in Folder…", action: NSSelectorFromString("orderFrontFindPanel:"), tag: 5),
					separatorSpec(),
					MenuSpec(title: "Show Find History", action: NSSelectorFromString("showFindHistory:"), keyEquivalent: "f", modifierFlags: [.command, .option, .control]),
					separatorSpec(),
					MenuSpec(title: "Incremental Search", action: NSSelectorFromString("incrementalSearch:"), keyEquivalent: "s", modifierFlags: [.control]),
					MenuSpec(title: "Incremental Search Previous", action: NSSelectorFromString("incrementalSearchPrevious:"), keyEquivalent: "S", modifierFlags: [.control]),
					separatorSpec(),
					MenuSpec(title: "Find Next", action: NSSelectorFromString("findNext:"), keyEquivalent: "g"),
					MenuSpec(title: "Find Previous", action: NSSelectorFromString("findPrevious:"), keyEquivalent: "G"),
					MenuSpec(title: "Find All", action: NSSelectorFromString("findAllInSelection:"), keyEquivalent: "f", modifierFlags: [.command, .option]),
					separatorSpec(),
					MenuSpec(title: "Find Options", submenu: [
						MenuSpec(title: "Ignore Case", action: NSSelectorFromString("toggleFindOption:"), keyEquivalent: "c", modifierFlags: [.command, .option], tag: 2),
						MenuSpec(title: "Regular Expression", action: NSSelectorFromString("toggleFindOption:"), keyEquivalent: "r", modifierFlags: [.command, .option], tag: 8),
						MenuSpec(title: "Ignore Whitespace", action: NSSelectorFromString("toggleFindOption:"), tag: 4),
						MenuSpec(title: "Wrap Around", action: NSSelectorFromString("toggleFindOption:"), keyEquivalent: "a", modifierFlags: [.command, .option], tag: 128),
					]),
					separatorSpec(),
					MenuSpec(title: "Replace", action: NSSelectorFromString("replace:"), keyEquivalent: "g", modifierFlags: [.command, .option]),
					MenuSpec(title: "Replace & Find", action: NSSelectorFromString("replaceAndFind:")),
					MenuSpec(title: "Replace All", action: NSSelectorFromString("replaceAll:"), keyEquivalent: "g", modifierFlags: [.command, .control]),
					MenuSpec(title: "Replace All in Selection", action: NSSelectorFromString("replaceAllInSelection:"), keyEquivalent: "G", modifierFlags: [.command, .control]),
					separatorSpec(),
					MenuSpec(title: "Use Selection for Find", action: NSSelectorFromString("copySelectionToFindPboard:"), keyEquivalent: "e"),
					MenuSpec(title: "Use Selection for Replace", action: NSSelectorFromString("copySelectionToReplacePboard:"), keyEquivalent: "E"),
				]),
				MenuSpec(title: "Spelling", submenuRef: { spellingMenu = $0 }, submenu: [
					MenuSpec(title: "Spelling…", action: NSSelectorFromString("showGuessPanel:"), keyEquivalent: ":"),
					MenuSpec(title: "Check Document Now", action: NSSelectorFromString("checkSpelling:"), keyEquivalent: ";"),
					separatorSpec(),
					MenuSpec(title: "Check Spelling While Typing", action: NSSelectorFromString("toggleContinuousSpellChecking:"), keyEquivalent: ";", modifierFlags: [.command, .option]),
					separatorSpec(),
				]),
			]),
			MenuSpec(title: "View", submenu: [
				MenuSpec(title: "Font", systemMenu: .font, submenu: [
					MenuSpec(title: "Show Fonts", action: NSSelectorFromString("orderFrontFontPanel:"), target: NSFontManager.shared),
					separatorSpec(),
					MenuSpec(title: "Bigger", action: NSSelectorFromString("makeTextLarger:"), keyEquivalent: "+"),
					MenuSpec(title: "Smaller", action: NSSelectorFromString("makeTextSmaller:"), keyEquivalent: "-"),
					MenuSpec(title: "Default Size", action: NSSelectorFromString("makeTextStandardSize:"), keyEquivalent: "0"),
				]),
				MenuSpec(title: "Show File Browser", action: NSSelectorFromString("toggleFileBrowser:"), keyEquivalent: "d", modifierFlags: [.command, .option, .control]),
				MenuSpec(title: "Show HTML Output", action: NSSelectorFromString("toggleHTMLOutput:"), keyEquivalent: "h", modifierFlags: [.command, .option, .control]),
				MenuSpec(title: "Show Line Numbers", action: NSSelectorFromString("toggleLineNumbers:"), keyEquivalent: "l", modifierFlags: [.command, .option]),
				separatorSpec(),
				MenuSpec(title: "Show Invisibles", action: NSSelectorFromString("toggleShowInvisibles:"), keyEquivalent: "i", modifierFlags: [.command, .option]),
				separatorSpec(),
				MenuSpec(title: "Enable Soft Wrap", action: NSSelectorFromString("toggleSoftWrap:"), keyEquivalent: "w", modifierFlags: [.command, .option]),
				MenuSpec(title: "Show Wrap Column", action: NSSelectorFromString("toggleShowWrapColumn:")),
				MenuSpec(title: "Show Indent Guides", action: NSSelectorFromString("toggleShowIndentGuides:")),
				MenuSpec(title: "Wrap Column", submenuRef: { wrapColumnMenu = $0 }, submenu: [
					MenuSpec(title: "Use Window Frame", action: NSSelectorFromString("takeWrapColumnFrom:")),
					separatorSpec(),
					MenuSpec(title: "40", action: NSSelectorFromString("takeWrapColumnFrom:"), tag: 40),
					MenuSpec(title: "80", action: NSSelectorFromString("takeWrapColumnFrom:"), tag: 80),
					separatorSpec(),
					MenuSpec(title: "Other…", action: NSSelectorFromString("takeWrapColumnFrom:"), tag: -1),
				]),
				separatorSpec(),
				MenuSpec(title: "Tab Size", submenu: [
					MenuSpec(title: "2", action: NSSelectorFromString("takeTabSizeFrom:"), tag: 2),
					MenuSpec(title: "3", action: NSSelectorFromString("takeTabSizeFrom:"), tag: 3),
					MenuSpec(title: "4", action: NSSelectorFromString("takeTabSizeFrom:"), tag: 4),
					MenuSpec(title: "5", action: NSSelectorFromString("takeTabSizeFrom:"), tag: 5),
					MenuSpec(title: "6", action: NSSelectorFromString("takeTabSizeFrom:"), tag: 6),
					MenuSpec(title: "7", action: NSSelectorFromString("takeTabSizeFrom:"), tag: 7),
					MenuSpec(title: "8", action: NSSelectorFromString("takeTabSizeFrom:"), tag: 8),
					separatorSpec(),
					MenuSpec(title: "Other…", action: NSSelectorFromString("showTabSizeSelectorPanel:")),
				]),
				MenuSpec(title: "Theme", submenuRef: { themesMenu = $0 }),
				separatorSpec(),
				MenuSpec(title: "Fold Current Block", action: NSSelectorFromString("toggleCurrentFolding:"), modifierFlags: [], key: NSF1FunctionKey),
				MenuSpec(title: "Toggle Foldings at Level", submenu: [
					MenuSpec(title: "All Levels", action: NSSelectorFromString("takeLevelToFoldFrom:"), keyEquivalent: "0", modifierFlags: [.command, .option]),
					MenuSpec(title: "1", action: NSSelectorFromString("takeLevelToFoldFrom:"), keyEquivalent: "1", modifierFlags: [.command, .option], tag: 1),
					MenuSpec(title: "2", action: NSSelectorFromString("takeLevelToFoldFrom:"), keyEquivalent: "2", modifierFlags: [.command, .option], tag: 2),
					MenuSpec(title: "3", action: NSSelectorFromString("takeLevelToFoldFrom:"), keyEquivalent: "3", modifierFlags: [.command, .option], tag: 3),
					MenuSpec(title: "4", action: NSSelectorFromString("takeLevelToFoldFrom:"), keyEquivalent: "4", modifierFlags: [.command, .option], tag: 4),
					MenuSpec(title: "5", action: NSSelectorFromString("takeLevelToFoldFrom:"), keyEquivalent: "5", modifierFlags: [.command, .option], tag: 5),
					MenuSpec(title: "6", action: NSSelectorFromString("takeLevelToFoldFrom:"), keyEquivalent: "6", modifierFlags: [.command, .option], tag: 6),
					MenuSpec(title: "7", action: NSSelectorFromString("takeLevelToFoldFrom:"), keyEquivalent: "7", modifierFlags: [.command, .option], tag: 7),
					MenuSpec(title: "8", action: NSSelectorFromString("takeLevelToFoldFrom:"), keyEquivalent: "8", modifierFlags: [.command, .option], tag: 8),
					MenuSpec(title: "9", action: NSSelectorFromString("takeLevelToFoldFrom:"), keyEquivalent: "9", modifierFlags: [.command, .option], tag: 9),
				]),
				separatorSpec(),
				MenuSpec(title: "Toggle Scroll Past End", action: NSSelectorFromString("toggleScrollPastEnd:")),
				separatorSpec(),
				MenuSpec(title: "View Source", action: NSSelectorFromString("viewSource:"), keyEquivalent: "u", modifierFlags: [.command, .option]),
				MenuSpec(title: "Enter Full Screen", action: NSSelectorFromString("toggleFullScreen:"), keyEquivalent: "f", modifierFlags: [.command, .control]),
				separatorSpec(),
				MenuSpec(title: "Customize Touch Bar…", action: NSSelectorFromString("toggleTouchBarCustomizationPalette:")),
			]),
			MenuSpec(title: "Navigate", submenu: [
				MenuSpec(title: "Jump to Line…", action: NSSelectorFromString("orderFrontGoToLinePanel:"), keyEquivalent: "l"),
				MenuSpec(title: "Jump to Symbol…", action: NSSelectorFromString("showSymbolChooser:"), keyEquivalent: "T"),
				MenuSpec(title: "Jump to Selection", action: NSSelectorFromString("centerSelectionInVisibleArea:"), keyEquivalent: "j"),
				separatorSpec(),
				MenuSpec(title: "Set Bookmark", action: NSSelectorFromString("toggleCurrentBookmark:"), key: NSF2FunctionKey),
				MenuSpec(title: "Jump to Next Bookmark", action: NSSelectorFromString("goToNextBookmark:"), modifierFlags: [], key: NSF2FunctionKey),
				MenuSpec(title: "Jump to Previous Bookmark", action: NSSelectorFromString("goToPreviousBookmark:"), modifierFlags: [.shift], key: NSF2FunctionKey),
				MenuSpec(title: "Jump to Bookmark", delegate: MBMenuDelegate.delegate(using: NSSelectorFromString("updateBookmarksMenu:"))),
				separatorSpec(),
				MenuSpec(title: "Jump to Next Mark", action: NSSelectorFromString("jumpToNextMark:"), modifierFlags: [], key: NSF3FunctionKey),
				MenuSpec(title: "Jump to Previous Mark", action: NSSelectorFromString("jumpToPreviousMark:"), modifierFlags: [.shift], key: NSF3FunctionKey),
				separatorSpec(),
				MenuSpec(title: "Scroll", submenu: [
					MenuSpec(title: "Line Up", action: NSSelectorFromString("scrollLineUp:"), modifierFlags: [.command, .option, .control], key: NSUpArrowFunctionKey),
					MenuSpec(title: "Line Down", action: NSSelectorFromString("scrollLineDown:"), modifierFlags: [.command, .option, .control], key: NSDownArrowFunctionKey),
					MenuSpec(title: "Column Left", action: NSSelectorFromString("scrollColumnLeft:"), modifierFlags: [.command, .option, .control], key: NSLeftArrowFunctionKey),
					MenuSpec(title: "Column Right", action: NSSelectorFromString("scrollColumnRight:"), modifierFlags: [.command, .option, .control], key: NSRightArrowFunctionKey),
				]),
				separatorSpec(),
				MenuSpec(title: "Go to Related File", action: NSSelectorFromString("goToRelatedFile:"), modifierFlags: [.command, .option], key: NSUpArrowFunctionKey),
				separatorSpec(),
				MenuSpec(title: "Move Focus to File Browser", action: NSSelectorFromString("moveFocus:"), modifierFlags: [.command, .option], key: NSTabCharacter),
			]),
			MenuSpec(title: "Text", submenu: [
				MenuSpec(title: "Transpose", action: NSSelectorFromString("transpose:")),
				separatorSpec(),
				MenuSpec(title: "Move Selection", submenu: [
					MenuSpec(title: "Up", action: NSSelectorFromString("moveSelectionUp:"), modifierFlags: [.command, .control], key: NSUpArrowFunctionKey),
					MenuSpec(title: "Down", action: NSSelectorFromString("moveSelectionDown:"), modifierFlags: [.command, .control], key: NSDownArrowFunctionKey),
					MenuSpec(title: "Left", action: NSSelectorFromString("moveSelectionLeft:"), modifierFlags: [.command, .control], key: NSLeftArrowFunctionKey),
					MenuSpec(title: "Right", action: NSSelectorFromString("moveSelectionRight:"), modifierFlags: [.command, .control], key: NSRightArrowFunctionKey),
				]),
				separatorSpec(),
				MenuSpec(title: "Toggle Case of Character / Selection", action: NSSelectorFromString("changeCaseOfLetter:")),
				MenuSpec(title: "Toggle Case of Word / Selection", action: NSSelectorFromString("changeCaseOfWord:")),
				separatorSpec(),
				MenuSpec(title: "Uppercase Word / Selection", action: NSSelectorFromString("uppercaseWord:")),
				MenuSpec(title: "Lowercase Word / Selection", action: NSSelectorFromString("lowercaseWord:")),
				MenuSpec(title: "Titlecase Line / Selection", action: NSSelectorFromString("capitalizeWord:")),
				separatorSpec(),
				MenuSpec(title: "Shift Left", action: NSSelectorFromString("shiftLeft:"), keyEquivalent: "["),
				MenuSpec(title: "Shift Right", action: NSSelectorFromString("shiftRight:"), keyEquivalent: "]"),
				MenuSpec(title: "Indent Line / Selection", action: NSSelectorFromString("indent:")),
				separatorSpec(),
				MenuSpec(title: "Reformat Text", action: NSSelectorFromString("reformatText:")),
				MenuSpec(title: "Reformat Text and Justify", action: NSSelectorFromString("reformatTextAndJustify:")),
				MenuSpec(title: "Unwrap Paragraph", action: NSSelectorFromString("unwrapText:")),
				separatorSpec(),
				MenuSpec(title: "Filter Through Command…", action: NSSelectorFromString("orderFrontRunCommandWindow:"), keyEquivalent: "|"),
			]),
			MenuSpec(title: "File Browser", submenu: [
				MenuSpec(title: "New File", action: NSSelectorFromString("newDocumentInDirectory:"), keyEquivalent: "n", modifierFlags: [.command, .control]),
				MenuSpec(title: "New Folder", action: NSSelectorFromString("newFolder:"), keyEquivalent: "N"),
				separatorSpec(),
				MenuSpec(title: "Back", action: NSSelectorFromString("goBack:")),
				MenuSpec(title: "Forward", action: NSSelectorFromString("goForward:")),
				MenuSpec(title: "Enclosing Folder", action: NSSelectorFromString("goToParentFolder:"), key: NSUpArrowFunctionKey),
				separatorSpec(),
				MenuSpec(title: "Select Document", action: NSSelectorFromString("revealFileInProject:"), keyEquivalent: "r", modifierFlags: [.command, .control]),
				MenuSpec(title: "Select None", action: NSSelectorFromString("deselectAll:"), keyEquivalent: "A"),
				separatorSpec(),
				MenuSpec(title: "Project Folder", action: NSSelectorFromString("goToProjectFolder:"), keyEquivalent: "P"),
				MenuSpec(title: "SCM Status", action: NSSelectorFromString("goToSCMDataSource:"), keyEquivalent: "Y"),
				MenuSpec(title: "Computer", action: NSSelectorFromString("goToComputer:"), keyEquivalent: "C"),
				MenuSpec(title: "Home", action: NSSelectorFromString("goToHome:"), keyEquivalent: "H"),
				MenuSpec(title: "Desktop", action: NSSelectorFromString("goToDesktop:"), keyEquivalent: "D"),
				MenuSpec(title: "Favorites", action: NSSelectorFromString("goToFavorites:")),
				separatorSpec(),
				MenuSpec(title: "Go to Folder…", action: NSSelectorFromString("orderFrontGoToFolder:")),
				MenuSpec(title: "Reload", action: NSSelectorFromString("reload:")),
			]),
			MenuSpec(title: "Bundles", submenuRef: { bundlesMenu = $0 }, submenu: [
				MenuSpec(title: "Select Bundle Item…", action: NSSelectorFromString("showBundleItemChooser:"), keyEquivalent: "t", modifierFlags: [.command, .control]),
				MenuSpec(title: "Edit Bundles…", action: NSSelectorFromString("showBundleEditor:"), keyEquivalent: "b", modifierFlags: [.command, .option, .control]),
				separatorSpec(),
			]),
			MenuSpec(title: "Window", systemMenu: .windows, submenu: [
				MenuSpec(title: "Minimize", action: NSSelectorFromString("miniaturize:"), keyEquivalent: "m"),
				MenuSpec(title: "Zoom", action: NSSelectorFromString("performZoom:")),
				separatorSpec(),
				MenuSpec(title: "Show Previous Tab", action: NSSelectorFromString("selectPreviousTab:"), modifierFlags: [.control, .shift], key: NSTabCharacter),
				MenuSpec(title: "Show Next Tab", action: NSSelectorFromString("selectNextTab:"), modifierFlags: [.control], key: NSTabCharacter),
				MenuSpec(title: "Show Previous Tab", action: NSSelectorFromString("selectPreviousTab:"), modifierFlags: [.option, .command], key: NSLeftArrowFunctionKey, hidden: true),
				MenuSpec(title: "Show Next Tab", action: NSSelectorFromString("selectNextTab:"), modifierFlags: [.option, .command], key: NSRightArrowFunctionKey, hidden: true),
				MenuSpec(title: "Show Previous Tab", action: NSSelectorFromString("selectPreviousTab:"), keyEquivalent: "{", hidden: true),
				MenuSpec(title: "Show Next Tab", action: NSSelectorFromString("selectNextTab:"), keyEquivalent: "}", hidden: true),
				MenuSpec(title: "Show Tab", delegate: MBMenuDelegate.delegate(using: NSSelectorFromString("updateShowTabMenu:"))),
				separatorSpec(),
				MenuSpec(title: "Move Tab to New Window", action: NSSelectorFromString("moveDocumentToNewWindow:")),
				MenuSpec(title: "Merge All Windows", action: NSSelectorFromString("mergeAllWindows:")),
				separatorSpec(),
				MenuSpec(title: "Bring All to Front", action: NSSelectorFromString("arrangeInFront:")),
			]),
			MenuSpec(title: "Help", systemMenu: .help, submenu: [
				MenuSpec(title: "TextMate Help", action: NSSelectorFromString("showHelp:"), keyEquivalent: "?"),
			]),
		]
		makeMenu(items, into: existingMenu)

		return MainMenuRefs(bundles: bundlesMenu, themes: themesMenu, spelling: spellingMenu, wrapColumn: wrapColumnMenu)
	}

	// The two submenus -themesMenuNeedsUpdate: fills in afterwards, from the bundle
	// index. Same `.submenuRef` shape as the main menu's four.
	@objc(TMThemeMenuRefs) class ThemeMenuRefs: NSObject {
		@objc let lightMenu: NSMenu?
		@objc let darkMenu: NSMenu?

		init(light: NSMenu?, dark: NSMenu?) {
			lightMenu = light
			darkMenu  = dark
		}
	}

	// The fixed part of the Theme menu — everything above the two per-appearance
	// submenus, which -themesMenuNeedsUpdate: populates from the bundle index and
	// which stay in ObjC++ because that walk is bundles::query and std::multimap.
	//
	// Testable on its own, which the ObjC++ was not: the literal sat below an early
	// return that always fires in a test process, since no bundle index loads there.
	// Its golden was captured by running the original literal once, verbatim, in a
	// throwaway probe.
	@objc(buildThemeMenuInto:target:)
	@MainActor class func buildThemeMenu(into existingMenu: NSMenu, target: AnyObject) -> ThemeMenuRefs {
		var lightMenu: NSMenu?
		var darkMenu: NSMenu?

		let items: [MenuSpec] = [
			MenuSpec(title: "Appearance", action: NSSelectorFromString("nop:")),
			MenuSpec(title: "Light", action: NSSelectorFromString("takeThemeAppearanceFrom:"), indent: 1, target: target, representedObject: "light"),
			MenuSpec(title: "Dark", action: NSSelectorFromString("takeThemeAppearanceFrom:"), indent: 1, target: target, representedObject: "dark"),
			MenuSpec(title: "Auto", action: NSSelectorFromString("takeThemeAppearanceFrom:"), indent: 1, target: target, representedObject: nil),
			separatorSpec(),
			MenuSpec(title: "Theme for Light Appearance", submenuRef: { lightMenu = $0 }),
			MenuSpec(title: "Theme for Dark Appearance", submenuRef: { darkMenu = $0 }),
		]
		makeMenu(items, into: existingMenu)

		return ThemeMenuRefs(light: lightMenu, dark: darkMenu)
	}

	// -[AppController applicationDockMenu:]. The only place the app sets an
	// explicit `.target`: the dock menu is shown with no key window, so the
	// responder chain cannot be relied on.
	@objc(dockMenuWithTarget:) @MainActor class func dockMenu(target: AnyObject) -> NSMenu {
		let items: [MenuSpec] = [
			MenuSpec(title: "New File", action: NSSelectorFromString("newDocumentAndActivate:"),  target: target),
			MenuSpec(title: "Open…",    action: NSSelectorFromString("openDocumentAndActivate:"), target: target),
		]
		return makeMenu(items)
	}
}
