import AppKit
import CoreServices

// FileBrowserViewController — the flip.
//
// The last ObjC++ in this framework's port, and the commit where the *class
// definition* moves rather than another section of methods. The nine Swift
// extensions that were peeled off ahead of this (FileBrowserDiskOperations,
// …OutlineViewDataSource, …TableCells, …AcceptDrop, …Actions, …Pasteboard,
// …MenuValidation, …QuickLook, …Loading) now extend a Swift class instead of an
// ObjC++ one, and needed no changes for it beyond the two noted below.
//
// **Two methods did not come across, and never will**: -variables and
// -updateMenu:, which live in FileBrowserViewControllerCxx.mm as an ObjC++
// category on this class — the DocumentWindowController arrangement (rule 23).
// -variables is pinned by DocumentWindowSupport.mm, which passes it a
// std::map; -updateMenu: builds an `MBMenu`, which is a std::vector behind a
// typedef. -menuNeedsUpdate: goes with the latter because the direction of that
// file only runs one way: an ObjC++ category may call into this Swift, but this
// Swift cannot call back into the category without putting the class's header
// back in the bridging header and declaring the class twice.
//
// -presentError: also stays ObjC++, in FileBrowserDiskOperationsSupport.mm, but
// for a new reason — see the note there. Rule 31 stopped applying at this
// commit; nullability took its place.
//
// **Private state that used to be a class extension is just private state
// now**, and FileBrowserViewControllerInternal.h / FileBrowserActions.h are
// deleted. The one thing to carry forward from the first of those is rule 46:
// the pending expand/select sets and the merged accessors of nearly the same
// name are *different values*, and conflating them shipped a crash once. Here
// they are `pendingExpandedURLs` (stored) and `expandedURLs` (computed), and the
// distinction is now enforced by them being different declarations rather than
// by a comment.
// The AppKit conformances are declared on the class, below. That was not true
// when the flip landed: the peeled sections spelled their parameters with the
// concrete type the browser receives (`item: FileItem`), which makes each of
// them "conflicts with optional requirement" the moment Swift sees the
// conformance, so they lived on an ObjC category instead and the three
// assignment sites went through a `+wire…` helper. Fourteen signatures were
// widened to the protocol's own types afterwards, which is what let all of that
// be deleted — see rule 47.
@objc(FileBrowserViewController)
class FileBrowserViewController: NSViewController, NSMenuDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate,
                                 // @preconcurrency on these two only: the compiler reports it as
                                 // having no effect on the three AppKit protocols above, and warns
                                 // if it is written there anyway.
                                 @preconcurrency OakUserDefaultsObserver, @preconcurrency FileBrowserOutlineViewDelegate {

	// ==========================================================
	// = Private state (was the class extension in the .mm)     =
	// ==========================================================
	//
	// Ownership is copied across unchanged (rule 27). Every one of these was an
	// unannotated strong `@property` or ivar; none was `weak`, and a flip is not
	// the moment to reconsider that.

	private var fileBrowserUndoManager: UndoManager?

	// Read and written by FileBrowserQuickLook.swift, which owns this state.
	@objc var previewItems: [FileItem]?

	// Assigned here in -updateMenu:, which is ObjC++ in
	// FileBrowserViewControllerCxx.mm, so it has to be @objc and settable from
	// there. `private` and `@objc` compose: the selector exists for the category,
	// the name does not leak into this module's other files.
	@objc fileprivate var openWithMenuDelegate: OakOpenWithMenuDelegate?

	@objc var fileItemObservers: NSMutableDictionary?
	@objc var loadingURLs: NSMutableSet?
	// `@convention(block)` so the array is representable in ObjC — the ObjC++
	// declared it `NSArray<void(^)(void)>*`, and the test reads it through KVC to
	// check that the handlers were drained rather than merely appended to.
	@objc var loadingURLsCompletionHandlers: [@convention(block) () -> Void]?

	@objc var expandingChildrenCounter: Int = 0
	@objc var collapsingChildrenCounter: Int = 0
	@objc var nestedCollapsingChildrenCounter: Int = 0

	// **The pending sets.** URLs the browser has been asked to expand or select
	// and has not reached yet. Not to be confused with `expandedURLs` /
	// `selectedURLs` below, which merge these with what the outline view is
	// currently showing — that conflation is rule 46 and it crashed the app.
	@objc var pendingExpandedURLs: NSMutableSet?
	@objc var pendingSelectedURLs: NSMutableSet?

	// The binding source for the current-location menu item's image
	// ("fileReference.image"), so it carries rule 1's `dynamic` — without it the
	// menu item's icon never updates.
	@objc dynamic var fileReference: TMFileReference?

	private var currentLocationMenuItem: NSMenuItem?

	// ==========================================================
	// = The public surface (FileBrowserViewController.h)       =
	// ==========================================================

	@objc weak var delegate: FileBrowserDelegate?

	// `dynamic`: the current-location menu item binds its title to
	// "fileItem.displayName", and t_file_browser_view_controller.mm pins that
	// with a real NSMenuItem.
	//
	// Implicitly unwrapped rather than Optional, deliberately: this is how the
	// ObjC++ property imported, and the nine extensions were written against
	// that. Narrowing it here would be a second change riding along inside the
	// flip; `fileItem?.` and `fileItem.map` both still read correctly.
	@objc dynamic var fileItem: FileItem! {
		get { return fileItemStorage }
		set { setFileItemStorage(newValue) }
	}
	private var fileItemStorage: FileItem?

	@objc var URL: NSURL? {
		get { return fileItemStorage?.URL }
		set {
			if let newValue, let item = FileItem.fileItem(withURL: newValue) {
				self.fileItem = item
			}
		}
	}

	@objc var path: String? {
		return URL?.filePathURL?.path
	}

	@objc var selectedFileURLs: [NSURL] {
		// `URL.isFileURL == YES` as an NSPredicate, then -valueForKeyPath:@"URL",
		// in the ObjC++. Native here: the predicate bought nothing but a string.
		return selectedItems.compactMap { $0.URL }.filter { $0.isFileURL }
	}

	@objc var headerView: NSView? { return fileBrowserView.headerView }
	@objc var outlineView: NSOutlineView! { return fileBrowserView.outlineView }

	// ==========================================================
	// = History                                                =
	// ==========================================================
	//
	// Exposed to ObjC as an NSArray rather than the NSMutableArray the ObjC++
	// declared, because the test drives it through KVC
	// (`setValue:@[…] forKey:@"history"`) and a Swift setter typed
	// NSMutableArray would trap on the immutable array it passes. Storage is a
	// native array; the setter copies, which is what every ObjC++ caller did
	// anyway (`[newHistory mutableCopy]`).
	@objc dynamic var history: NSArray {
		get { return historyStorage as NSArray }
		set { historyStorage = (newValue as? [[String: Any]]) ?? [] }
	}
	private var historyStorage: [[String: Any]] = []

	@objc dynamic var historyIndex: Int {
		get { return historyIndexStorage }
		set {
			historyIndexStorage = newValue
			// The ObjC++ read self.history[index][@"url"] unguarded and would have
			// thrown on a bad index; nothing reaches this with one, and a Swift
			// subscript would trap rather than throw. Guarded, and the guard is the
			// only behavioural difference in this property.
			if newValue >= 0 && newValue < historyStorage.count {
				self.URL = historyStorage[newValue]["url"] as? NSURL
			}
		}
	}
	private var historyIndexStorage: Int = 0

	@objc class func keyPathsForValuesAffectingCanGoBack() -> Set<String> {
		return [ "historyIndex" ]
	}

	@objc class func keyPathsForValuesAffectingCanGoForward() -> Set<String> {
		return [ "historyIndex" ]
	}

	// Methods rather than properties, as the public header declares them; the two
	// nav buttons bind their enabled state to these key paths and KVC reaches a
	// method just as well as a getter.
	@objc func canGoBack() -> Bool { return historyIndexStorage > 0 }
	@objc func canGoForward() -> Bool { return historyIndexStorage + 1 < historyStorage.count }

	@objc(goBack:)    func goBack(_ sender: Any?)    { historyIndex = historyIndexStorage - 1 }
	@objc(goForward:) func goForward(_ sender: Any?) { historyIndex = historyIndexStorage + 1 }

	@objc(addHistoryURL:)
	func addHistoryURL(_ url: NSURL) {
		if historyIndexStorage + 1 < historyStorage.count {
			historyStorage.removeSubrange((historyIndexStorage + 1) ..< historyStorage.count)
		}

		// The scroll offset of the entry being left, recorded on the way out so
		// going back restores where the user was.
		if var last = historyStorage.last {
			last["scrollOffset"] = NSNumber(value: Double(outlineView.visibleRect.minY))
			historyStorage[historyStorage.count - 1] = [
				"url":          last["url"] as Any,
				"scrollOffset": last["scrollOffset"] as Any,
			]
		}

		historyStorage.append([ "url": url ])
		historyIndex = historyStorage.count - 1
	}

	// ==========================================================
	// = Construction                                           =
	// ==========================================================

	// The two legacy pasteboard types the services menu registration and
	// -validRequestorForSendType:returnType: are written in terms of, spelled by
	// raw value because AppKit's apinotes mark both `nonswift` ("use
	// PasteboardType.fileURL") — the same reason FileBrowserAcceptDrop.swift
	// spells NSFilenamesPboardType out.
	//
	// **Not** .fileURL / .URL, which is what the suggestion would give: those are
	// "public.file-url" and "public.url", different types from
	// "NSFilenamesPboardType" and "Apple URL pasteboard type" (checked, not
	// assumed). Substituting them would quietly change which services this
	// browser offers.
	private static let servicesSendTypes: [NSPasteboard.PasteboardType] = [
		NSPasteboard.PasteboardType("NSFilenamesPboardType"),
		NSPasteboard.PasteboardType("Apple URL pasteboard type"),
	]

	// Was +initialize, converted to explicit lazy registration in 8c98956d
	// because a Swift class cannot provide one (rule 20). It must stay at the top
	// of the initializer: the setup three lines down reads
	// kUserDefaultsFoldersOnTopKey, and this is why that key has a value at all.
	@objc class func registerDefaults() {
		_registerDefaultsOnce
	}

	private static let _registerDefaultsOnce: Void = {
		NSApplication.shared.registerServicesMenuSendTypes(FileBrowserViewController.servicesSendTypes, returnTypes: [])

		let finderDefaults = UserDefaults(suiteName: "com.apple.finder")
		UserDefaults.standard.register(defaults: [
			kUserDefaultsFoldersOnTopKey: finderDefaults?.object(forKey: "_FXSortFoldersFirst") ?? false,
		])
	}()

	// NSViewController's two designated initializers, and nothing else.
	// `[FileBrowserViewController new]` — which both the tests and
	// DocumentWindowController.swift:1588 use — reaches commonInit because
	// NSViewController's own -init funnels through -initWithNibName:bundle:.
	// That is an assumption about AppKit rather than something the compiler
	// checks, so it is pinned by
	// test_file_browser_view_controller_registers_its_defaults_from_init: if the
	// funnel ever stopped, +registerDefaults would never run and that test fails.
	//
	// An explicit `init()` was tried first and does not compile — NSViewController
	// has no designated `init()` to override.
	override init(nibName: NSNib.Name?, bundle: Bundle?) {
		super.init(nibName: nibName, bundle: bundle)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		FileBrowserViewController.registerDefaults()

		fileItemObservers = NSMutableDictionary()
		loadingURLs       = NSMutableSet()

		canExpandSymbolicLinksStorage     = UserDefaults.standard.bool(forKey: kUserDefaultsAllowExpandingLinksKey)
		canExpandPackagesStorage          = UserDefaults.standard.bool(forKey: kUserDefaultsAllowExpandingPackagesKey)
		sortDirectoriesBeforeFilesStorage = UserDefaults.standard.bool(forKey: kUserDefaultsFoldersOnTopKey)

		pendingExpandedURLs = NSMutableSet()
		pendingSelectedURLs = NSMutableSet()

		OakObserveUserDefaults(self)
	}

	deinit {
		// The ObjC++ -dealloc, unchanged. A @MainActor class cannot touch its own
		// state from a nonisolated deinit under Swift 6, and an NSViewController is
		// always deallocated on the main thread, so assumeIsolated is the sanctioned
		// way to say so — the same shape FileItemTableCellView uses (rule 26).
		MainActor.assumeIsolated {
			for observer in (fileItemObservers?.allValues ?? []) {
				FileItem.removeObserver(observer)
			}
			fileItemObservers = nil

			if let menuItem = currentLocationMenuItem {
				menuItem.unbind(.title)
				menuItem.unbind(.image)
			}

			if let headerView = fileBrowserViewStorage?.headerView {
				headerView.goBackButton?.unbind(.enabled)
				headerView.goForwardButton?.unbind(.enabled)

				NotificationCenter.default.removeObserver(self, name: NSPopUpButton.willPopUpNotification, object: headerView.folderPopUpButton)
			}
		}
	}

	@objc(userDefaultsDidChange:)
	func userDefaultsDidChange(_ sender: Notification) {
		canExpandSymbolicLinks     = UserDefaults.standard.bool(forKey: kUserDefaultsAllowExpandingLinksKey)
		canExpandPackages          = UserDefaults.standard.bool(forKey: kUserDefaultsAllowExpandingPackagesKey)
		sortDirectoriesBeforeFiles = UserDefaults.standard.bool(forKey: kUserDefaultsFoldersOnTopKey)
	}

	// ==========================================================
	// = The view                                               =
	// ==========================================================

	override func loadView() {
		self.view = fileBrowserView
	}

	private var fileBrowserViewStorage: FileBrowserView?

	@objc var fileBrowserView: FileBrowserView {
		if let existing = fileBrowserViewStorage {
			return existing
		}

		let view = FileBrowserView(frame: NSZeroRect)
		fileBrowserViewStorage = view

		let locationMenuItem = NSMenuItem(title: "", action: #selector(takeURLFrom(_:)), keyEquivalent: "")
		locationMenuItem.target = self
		locationMenuItem.bind(.title, to: self, withKeyPath: "fileItem.displayName", options: nil)
		locationMenuItem.bind(.image, to: self, withKeyPath: "fileReference.image", options: nil)
		currentLocationMenuItem = locationMenuItem

		let outlineView = view.outlineView!
		outlineView.dataSource   = self
		outlineView.delegate     = self
		outlineView.target       = self
		outlineView.action       = #selector(didSingleClickOutlineView(_:))
		outlineView.doubleAction = #selector(didDoubleClickOutlineView(_:))

		outlineView.menu = NSMenu()
		outlineView.menu?.delegate = self

		let headerView = view.headerView!
		headerView.goBackButton?.target    = self
		headerView.goBackButton?.action    = #selector(goBack(_:))
		headerView.goBackButton?.isEnabled = false

		headerView.goForwardButton?.target    = self
		headerView.goForwardButton?.action    = #selector(goForward(_:))
		headerView.goForwardButton?.isEnabled = false

		headerView.goBackButton?.bind(.enabled, to: self, withKeyPath: "canGoBack", options: nil)
		headerView.goForwardButton?.bind(.enabled, to: self, withKeyPath: "canGoForward", options: nil)

		if let folderPopUpMenu = headerView.folderPopUpButton?.menu {
			folderPopUpMenu.removeAllItems()
			folderPopUpMenu.addItem(locationMenuItem)
			headerView.folderPopUpButton?.select(locationMenuItem)
		}

		NotificationCenter.default.addObserver(self, selector: #selector(folderPopUpButtonWillPopUp(_:)), name: NSPopUpButton.willPopUpNotification, object: headerView.folderPopUpButton)

		let actionsView = view.actionsView!

		// createButton and searchButton get no target: they go up the responder
		// chain to DocumentWindowController, exactly as in the ObjC++. Spelled with
		// NSSelectorFromString because this class does not implement them and
		// #selector would not compile.
		actionsView.createButton?.action    = NSSelectorFromString("newDocumentInDirectory:")
		actionsView.reloadButton?.target    = self
		actionsView.reloadButton?.action    = #selector(reload(_:))
		actionsView.searchButton?.action    = NSSelectorFromString("orderFrontFindPanelForFileBrowser:")
		actionsView.favoritesButton?.target = self
		actionsView.favoritesButton?.action = #selector(goToFavorites(_:))
		actionsView.scmButton?.target       = self
		actionsView.scmButton?.action       = #selector(goToSCMDataSource(_:))

		actionsView.actionsPopUpButton?.menu?.delegate = self

		return view
	}

	@objc(toggleShowInvisibles:)
	func toggleShowInvisibles(_ sender: Any?) {
		showExcludedItems = !showExcludedItems
	}

	// ==========================================================
	// = Location                                               =
	// ==========================================================

	// `go(to:)`, not `goToURL(_:)`. The importer trims the trailing URL off this
	// selector (rule 28), so that is the name the peeled sections were written
	// against — FileBrowserActions.swift calls it three times. Keeping the
	// @objc spelling pinned means the selector the public header promises is
	// unchanged either way.
	@objc(goToURL:)
	func go(to url: URL?) {
		if let url, !(self.URL?.isEqual(url as NSURL) ?? false) {
			addHistoryURL(url as NSURL)
		}
	}

	@objc(goToComputer:) func goToComputer(_ sender: Any?) { go(to: kURLLocationComputer as Foundation.URL) }
	@objc(goToHome:)     func goToHome(_ sender: Any?)     { go(to: Foundation.URL(fileURLWithPath: NSHomeDirectory())) }

	@objc(goToDesktop:)
	func goToDesktop(_ sender: Any?) {
		go(to: try? FileManager.default.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
	}

	@objc(goToFavorites:)
	func goToFavorites(_ sender: Any?) {
		if !(self.URL?.isEqual(kURLLocationFavorites) ?? false) {
			go(to: kURLLocationFavorites as Foundation.URL)
		} else if canGoBack() {
			goBack(sender)
		}
	}

	@objc(goToSCMDataSource:)
	func goToSCMDataSource(_ sender: Any?) {
		guard let url = self.URL else { return NSSound.beep() }

		if url.scheme == "file" {
			let repository = SCMManager.sharedInstance.repository(at: url as Foundation.URL)
			if let repository, repository.enabled {
				let encoded = url.path?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
				go(to: Foundation.URL(string: "scm://localhost\(encoded)/"))
			} else {
				let alert = NSAlert()

				// `?? ""` rather than straight interpolation: localizedName is
				// `String!` and interpolating one prints Optional(…) into the alert
				// (rule 44).
				let name = fileItem?.localizedName ?? ""
				if repository != nil {
					alert.messageText     = "Version control is disabled for “\(name)”."
					alert.informativeText = "For performance reasons TextMate will not monitor version control information for this folder."
				} else {
					alert.messageText     = "Version control is not available for “\(name)”."
					alert.informativeText = "You need to initialize the folder using your favorite version control system before TextMate can show you status."
				}

				alert.addButton(withTitle: "OK")
				if let window = view.window {
					alert.beginSheetModal(for: window, completionHandler: { _ in })
				}
			}
		} else if url.scheme == "scm" {
			if canGoBack() {
				goBack(self)
			} else if let parentURL = fileItem?.parentURL {
				go(to: parentURL as Foundation.URL)
			}
		} else {
			NSSound.beep()
		}
	}

	@objc(goToParentFolder:)
	func goToParentFolder(_ sender: Any?) {
		guard let url = fileItem?.parentURL else { return }
		let cameFromURL = self.URL
		go(to: url as Foundation.URL)
		expandURLs(nil, selectURLs: cameFromURL.map { [ $0 ] })
	}

	@objc(takeURLFrom:)
	func takeURLFrom(_ sender: Any?) {
		go(to: (sender as? NSMenuItem)?.representedObject as? NSURL as Foundation.URL?)
	}

	@objc(folderPopUpButtonWillPopUp:)
	func folderPopUpButtonWillPopUp(_ aNotification: Notification) {
		guard let menu = fileBrowserView.headerView?.folderPopUpButton?.menu else { return }
		while menu.numberOfItems > 1 {
			menu.removeItem(at: menu.numberOfItems - 1)
		}

		var item = fileItem
		while let parentURL = item?.parentURL, let next = FileItem.fileItem(withURL: parentURL) {
			let menuItem = menu.addItem(withTitle: next.localizedName ?? "", action: #selector(takeURLFrom(_:)), keyEquivalent: "")
			menuItem.representedObject = next.resolvedURL
			menuItem.image             = TMFileReference.image(for: next.resolvedURL as Foundation.URL, size: NSMakeSize(16, 16))
			menuItem.target            = self
			item = next
		}

		menu.addItem(NSMenuItem.separator())
		menu.addItem(withTitle: "Other…", action: #selector(orderFrontGoToFolder(_:)), keyEquivalent: "").target = self

		if let root = fileItem, let url = root.URL?.filePathURL {
			menu.addItem(NSMenuItem.separator())
			// takeProjectPathFrom: is DocumentWindowController's, up the responder
			// chain — no target, and NSSelectorFromString for the same reason as the
			// actions view above.
			let projectItem = menu.addItem(withTitle: "Use “\(root.localizedName ?? "")” as Project Folder", action: NSSelectorFromString("takeProjectPathFrom:"), keyEquivalent: "")
			projectItem.representedObject = url.path
		}
	}

	@objc(orderFrontGoToFolder:)
	func orderFrontGoToFolder(_ sender: Any?) {
		let panel = NSOpenPanel()

		panel.canChooseFiles          = false
		panel.canChooseDirectories    = true
		panel.allowsMultipleSelection = false
		panel.directoryURL            = URL?.filePathURL

		guard let window = view.window else { return }
		panel.beginSheetModal(for: window) { result in
			if result == .OK {
				self.go(to: panel.urls.last)
			}
		}
	}

	@objc(selectURL:withParentURL:)
	func selectURL(_ url: NSURL, withParentURL parentURL: NSURL?) {
		var parentURL = parentURL

		let fileReferenceURL = url.fileReferenceURL() as NSURL?
		for i in 0 ..< outlineView.numberOfRows {
			guard let item = outlineView.item(atRow: i) as? FileItem else { continue }
			// -[NSURL isEqual:], never Swift's URL == (rule 33).
			if url.isEqual(item.URL) || (fileReferenceURL?.isEqual(item.fileReferenceURL) ?? false) {
				outlineView.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
				centerSelectionInVisibleArea(self)
				return
			}
		}

		let currentParent = self.URL
		let expandURLs = (self.expandedURLs as NSSet).mutableCopy() as! NSMutableSet

		var childURL = url
		while true {
			var flag: AnyObject?
			if (try? childURL.getResourceValue(&flag, forKey: .isVolumeKey)) != nil, (flag as? NSNumber)?.boolValue == true {
				break
			}

			var potentialParentURL: AnyObject?
			guard (try? childURL.getResourceValue(&potentialParentURL, forKey: .parentDirectoryURLKey)) != nil,
			      let parent = potentialParentURL as? NSURL, !childURL.isEqual(parent) else {
				break
			}

			childURL = parent
			if childURL.isEqual(currentParent) {
				parentURL = currentParent
				break
			}

			if childURL.isEqual(parentURL) {
				break
			}

			expandURLs.add(childURL)
		}

		if childURL.isEqual(parentURL) {
			go(to: parentURL as URL?)
			self.expandURLs(expandURLs.allObjects as? [NSURL], selectURLs: [ url ])
		} else {
			go(to: url.deletingLastPathComponent)
			self.expandURLs(nil, selectURLs: [ url ])
		}
	}

	@objc(deselectAll:)
	func deselectAll(_ sender: Any?) {
		outlineView.deselectAll(sender)
	}

	// ==========================================================
	// = Opening                                                =
	// ==========================================================

	@objc(openItems:animate:)
	func openItems(_ items: [FileItem], animate animateFlag: Bool) {
		var itemsToOpen: [FileItem]              = []
		var itemsToOpenInTextMate: [FileItem]    = []
		var itemsToShowInFinder: [FileItem]      = []
		var itemsToShowInFileBrowser: [FileItem] = []

		let eventType  = NSApp.currentEvent?.type
		let eventFlags = (NSApp.currentEvent?.modifierFlags ?? []).intersection([ .control, .option, .shift, .command ])
		// Verbatim from the ObjC++ (rule 6), including that it tests
		// NSEventTypeOtherMouseUp twice — the second was very likely meant to be
		// rightMouseUp, but that is a behaviour change and this commit is a
		// translation.
		let isMouseEvent            = eventType == .leftMouseUp || eventType == .otherMouseUp || eventType == .otherMouseUp
		let commandKeyDown          = isMouseEvent && eventFlags == .command
		let optionKeyDown           = isMouseEvent && eventFlags == .option
		let treatPackageAsDirectory = UserDefaults.standard.bool(forKey: kUserDefaultsAllowExpandingPackagesKey)

		for item in items {
			if commandKeyDown {
				itemsToShowInFinder.append(item)
			} else if item.isDirectory && (treatPackageAsDirectory || !item.package) || item.linkToDirectory && (treatPackageAsDirectory || !item.linkToPackage) || optionKeyDown && (item.package || item.linkToDirectory) {
				itemsToShowInFileBrowser.append(item)
			} else if item.package || item.linkToPackage || (item.URL?.isFileURL ?? false) && FileBrowserViewControllerSupport.isBinaryURL(item.URL as Foundation.URL?) {
				itemsToOpen.append(item)
			} else {
				itemsToOpenInTextMate.append(item)
			}
		}

		if let first = itemsToShowInFileBrowser.first {
			return go(to: first.resolvedURL as Foundation.URL)
		}

		if animateFlag && !UserDefaults.standard.bool(forKey: kUserDefaultsFileBrowserOpenAnimationDisabled) {
			for group in [ itemsToOpen, itemsToOpenInTextMate ] {
				for item in group {
					guard let url = item.URL else { continue }
					OakZoomingIcon.zoom(TMFileReference.image(for: url as Foundation.URL, size: NSMakeSize(48, 48)), from: imageRect(of: item))
				}
			}
		}

		if !itemsToShowInFinder.isEmpty {
			NSWorkspace.shared.activateFileViewerSelecting(itemsToShowInFinder.compactMap { $0.URL as Foundation.URL? })
		}

		for item in itemsToOpen {
			if let path = item.resolvedURL.path {
				NSWorkspace.shared.openFile(path)
			}
		}

		if !itemsToOpenInTextMate.isEmpty {
			delegate?.fileBrowser(self, openURLs: itemsToOpenInTextMate.compactMap { $0.URL })
		}
	}

	@objc(didSingleClickOutlineView:)
	func didSingleClickOutlineView(_ sender: Any?) {
		if !NSEvent.modifierFlags.intersection([ .control, .shift, .command ]).isEmpty {
			return
		}

		if UserDefaults.standard.bool(forKey: kUserDefaultsFileBrowserSingleClickToOpenKey) {
			if let item = outlineView.item(atRow: outlineView.clickedRow) as? FileItem,
			   !item.isDirectory, !item.linkToDirectory, !item.package, !item.linkToPackage, !item.isApplication {
				openItems([ item ], animate: false)
			}
		}
	}

	@objc(didDoubleClickOutlineView:)
	func didDoubleClickOutlineView(_ sender: Any?) {
		openItems(selectedItems, animate: true)
	}

	@objc(openWithMenuAction:)
	func openWithMenuAction(_ sender: Any?) {
		if let appURL = (sender as? NSMenuItem)?.representedObject as? NSURL {
			openWithMenuDelegate?.openDocumentURLs(previewableItems.map { $0.resolvedURL as Foundation.URL }, withApplicationURL: appURL as Foundation.URL)
		}
	}

	// ==========================================================
	// = New file / new folder                                  =
	// ==========================================================

	@objc(newFile:)
	func newFile(_ sender: Any?) -> NSURL? {
		guard let directoryURL = directoryURLForNewItems else { return nil }

		var pathExtension = "txt"
		if let ext = FileBrowserViewControllerSupport.pathExtensionForNewFile(inDirectoryURL: directoryURL) {
			pathExtension = ext
		}

		let newFileURL = directoryURL.appendingPathComponent("untitled", isDirectory: false).appendingPathExtension(pathExtension)
		let urls = performOperation(.newFile, sourceURLs: nil, destinationURLs: [ newFileURL as NSURL ], unique: true, select: true)
		editNewItem(urls)
		return urls?.first
	}

	@objc(newFolder:)
	func newFolder(_ sender: Any?) -> NSURL? {
		guard let directoryURL = directoryURLForNewItems else { return nil }

		let newFolderURL = directoryURL.appendingPathComponent("untitled folder", isDirectory: true)
		let urls = performOperation(.newFolder, sourceURLs: nil, destinationURLs: [ newFolderURL as NSURL ], unique: true, select: true)
		editNewItem(urls)
		return urls?.first
	}

	// The tail the two share verbatim in the ObjC++: if the operation produced
	// exactly one item and it is the one now selected, scroll to it and open the
	// field editor so the name can be typed over.
	private func editNewItem(_ urls: [NSURL]?) {
		guard let urls, urls.count == 1, outlineView.numberOfSelectedRows == 1 else { return }
		guard let newItem = outlineView.item(atRow: outlineView.selectedRow) as? FileItem else { return }
		if newItem.URL?.isEqual(urls.first) ?? false {
			outlineView.scrollRowToVisible(outlineView.selectedRow)
			outlineView.editColumn(0, row: outlineView.selectedRow, with: nil, select: true)
		}
	}

	// ==========================================================
	// = NSRestorableState                                      =
	// ==========================================================

	override class var restorableStateKeyPaths: [String] {
		return [ "showExcludedItems" ]
	}

	override func restoreState(with state: NSCoder) {
		super.restoreState(with: state)

		guard let newHistory = state.decodeObject(forKey: "history") as? [[String: Any]], !newHistory.isEmpty else { return }

		historyStorage = newHistory
		historyIndex   = min(max(state.decodeInteger(forKey: "historyIndex"), 0), newHistory.count)

		let expandedURLs = state.decodeObject(forKey: "expandedURLs") as? [NSURL]
		let selectedURLs = state.decodeObject(forKey: "selectedURLs") as? [NSURL]
		expandURLs(expandedURLs, selectURLs: selectedURLs)
	}

	override func encodeRestorableState(with state: NSCoder) {
		super.encodeRestorableState(with: state)

		var history: [[String: Any]] = []
		let from = historyStorage.count > 5 ? historyStorage.count - 5 : 0
		for i in from ..< historyStorage.count {
			let record = historyStorage[i]
			let scrollOffset = i == historyIndexStorage ? NSNumber(value: Double(outlineView.visibleRect.minY)) : record["scrollOffset"] as? NSNumber
			if let scrollOffset, scrollOffset.doubleValue > 0 {
				history.append([ "url": record["url"] as Any, "scrollOffset": scrollOffset ])
			} else {
				history.append([ "url": record["url"] as Any ])
			}
		}

		state.encode(history, forKey: "history")
		state.encode(historyIndexStorage - from, forKey: "historyIndex")
		state.encode(Array(self.selectedURLs), forKey: "selectedURLs")
		state.encode(Array(self.expandedURLs), forKey: "expandedURLs")
	}

	// ==========================================================
	// = Public API                                             =
	// ==========================================================

	@objc var sessionState: Any? {
		let coder = NSKeyedArchiver(requiringSecureCoding: false)
		encodeRestorableState(with: coder)
		coder.finishEncoding()
		return coder.encodedData
	}

	@objc(setupViewWithState:)
	func setupView(withState state: Any?) {
		if let data = state as? Data {
			if let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
				coder.requiresSecureCoding = false
				restoreState(with: coder)
			}
		} else if let fileBrowserState = state as? [String: Any] {
			showExcludedItems = (fileBrowserState["showHidden"] as? NSNumber)?.boolValue ?? false

			var newHistory: [[String: Any]] = []
			for entry in (fileBrowserState["history"] as? [[String: Any]]) ?? [] {
				if let urlString = entry["url"] as? String, let url = NSURL(string: urlString) {
					newHistory.append([ "url": url ])
				}
			}

			guard !newHistory.isEmpty else { return }

			historyStorage = newHistory
			let index = (fileBrowserState["historyIndex"] as? NSNumber)?.intValue ?? 0
			historyIndex = min(max(index, 0), newHistory.count)

			let expandedURLs = ((fileBrowserState["expanded"] as? [String]) ?? []).compactMap { NSURL(string: $0) }
			let selectedURLs = ((fileBrowserState["selection"] as? [String]) ?? []).compactMap { NSURL(string: $0) }

			expandURLs(expandedURLs, selectURLs: selectedURLs)
		}
	}

	// ==========================================================
	// = Swipe                                                  =
	// ==========================================================

	override func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
		return axis == .horizontal
	}

	override func scrollWheel(with anEvent: NSEvent) {
		if !NSEvent.isSwipeTrackingFromScrollEventsEnabled || anEvent.phase == [] || abs(anEvent.scrollingDeltaX) <= abs(anEvent.scrollingDeltaY) {
			return
		}

		anEvent.trackSwipeEvent(options: [], dampenAmountThresholdMin: (canGoForward() ? -1 : 0), max: (canGoBack() ? +1 : 0)) { (gestureAmount: CGFloat, phase: Int, isComplete: Bool, stop: UnsafeMutablePointer<ObjCBool>) in
			if phase == Int(NSEvent.Phase.began.rawValue) {
				// Setup animation overlay layers
			}

			// Update animation overlay to match gestureAmount

			if phase == Int(NSEvent.Phase.ended.rawValue) {
				if gestureAmount > 0 && self.canGoBack() {
					self.goBack(self)
				} else if gestureAmount < 0 && self.canGoForward() {
					self.goForward(self)
				}
			}

			if isComplete {
				// Tear down animation overlay here
			}
		}
	}

	// ==========================================================
	// = From FileBrowserView                                   =
	// ==========================================================
	//
	// Four settings, each with a setter that walks the tree and reloads what the
	// change affects. These are the accessors a Swift extension could not supply,
	// which is why they were the last ordinary methods stuck in the .mm.

	@objc var canExpandSymbolicLinks: Bool {
		get { return canExpandSymbolicLinksStorage }
		set {
			guard canExpandSymbolicLinksStorage != newValue else { return }
			canExpandSymbolicLinksStorage = newValue
			guard let root = fileItem else { return }

			var stack = (root.arrangedChildren as? [FileItem]) ?? []
			while let item = stack.first {
				stack.removeFirst()
				if item.linkToDirectory && (canExpandPackagesStorage || !item.linkToPackage) {
					outlineView.reloadItem(item, reloadChildren: true)
				}
				if outlineView.isExpandable(item), let children = item.arrangedChildren as? [FileItem] {
					stack.append(contentsOf: children)
				}
			}
		}
	}
	private var canExpandSymbolicLinksStorage = false

	@objc var canExpandPackages: Bool {
		get { return canExpandPackagesStorage }
		set {
			guard canExpandPackagesStorage != newValue else { return }
			canExpandPackagesStorage = newValue
			guard let root = fileItem else { return }

			var stack = (root.arrangedChildren as? [FileItem]) ?? []
			while let item = stack.first {
				stack.removeFirst()
				if item.isDirectory && item.package {
					outlineView.reloadItem(item, reloadChildren: true)
				}
				if outlineView.isExpandable(item), let children = item.arrangedChildren as? [FileItem] {
					stack.append(contentsOf: children)
				}
			}
		}
	}
	private var canExpandPackagesStorage = false

	@objc var sortDirectoriesBeforeFiles: Bool {
		get { return sortDirectoriesBeforeFilesStorage }
		set {
			guard sortDirectoriesBeforeFilesStorage != newValue else { return }
			sortDirectoriesBeforeFilesStorage = newValue
			rearrangeWholeTree()
		}
	}
	private var sortDirectoriesBeforeFilesStorage = false

	// `dynamic`: +restorableStateKeyPaths names this, and NSResponder observes it
	// to know when to invalidate the restorable state.
	@objc dynamic var showExcludedItems: Bool {
		get { return showExcludedItemsStorage }
		set {
			guard showExcludedItemsStorage != newValue else { return }
			showExcludedItemsStorage = newValue
			rearrangeWholeTree()
		}
	}
	private var showExcludedItemsStorage = false

	// -setSortDirectoriesBeforeFiles: and -setShowExcludedItems: had the same
	// five-line body in the ObjC++; it is one function here.
	private func rearrangeWholeTree() {
		guard let root = fileItem else { return }

		var stack: [FileItem] = [ root ]
		while let item = stack.first {
			stack.removeFirst()
			rearrangeChildren(inParent: item)
			if item === root || outlineView.isItemExpanded(item), let children = item.arrangedChildren as? [FileItem] {
				stack.append(contentsOf: children)
			}
		}
	}

	// ==========================================================
	// = Arranging children                                     =
	// ==========================================================

	// A method returning an implicitly-unwrapped Comparator, not a property, and
	// both halves of that match how `- (NSComparator)itemComparator` imported:
	// FileBrowserDiskOperations.swift:535 writes
	// `guard let compare = itemComparator()`.
	@objc func itemComparator() -> Comparator! {
		let sortDescriptors = [
			NSSortDescriptor(key: "localizedName", ascending: true, selector: #selector(NSString.localizedCompare(_:))),
			NSSortDescriptor(key: "URL.URLByDeletingLastPathComponent.lastPathComponent", ascending: true, selector: #selector(NSString.localizedCompare(_:))),
		]

		return { [weak self] lhs, rhs in
			guard let self, let lhs = lhs as? FileItem, let rhs = rhs as? FileItem else { return .orderedSame }

			if self.sortDirectoriesBeforeFilesStorage {
				if (lhs.isDirectory || lhs.linkToDirectory) && !(rhs.isDirectory || rhs.linkToDirectory) {
					return .orderedAscending
				} else if (rhs.isDirectory || rhs.linkToDirectory) && !(lhs.isDirectory || lhs.linkToDirectory) {
					return .orderedDescending
				}
			}

			for sortDescriptor in sortDescriptors {
				let order = sortDescriptor.compare(lhs, to: rhs)
				if order != .orderedSame {
					return order
				}
			}

			return .orderedSame
		}
	}

	@objc(itemPredicateForChildrenInParent:)
	func itemPredicateForChildren(inParent parentOrNil: FileItem?) -> NSPredicate {
		if showExcludedItemsStorage {
			return NSPredicate(value: true)
		}
		return FileBrowserViewControllerSupport.itemPredicate(forDirectoryURL: (parentOrNil ?? fileItem)?.URL as Foundation.URL?)
	}

	@objc(arrangeChildren:inParent:)
	func arrangeChildren(_ children: [FileItem]?, inParent parentOrNil: FileItem?) -> [FileItem] {
		let filtered = ((children ?? []) as NSArray).filtered(using: itemPredicateForChildren(inParent: parentOrNil))
		return (filtered as NSArray).sortedArray(comparator: itemComparator()!) as? [FileItem] ?? []
	}

	@objc(rearrangeChildrenInParent:)
	func rearrangeChildren(inParent item: FileItem) {
		let existingChildren = item.arrangedChildren
		let children = item.children ?? []

		if let existingChildren, existingChildren.count * children.count < 250000 {
			let newArrangedChildren = arrangeChildren(children, inParent: item)
			let parentOrNil: FileItem? = item !== fileItem ? item : nil

			// ================
			// = Remove Items =
			// ================

			var indexesToRemove = IndexSet()
			for i in 0 ..< existingChildren.count {
				if let child = existingChildren[i] as? FileItem, !newArrangedChildren.contains(where: { $0 === child }) {
					indexesToRemove.insert(i)
				}
			}

			if !indexesToRemove.isEmpty {
				let wasFirstResponderInOutlineView = firstResponderIsInOutlineView()

				existingChildren.removeObjects(at: indexesToRemove)
				outlineView.removeItems(at: indexesToRemove, inParent: parentOrNil, withAnimation: [ .effectFade, .slideUp ])

				if wasFirstResponderInOutlineView && !firstResponderIsInOutlineView() {
					outlineView.window?.makeFirstResponder(outlineView)
				}
			}

			// =======================
			// = Move Items (rename) =
			// =======================

			let compare = itemComparator()!

			var alreadySorted = true
			var i = 1
			while alreadySorted && i < existingChildren.count {
				alreadySorted = compare(existingChildren[i-1], existingChildren[i]) != .orderedDescending
				i += 1
			}

			if !alreadySorted {
				let lcs = longestCommonSubsequence(existingChildren as? [FileItem] ?? [], newArrangedChildren)

				// (isInLCS, item), the ObjC++'s std::vector<std::pair<BOOL, FileItem*>>.
				var v: [(inLCS: Bool, item: FileItem)] = []
				for i in 0 ..< existingChildren.count {
					if let child = existingChildren[i] as? FileItem {
						v.append((lcs.contains(i), child))
					}
				}

				var i = 0
				while i < v.count {
					if v[i].inLCS {
						i += 1
					} else {
						let child = v[i].item

						v.remove(at: i)
						var newIndex = 0
						while newIndex < v.count {
							if v[newIndex].inLCS && compare(child, v[newIndex].item) == .orderedAscending {
								break
							}
							newIndex += 1
						}
						v.insert((true, child), at: newIndex)

						existingChildren.removeObject(at: i)
						existingChildren.insert(child, at: newIndex)
						outlineView.moveItem(at: i, inParent: parentOrNil, to: newIndex, inParent: parentOrNil)
					}
				}
			}

			// ================
			// = Insert Items =
			// ================

			var insertionIndexes = IndexSet()
			for i in 0 ..< newArrangedChildren.count {
				let child = newArrangedChildren[i]
				if !existingChildren.contains(where: { ($0 as AnyObject) === child }) {
					insertionIndexes.insert(i)
				}
			}

			if !insertionIndexes.isEmpty {
				existingChildren.insert(insertionIndexes.map { newArrangedChildren[$0] }, at: insertionIndexes)
				outlineView.insertItems(at: insertionIndexes, inParent: parentOrNil, withAnimation: [ .effectFade, .slideUp ])
			}
		} else {
			item.arrangedChildren = NSMutableArray(array: arrangeChildren(children, inParent: item))
			outlineView.reloadItem(item !== fileItem ? item : nil, reloadChildren: true)

			if item === fileItem {
				outlineView.needsDisplay = true
			}
		}

		updateDisambiguationSuffix(inParent: item)
	}

	private func firstResponderIsInOutlineView() -> Bool {
		guard let responder = outlineView.window?.firstResponder as? NSView else { return false }
		return responder.isDescendant(of: outlineView)
	}

	// ==========================================================
	// = Disambiguation suffixes                                =
	// ==========================================================

	@objc(disambiguationSuffixForURL:numberOfParents:)
	func disambiguationSuffix(forURL url: NSURL, numberOfParents: Int) -> String? {
		var url = url
		var parentNames: [String] = []
		for _ in 0 ..< numberOfParents {
			var flag: AnyObject?
			if (try? url.getResourceValue(&flag, forKey: .isVolumeKey)) != nil, (flag as? NSNumber)?.boolValue == true {
				return nil
			}

			var parentURL: AnyObject?
			guard (try? url.getResourceValue(&parentURL, forKey: .parentDirectoryURLKey)) != nil,
			      let parent = parentURL as? NSURL, !url.isEqual(parent) else {
				return nil
			}

			var parentName: AnyObject?
			guard (try? parent.getResourceValue(&parentName, forKey: .localizedNameKey)) != nil,
			      let name = parentName as? String else {
				return nil
			}

			parentNames.append(name)
			url = parent
		}
		return parentNames.reversed().joined(separator: "/")
	}

	@objc(updateDisambiguationSuffixInParent:)
	func updateDisambiguationSuffix(inParent item: FileItem) {
		var children = ((item.arrangedChildren as? [FileItem]) ?? []).filter { $0.URL?.isFileURL ?? false }
		for child in children {
			child.disambiguationSuffix = nil
		}

		var showNumberOfParents = 1
		while !children.isEmpty {
			let countOfConflicts = NSCountedSet(array: children.map { $0.displayName })
			var conflictedChildren: [FileItem] = []
			for child in children {
				if countOfConflicts.count(for: child.displayName) == 1 {
					continue
				}

				if let url = child.URL, let newSuffix = disambiguationSuffix(forURL: url, numberOfParents: showNumberOfParents) {
					child.disambiguationSuffix = " — " + newSuffix
					conflictedChildren.append(child)
				}
			}
			children = conflictedChildren
			showNumberOfParents += 1
		}
	}

	// ==========================================================
	// = The tree root                                          =
	// ==========================================================

	private func setFileItemStorage(_ item: FileItem?) {
		if fileItemStorage != nil {
			// Remove visible but non-selected/expanded items from pending
			// selection/expansion. This is the *merge*, and the one place that
			// deliberately reads the computed accessors rather than the pending sets.
			pendingExpandedURLs = NSMutableSet(set: expandedURLs)
			pendingSelectedURLs = NSMutableSet(set: selectedURLs)

			for observer in (fileItemObservers?.allValues ?? []) {
				FileItem.removeObserver(observer)
			}
			fileItemObservers = NSMutableDictionary()
		}

		fileItemStorage = item

		if let url = item?.URL, url.isFileURL {
			fileReference = TMFileReference(url: url as Foundation.URL)
		} else {
			var image: NSImage?
			if item?.URL?.scheme == "scm" {
				let query = item?.URL?.query
				if query?.hasSuffix("unstaged") == true || query?.hasSuffix("untracked") == true {
					image = NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericFolderIcon)))
				} else {
					image = NSImage(named: "SCMTemplate", inSameBundleAsClass: NSClassFromString("OakFileBrowser"))
				}
			} else if item?.URL?.scheme == "computer" {
				image = NSImage(named: NSImage.computerName)
			} else {
				image = NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericFolderIcon)))
			}

			let copied = image?.copy() as? NSImage
			copied?.size = NSMakeSize(16, 16)
			fileReference = copied.map { TMFileReference(image: $0) }
		}

		outlineView.reloadItem(nil, reloadChildren: true)
		outlineView.deselectAll(self)
		outlineView.scrollRowToVisible(0)

		loadChildren(for: item, expandChildren: false)

		invalidateRestorableState()
	}

	@objc(reload:)
	func reload(_ sender: Any?) {
		var stack: [FileItem] = fileItem.map { [ $0 ] } ?? []
		while let item = stack.first {
			stack.removeFirst()
			guard let children = item.arrangedChildren as? [FileItem] else { continue }
			FSEventsManager.sharedInstance.reloadDirectory(at: item.resolvedURL as Foundation.URL)
			stack.append(contentsOf: children)
		}
	}

	// ==========================================================
	// = Selection                                              =
	// ==========================================================

	@objc var selectedItems: [FileItem] {
		let indexSet: IndexSet

		let clickedRow = outlineView.clickedRow
		if 0 <= clickedRow && clickedRow < outlineView.numberOfRows && !outlineView.selectedRowIndexes.contains(clickedRow) {
			indexSet = IndexSet(integer: clickedRow)
		} else {
			indexSet = outlineView.selectedRowIndexes
		}

		return indexSet.compactMap { outlineView.item(atRow: $0) as? FileItem }
	}

	@objc var previewableItems: [FileItem] {
		return selectedItems.filter { $0.previewItemURL != nil }
	}

	// Bridged `URL?`, not `NSURL?`, and that is not a free choice: the ObjC++
	// declared this `NSURL*` and so it imported as `URL!`, which is what
	// FileBrowserPasteboard.swift and FileBrowserMenuValidation.swift were
	// written against — the first does `directoryURL.appendingPathComponent(…)`
	// and takes a non-optional back. Declaring it NSURL? here compiles in this
	// file and breaks that call site. Keep the Swift-visible type each peeled
	// section already sees.
	@objc var directoryURLForNewItems: Foundation.URL? {
		var candidates: [Foundation.URL] = []
		for item in selectedItems {
			if item.resolvedURL.isFileURL && outlineView.isItemExpanded(item) {
				candidates.append(item.resolvedURL as Foundation.URL)
			} else if let parentItem = outlineView.parent(forItem: item) as? FileItem {
				if parentItem.resolvedURL.isFileURL {
					candidates.append(parentItem.resolvedURL as Foundation.URL)
				}
			}
		}
		return candidates.last ?? fileItem?.URL?.filePathURL
	}

	@objc(centerSelectionInVisibleArea:)
	override func centerSelectionInVisibleArea(_ sender: Any?) {
		guard outlineView.numberOfSelectedRows != 0, let row = outlineView.selectedRowIndexes.first else { return }

		let rowRect     = outlineView.rect(ofRow: row)
		let visibleRect = outlineView.visibleRect
		if rowRect.minY < visibleRect.minY || rowRect.maxY > visibleRect.maxY {
			outlineView.scroll(NSMakePoint(rowRect.minX, (rowRect.midY - visibleRect.height / 2).rounded()))
		}
	}

	// **These two are the merged accessors, and they are not the pending sets**
	// (rule 46). Each starts from what is still pending and then corrects it
	// against every row the outline view currently has: a row that is selected or
	// expanded goes in, one that is not comes out. The pending set is what has not
	// been reached yet; this is the whole picture.
	//
	// The ObjC++ returned `[res copy]` and its own callers reached past that for
	// the ivars. Here the two are simply different declarations, and only three
	// callers want this one: -encodeRestorableStateWithCoder:,
	// -selectURL:withParentURL: and the merge in -setFileItem:.
	@objc var selectedURLs: Set<NSURL> {
		var res = (pendingSelectedURLs as? Set<NSURL>) ?? []
		let selectedIndexes = outlineView.selectedRowIndexes
		for i in 0 ..< outlineView.numberOfRows {
			guard let item = outlineView.item(atRow: i) as? FileItem, let url = item.URL else { continue }
			if selectedIndexes.contains(i) {
				res.insert(url)
			} else {
				res.remove(url)
			}
		}
		return res
	}

	@objc var expandedURLs: Set<NSURL> {
		var res = (pendingExpandedURLs as? Set<NSURL>) ?? []
		for i in 0 ..< outlineView.numberOfRows {
			guard let item = outlineView.item(atRow: i) as? FileItem, let url = item.URL else { continue }
			if outlineView.isItemExpanded(item) && url.scheme != "scm" {
				res.insert(url)
			} else {
				res.remove(url)
			}
		}
		return res
	}

	// ==========================================================
	// = Services                                               =
	// ==========================================================

	override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
		if returnType == nil, let sendType, FileBrowserViewController.servicesSendTypes.contains(sendType) {
			return self
		}
		return nil
	}

	@objc(writeSelectionToPasteboard:types:)
	func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
		let urls = previewableItems.compactMap { $0.URL }
		if urls.isEmpty {
			return false
		}

		pboard.clearContents()
		return pboard.writeObjects(urls)
	}

	// ==========================================================
	// = Undo/Redo                                              =
	// ==========================================================

	override var undoManager: UndoManager? {
		if fileBrowserUndoManager == nil {
			fileBrowserUndoManager = UndoManager()
		}
		return fileBrowserUndoManager
	}

	@objc var activeUndoManager: UndoManager? {
		if let firstResponder = view.window?.firstResponder as? NSView, firstResponder.isDescendant(of: view) {
			return firstResponder.undoManager
		}
		return undoManager
	}

	@objc(undo:) func undo(_ sender: Any?) { activeUndoManager?.undo() }
	@objc(redo:) func redo(_ sender: Any?) { activeUndoManager?.redo() }
}

// The longest common subsequence of two item lists, as an IndexSet over the
// first — the file-static MutableLongestCommonSubsequence() from the .mm, which
// is what tells -rearrangeChildrenInParent: which rows merely moved.
//
// **The stride is fixed here, and that is a behaviour change worth reading
// twice.** The C++ allocated `width * height` (with width = lhs.count+1,
// height = rhs.count+1) and then indexed `matrix[width*i + j]` for j up to
// rhs.count. The stride for a j-major row is `height`, not `width`, so the
// moment the two lists were different lengths it addressed past the end of the
// buffer — lhs of 3 and rhs of 1 reaches index 13 of an 8-element array. It went
// unnoticed because the case that reaches this code is a rename, where the two
// lists are usually the same length and width == height makes the arithmetic
// accidentally correct.
//
// It cannot be carried across: a Swift array traps instead of reading someone
// else's memory. So this uses the correct stride, which is identical to the C++
// wherever the C++ was in bounds.
private func longestCommonSubsequence(_ lhs: [FileItem], _ rhs: [FileItem]) -> IndexSet {
	let height = rhs.count + 1
	var matrix = [Int](repeating: 0, count: (lhs.count + 1) * height)

	for i in stride(from: lhs.count, through: 0, by: -1) {
		for j in stride(from: rhs.count, through: 0, by: -1) {
			if i == lhs.count || j == rhs.count {
				matrix[height*i + j] = 0
			} else if lhs[i].isEqual(rhs[j]) {
				matrix[height*i + j] = matrix[height*(i+1) + j+1] + 1
			} else {
				matrix[height*i + j] = max(matrix[height*(i+1) + j], matrix[height*i + j+1])
			}
		}
	}

	var res = IndexSet()
	var i = 0, j = 0
	while i < lhs.count && j < rhs.count {
		if lhs[i].isEqual(rhs[j]) {
			res.insert(i)
			i += 1
			j += 1
		} else if matrix[height*i + j+1] < matrix[height*(i+1) + j] {
			i += 1
		} else {
			j += 1
		}
	}
	return res
}
