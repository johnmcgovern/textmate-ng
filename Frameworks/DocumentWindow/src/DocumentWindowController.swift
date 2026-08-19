// The project window: tabs, file browser, HTML output, session save/restore.
//
// Ported from DocumentWindowController.mm (2573 lines) in Phase 4. The class is
// still declared in DocumentWindowController.h by hand — the pattern Find.h and
// TMFileReference.h established — because that header carries
// -performBundleItem:(bundles::item_ptr), which no generated header could.
//
// The C++ lives in two places and nowhere else:
//
//  * DocumentWindowSupport.mm holds a category with the five selectors whose
//    signatures are C++ and cannot move, plus the shims for the APIs whose
//    *blocks* carry C++ (-loadModalForWindow:, -saveModalForWindow:,
//    OakSavePanel) — see that file's header comment for why each one is there.
//
//  * DWScopeContext holds the SCM and scope-attribute state. It was extracted
//    first, in d7f43ebd, precisely so this class could become Swift: a Swift
//    @objc class cannot hold an scm::info_ptr.
//
// Everything else below is ordinary AppKit.
//
// Two spellings look wrong and are deliberate. -didOpenDocuemntInTextView: is
// misspelled in the original and is reached by -performSelector:, so the typo is
// load-bearing. And -validateMenuItem:'s tab-bar action list names
// `takeNewTabIndexFrom::` with two colons — a selector no method has — which is
// kept because "fixing" it silently changes which items get index-set
// validation; see the note there for why it happens to be harmless.
import AppKit

private let kUserDefaultsAlwaysFindInDocument       = "alwaysFindInDocument"
private let kUserDefaultsDisableFolderStateRestore  = "disableFolderStateRestore"
private let kUserDefaultsHideStatusBarKey           = "hideStatusBar"
private let kUserDefaultsDisableBundleSuggestionsKey = "disableBundleSuggestions"
private let kUserDefaultsGrammarsToNeverSuggestKey  = "grammarsToNeverSuggest"

private let kObservedKeyPaths = [
	"arrayController.arrangedObjects.path",
	"arrayController.arrangedObjects.displayName",
	"arrayController.arrangedObjects.documentEdited",
	"selectedDocument.path",
	"selectedDocument.displayName",
	"selectedDocument.icon",
	"selectedDocument.onDisk",
	"selectedDocument.documentEdited",
]

// Session saving is suppressed while a restore is in flight. A file static in
// the ObjC++, and still one shared counter rather than per-instance state.
@MainActor private var DisableSessionSavingCount: UInt = 0

// -scheduleSessionBackup: coalesces every window notification into one timer.
@MainActor private var SessionBackupTimer: Timer?

// -applicationDidResignActiveNotification:'s reentrancy guard, which was a
// function-static BOOL. The save it starts is asynchronous, so this stays set
// until the completion handler runs.
@MainActor private var IsSavingOnResignActive = false

@objc(DocumentWindowController)
class DocumentWindowController: NSResponder, NSWindowDelegate, NSTouchBarDelegate, NSMenuItemValidation, @preconcurrency OakTabBarViewDelegate, @preconcurrency OakTabBarViewDataSource, @preconcurrency FileBrowserDelegate, @preconcurrency OakTextViewDelegate, @preconcurrency OakUserDefaultsObserver {

	// OakTextViewDelegate is conformed to here and FindDelegate is not, and the
	// difference is worth stating because it is not the one the plan assumed.
	//
	// The importer drops -variables, whose return type is a std::map, so Swift's
	// view of OakTextViewDelegate is -scopeAttributes alone and this class can
	// satisfy it. It does *not* drop FindDelegate's -selectRange:inDocument:: under
	// SWIFT_OBJC_INTEROP_MODE=objcxx a `text::range_t const&` parameter imports
	// fine, so declaring that conformance here would oblige the Swift to name and
	// compare a C++ type. Both conformances the category needs are declared on it
	// in DocumentWindowSupport.mm, and Find's delegate is set through a shim for
	// the same reason.

	// ==========================================
	// = tracking document controller instances =
	// ==========================================

	private static let _allControllers = NSMutableDictionary()

	@objc class var allControllers: NSMutableDictionary {
		return _allControllers
	}

	@objc class var sortedControllers: [DocumentWindowController] {
		var res: [DocumentWindowController] = []
		for flag in [ false, true ] {
			for window in NSApp.orderedWindows {
				if window.isMiniaturized == flag, window.delegate?.responds(to: #selector(getter: DocumentWindowController.identifier)) == true {
					guard let delegate = window.delegate as? DocumentWindowController, let identifier = delegate.identifier else { continue }
					if let controller = allControllers[identifier] as? DocumentWindowController {
						res.append(controller)
					}
				}
			}
		}
		return res
	}

	@objc(isDisposableDocument:) class func isDisposableDocument(_ doc: OakDocument?) -> Bool {
		guard let doc = doc else { return false }
		return !doc.isDocumentEdited && !doc.isOnDisk && doc.path == nil && doc.isLoaded && doc.isBufferEmpty
	}

	@objc class var sharedProjectStateDB: KVDB {
		let appSupport = (NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)[0] as NSString).appendingPathComponent("TextMate")
		return KVDB.sharedDB(usingFile: "RecentProjects.db", inDirectory: appSupport)
	}

	// ==============
	// = Properties =
	// ==============

	@objc nonisolated(unsafe) var window: NSWindow!

	@objc var identifier: UUID? {
		get { _identifier }
		set {
			guard _identifier != newValue else { return }

			let oldIdentifier = _identifier
			_identifier = newValue
			if let newIdentifier = newValue {
				DocumentWindowController.allControllers[newIdentifier] = self
			}

			if let oldIdentifier = oldIdentifier {
				DocumentWindowController.allControllers.removeObject(forKey: oldIdentifier) // This may release our object
			}
		}
	}
	private var _identifier: UUID?

	@objc var defaultProjectPath: String?

	@objc private(set) var projectPath: String? {
		get { _projectPath }
		set {
			if _projectPath != newValue {
				_projectPath = newValue
				scopeContext.projectPath = _projectPath

				updateExternalAttributes()
				updateWindowTitle()
			}
		}
	}
	private var _projectPath: String?

	@objc var documentPath: String? {
		get { _documentPath }
		set {
			// The context decides whether this is a change worth acting on: it also
			// re-runs when its attribute list is empty, which is how a window that opens
			// with no document picks the attributes up once it has one. That guard used to
			// be the `|| _documentScopeAttributes.empty()` half of the condition here.
			_documentPath = newValue
			scopeContext.setDocumentPath(newValue, fileType: selectedDocument?.fileType)

			updateExternalAttributes()

			if autoRevealFile, selectedDocument?.path != nil, fileBrowserVisible {
				revealFileInProject(self)
			}
		}
	}
	private var _documentPath: String?

	@objc dynamic var documents: [OakDocument] {
		get { _documents }
		set {
			for document in newValue {
				document.keepBackupFile = true
				document.open()

				// Avoid resetting directory when tearing off a tab (unless moved to new project)
				if document.path == nil && (projectPath != nil || document.directory == nil) {
					document.directory = projectPath ?? defaultProjectPath
				}
			}

			for document in _documents {
				document.close()
			}

			_documents = newValue
			if !_documents.isEmpty {
				tabBarView.reloadData()
				if tabBarView.selectedTabIndex == UInt(NSNotFound) {
					tabBarView.selectedTabIndex = UInt(min(_selectedTabIndex, _documents.count - 1))
				}
			}

			let disableTabBarCollapsingKey = UserDefaults.standard.bool(forKey: kUserDefaultsDisableTabBarCollapsingKey)
			titlebarViewController?.isHidden = !disableTabBarCollapsingKey && documents.count <= 1

			updateTouchBarButtons()
			DocumentWindowController.scheduleSessionBackup(self)
		}
	}
	private var _documents: [OakDocument] = []

	@objc dynamic var selectedDocument: OakDocument? {
		get { _selectedDocument }
		set {
			assert(newValue == nil || newValue!.isLoaded)
			if _selectedDocument == newValue {
				documentView.document = _selectedDocument
				return
			}

			OakDocumentController.sharedInstance.didTouchDocument(_selectedDocument)
			OakDocumentController.sharedInstance.didTouchDocument(newValue)

			_selectedDocument = newValue
			if let newDocument = newValue {
				var projectPath = defaultProjectPath ?? fileBrowser?.path ?? (newDocument.path as NSString?)?.deletingLastPathComponent
				if let candidate = projectPath {
					if let userProjectDirectory = DWUserProjectDirectoryForPath(candidate) {
						projectPath = userProjectDirectory
					}
				} else if let urlString = UserDefaults.standard.string(forKey: kUserDefaultsInitialFileBrowserURLKey) {
					if let url = URL(string: urlString) {
						projectPath = url.standardizedFileURL.path
					}
				}

				self.projectPath = projectPath

				documentView.document = _selectedDocument
				DocumentWindowController.scheduleSessionBackup(self)
			} else {
				self.projectPath = nil
			}
		}
	}
	private var _selectedDocument: OakDocument?

	@objc var selectedTabIndex: UInt {
		get { UInt(_selectedTabIndex) }
		set {
			_selectedTabIndex = Int(newValue)
			tabBarView.selectedTabIndex = newValue
		}
	}
	private var _selectedTabIndex: Int = 0

	@objc var scopeContext: DWScopeContext!
	@objc var titlebarViewController: NSTitlebarAccessoryViewController?
	@objc var layoutView: ProjectLayoutView!
	@objc nonisolated(unsafe) var tabBarView: OakTabBarView!
	@objc var documentView: OakDocumentView!
	@objc nonisolated(unsafe) var textView: OakTextView!
	@objc private(set) var fileBrowser: FileBrowserViewController?

	@objc var disableFileBrowserWindowResize: Bool = false
	@objc var autoRevealFile: Bool = false
	@objc var oldWindowFrame: NSRect = .zero
	@objc var newWindowFrame: NSRect = .zero

	@objc var htmlOutputWindowController: HTMLOutputWindowController?
	@objc var htmlOutputView: OakHTMLOutputView?

	@objc var previousNextTouchBarControl: NSSegmentedControl?

	@objc var bundlesAlreadySuggested: [TMBundle]?

	@objc var arrayController: NSArrayController!

	private var stickyDocumentIdentifiers: Set<UUID>?

	// ========
	// = Init =
	// ========

	override init() {
		super.init()

		self.identifier = UUID()

		tabBarView = OakTabBarView(frame: .zero)
		tabBarView.dataSource = self
		tabBarView.delegate   = self

		documentView = OakDocumentView()
		textView = documentView.textView
		textView.delegate = self

		layoutView = ProjectLayoutView(frame: .zero)
		layoutView.documentView = documentView

		let windowStyle: NSWindow.StyleMask = [ .titled, .closable, .resizable, .miniaturizable ]
		window = NSWindow(contentRect: NSWindow.contentRect(forFrameRect: frameRectForNewWindow(), styleMask: windowStyle), styleMask: windowStyle, backing: .buffered, defer: false)
		window.animationBehavior  = .documentWindow
		window.collectionBehavior = .fullScreenPrimary
		window.delegate           = self
		window.isReleasedWhenClosed = false

		titlebarViewController = NSTitlebarAccessoryViewController()
		tabBarView.setFrameSize(tabBarView.intrinsicContentSize)
		titlebarViewController?.view = tabBarView
		titlebarViewController?.fullScreenMinHeight = NSHeight(tabBarView.frame)
		window.addTitlebarAccessoryViewController(titlebarViewController!)

		OakAddAutoLayoutViewsToSuperview([ layoutView as NSView ], window.contentView)
		window.initialFirstResponder = textView

		window.contentView?.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[view]|", options: [], metrics: nil, views: [ "view": layoutView as NSView ]))
		window.contentView?.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[view]|", options: [], metrics: nil, views: [ "view": layoutView as NSView ]))

		scopeContext = DWScopeContext()
		// The block is retained by the context, so the capture must be weak — its
		// header says so, and a strong capture here is a window that never closes.
		scopeContext.variablesDidChange = { [weak self] in self?.updateWindowTitle() }

		arrayController = NSArrayController()
		arrayController.bind(NSBindingName.content, to: self, withKeyPath: "documents", options: nil)

		for keyPath in kObservedKeyPaths {
			addObserver(self, forKeyPath: keyPath, options: .initial, context: nil)
		}

		OakObserveUserDefaults(self)
		NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActiveNotification(_:)), name: NSApplication.didBecomeActiveNotification, object: NSApp)
		NotificationCenter.default.addObserver(self, selector: #selector(applicationDidResignActiveNotification(_:)), name: NSApplication.didResignActiveNotification, object: NSApp)
		NotificationCenter.default.addObserver(self, selector: #selector(fileBrowserWillDelete(_:)), name: NSNotification.Name.FileBrowserWillDelete, object: nil)

		userDefaultsDidChange(nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		for keyPath in kObservedKeyPaths {
			removeObserver(self, forKeyPath: keyPath)
		}

		NotificationCenter.default.removeObserver(self)

		window?.delegate       = nil
		tabBarView?.dataSource = nil
		tabBarView?.delegate   = nil
		textView?.delegate     = nil

		// When option-clicking to close all windows then
		// messages are sent to our window after windowWillClose:
		_ = window
	}

	// ======================================
	// = Find suitable frame for new window =
	// ======================================

	@objc var windowFrame: NSRect {
		var res = window.frame
		if fileBrowserVisible && !disableFileBrowserWindowResize {
			res.size.width -= fileBrowserWidth
		}
		return res
	}

	@objc var cascadedWindowFrame: NSRect {
		let frameRect   = windowFrame
		let contentRect = NSWindow.contentRect(forFrameRect: frameRect, styleMask: window.styleMask)

		let offset = NSMaxY(frameRect) - NSMaxY(contentRect)
		return NSOffsetRect(frameRect, offset, -offset)
	}

	@objc func frameRectForNewWindow() -> NSRect {
		// A std::map<CGFloat, NSWindow*> keyed by NSMaxY in the ObjC++, so this is an
		// ordered walk and `.begin()` is the *lowest* maxY. A stable sort reproduces
		// it including the tie case: std::map::emplace keeps the first window
		// inserted for an equal key, and a stable sort keeps the first in
		// NSApp.windows order too.
		var ourWindows: [(maxY: CGFloat, window: NSWindow)] = []
		for win in NSApp.windows {
			if win.isVisible, win.isOnActiveSpace, !win.isZoomed, !win.styleMask.contains(.fullScreen), win.delegate is DocumentWindowController {
				ourWindows.append((NSMaxY(win.frame), win))
			}
		}
		ourWindows.sort { $0.maxY < $1.maxY }

		if !ourWindows.isEmpty {
			var r = (ourWindows[0].window.delegate as! DocumentWindowController).cascadedWindowFrame

			let scrRect = NSScreen.main?.visibleFrame ?? .zero
			if NSContainsRect(scrRect, r) {
				return r
			}

			r.origin.x = 61
			r.origin.y = NSMaxY(scrRect) - NSHeight(r)

			var alreadyHasWrappedWindow = false
			for pair in ourWindows {
				if NSEqualPoints(pair.window.frame.origin, r.origin) {
					alreadyHasWrappedWindow = true
				}
			}

			if alreadyHasWrappedWindow {
				if let mainWindow = NSApp.mainWindow, let delegate = mainWindow.delegate as? DocumentWindowController {
					r = delegate.cascadedWindowFrame
				}
			}

			return r
		}

		if let rectStr = UserDefaults.standard.string(forKey: "DocumentControllerWindowFrame") {
			return NSRectFromString(rectStr)
		}

		let r = NSScreen.main?.visibleFrame ?? .zero
		return NSIntegralRect(NSInsetRect(r, NSWidth(r) / 3, NSHeight(r) / 5))
	}

	// =========================

	func windowWillClose(_ notification: Notification) {
		if !window.styleMask.contains(.fullScreen) && !window.isZoomed {
			UserDefaults.standard.set(NSStringFromRect(windowFrame), forKey: "DocumentControllerWindowFrame")
		}

		arrayController.unbind(NSBindingName.content)

		documents          = []
		selectedDocument   = nil
		fileBrowserVisible = false // Make window frame small as we no longer respond to savableWindowFrame
		identifier         = nil   // This removes us from AllControllers and causes a release
	}

	@objc func showWindow(_ sender: Any?) {
		if _documents.isEmpty {
			guard let defaultDocument = OakDocumentController.sharedInstance.untitledDocument() else { return }
			documents = [ defaultDocument ]
			openAndSelectDocument(defaultDocument, activate: true)
		}
		window.makeKeyAndOrderFront(sender)
	}

	@objc func makeTextViewFirstResponder(_ sender: Any?) { window.makeFirstResponder(textView) }
	@objc func close()                                    { window.close() }

	@objc func moveFocus(_ sender: Any?) {
		if window.firstResponder == textView {
			fileBrowserVisible = true
			guard let outlineView = fileBrowser?.outlineView else { return }
			window.makeFirstResponder(outlineView)
			if outlineView.numberOfSelectedRows == 0 {
				for row in 0..<outlineView.numberOfRows {
					if let delegate = outlineView.delegate, delegate.responds(to: #selector(NSOutlineViewDelegate.outlineView(_:isGroupItem:))), let item = outlineView.item(atRow: row), delegate.outlineView?(outlineView, isGroupItem: item) == true {
						continue
					}
					outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
					break
				}
			}
		} else {
			makeTextViewFirstResponder(sender)
		}
	}

	// ==========================
	// = Notification Callbacks =
	// ==========================

	@objc func userDefaultsDidChange(_ notification: Notification?) {
		htmlOutputInWindow             = UserDefaults.standard.string(forKey: kUserDefaultsHTMLOutputPlacementKey) == "window"
		disableFileBrowserWindowResize = UserDefaults.standard.bool(forKey: kUserDefaultsDisableFileBrowserWindowResizeKey)
		autoRevealFile                 = UserDefaults.standard.bool(forKey: kUserDefaultsAutoRevealFileKey)
		documentView.hideStatusBar     = UserDefaults.standard.bool(forKey: kUserDefaultsHideStatusBarKey)

		if layoutView.fileBrowserOnRight != (UserDefaults.standard.string(forKey: kUserDefaultsFileBrowserPlacementKey) == "right") {
			oldWindowFrame = .zero
			newWindowFrame = .zero
			layoutView.fileBrowserOnRight = !layoutView.fileBrowserOnRight
		}

		let disableTabBarCollapsingKey = UserDefaults.standard.bool(forKey: kUserDefaultsDisableTabBarCollapsingKey)
		titlebarViewController?.isHidden = !disableTabBarCollapsingKey && documents.count <= 1
	}

	@objc func applicationDidBecomeActiveNotification(_ notification: Notification) {
		if !_documents.isEmpty {
			textView.perform(#selector(applicationDidBecomeActiveNotification(_:)), with: notification)
		}
	}

	@objc func applicationDidResignActiveNotification(_ notification: Notification) {
		if IsSavingOnResignActive {
			return
		}
		IsSavingOnResignActive = true

		var documentsToSave: [OakDocument] = []
		for doc in _documents {
			if doc.isDocumentEdited, doc.path != nil {
				if DWShouldSaveOnBlur(doc) {
					if doc == selectedDocument {
						textView.updateDocumentMetadata()
					}
					documentsToSave.append(doc)
				}
			}
		}

		saveDocuments(using: documentsToSave.makeIterator()) { [self] _ in
			if !_documents.isEmpty {
				textView.perform(#selector(applicationDidResignActiveNotification(_:)), with: notification)
			}
			IsSavingOnResignActive = false
		}
	}

	// =================
	// = Close Methods =
	// =================

	@objc class func saveAlert(forDocuments someDocuments: [OakDocument]) -> NSAlert {
		let alert = NSAlert()
		alert.alertStyle = .warning
		if someDocuments.count == 1 {
			let document = someDocuments[0]
			alert.messageText = "Do you want to save the changes you made in the document “\(document.displayName ?? "")”?"
			alert.informativeText = "Your changes will be lost if you don’t save them."
			// -addButtons: is an ObjC variadic method and therefore uncallable from
			// Swift. Its whole implementation is this loop over -addButtonWithTitle:.
			for title in [ "Save", "Cancel", "Don’t Save" ] {
				alert.addButton(withTitle: title)
			}
		} else {
			var body = ""
			for document in someDocuments {
				body += "• “\(document.displayName ?? "")”\n"
			}
			alert.messageText = "Do you want to save documents with changes?"
			alert.informativeText = body
			for title in [ "Save All", "Cancel", "Don’t Save" ] {
				alert.addButton(withTitle: title)
			}
		}
		return alert
	}

	@objc func showCloseWarningUI(forDocuments someDocuments: [OakDocument], completionHandler callback: @escaping (Bool) -> Void) {
		if someDocuments.isEmpty {
			return callback(true)
		}

		if someDocuments.count == 1 {
			let doc = someDocuments[0]
			if doc != selectedDocument {
				selectedTabIndex = UInt(documents.firstIndex(of: doc) ?? 0)
				openAndSelectDocument(doc, activate: true)
			}
		}

		let alert = DocumentWindowController.saveAlert(forDocuments: someDocuments)
		alert.beginSheetModal(for: window) { [self] returnCode in
			switch returnCode {
				case .alertFirstButtonReturn: /* "Save" */
					saveDocuments(using: someDocuments.makeIterator()) { result in
						callback(result == .success)
					}

				case .alertSecondButtonReturn: /* "Cancel" */
					callback(false)

				case .alertThirdButtonReturn: /* "Don't Save" */
					callback(true)

				default:
					break
			}
		}
	}

	@objc(closeTabsAtIndexes:askToSaveChanges:createDocumentIfEmpty:activate:)
	func closeTabs(at anIndexSet: IndexSet, askToSaveChanges askToSaveFlag: Bool, createDocumentIfEmpty createIfEmptyFlag: Bool, activate activateFlag: Bool) {
		let documentsToClose = anIndexSet.compactMap { $0 < _documents.count ? _documents[$0] : nil }
		if documentsToClose.isEmpty {
			return
		}

		if askToSaveFlag {
			let documentsToSave = documentsToClose.filter { $0.isDocumentEdited }
			if !documentsToSave.isEmpty {
				showCloseWarningUI(forDocuments: documentsToSave) { [self] canClose in
					if canClose {
						closeTabs(at: anIndexSet, askToSaveChanges: false, createDocumentIfEmpty: createIfEmptyFlag, activate: activateFlag)
					} else {
						let newIndexes = IndexSet(anIndexSet.filter { $0 < _documents.count && !_documents[$0].isDocumentEdited })
						closeTabs(at: newIndexes, askToSaveChanges: true, createDocumentIfEmpty: createIfEmptyFlag, activate: activateFlag)
					}
				}
				return
			}
		}

		let uuids = Set(documentsToClose.map { $0.identifier })
		let selectedUUID = _documents[_selectedTabIndex].identifier

		var newDocuments: [OakDocument] = []
		var newSelectedTabIndex = _selectedTabIndex
		for document in _documents {
			if !uuids.contains(document.identifier) {
				newDocuments.append(document)
			}
			if selectedUUID == document.identifier {
				newSelectedTabIndex = max(newDocuments.count, 1) - 1
			}
		}

		if createIfEmptyFlag && newDocuments.isEmpty {
			if let untitled = OakDocumentController.sharedInstance.untitledDocument() { newDocuments.append(untitled) }
		}

		NSAnimationContext.runAnimationGroup({ [self] context in
			context.allowsImplicitAnimation = true
			documents        = newDocuments
			selectedTabIndex = UInt(newSelectedTabIndex)
		}, completionHandler: {
		})

		if !newDocuments.isEmpty && newDocuments[newSelectedTabIndex].identifier != selectedUUID {
			openAndSelectDocument(newDocuments[newSelectedTabIndex], activate: activateFlag)
		}
	}

	@objc func performClose(_ sender: Any?) {
		tabBarView.performClose(sender)
	}

	@objc func performCloseTab(_ sender: Any?) {
		let index = (sender as? OakTabBarView)?.tag ?? _selectedTabIndex
		if index == NSNotFound || _documents.isEmpty || (_documents.count == 1 && (DocumentWindowController.isDisposableDocument(selectedDocument) || !fileBrowserVisible)) {
			return performCloseWindow(sender)
		}
		closeTabs(at: IndexSet(integer: index), askToSaveChanges: true, createDocumentIfEmpty: true, activate: true)
	}

	@objc func performCloseSplit(_ sender: Any?) {
		assert((sender as AnyObject?) === layoutView.htmlOutputView)
		htmlOutputVisible = false
	}

	@objc func performCloseWindow(_ sender: Any?) {
		window.performClose(self)
	}

	@objc func performCloseAllTabs(_ sender: Any?) {
		let allTabs = IndexSet(_documents.indices.filter { !isDocumentSticky(_documents[$0]) && (!_documents[$0].isDocumentEdited || _documents[$0].path != nil) })
		closeTabs(at: allTabs, askToSaveChanges: true, createDocumentIfEmpty: true, activate: true)
	}

	@objc func performCloseOtherTabsXYZ(_ sender: Any?) {
		var otherTabs = IndexSet(_documents.indices.filter { !isDocumentSticky(_documents[$0]) && (!_documents[$0].isDocumentEdited || _documents[$0].path != nil) })

		let tabIndex = (sender as? OakTabBarView)?.tag ?? _selectedTabIndex
		otherTabs.remove(tabIndex)

		closeTabs(at: otherTabs, askToSaveChanges: true, createDocumentIfEmpty: true, activate: true)
	}

	@objc func performCloseTabsToTheRight(_ sender: Any?) {
		let from = _selectedTabIndex + 1, to = _documents.count
		if from < to {
			closeTabs(at: IndexSet(integersIn: from..<to), askToSaveChanges: true, createDocumentIfEmpty: true, activate: true)
		}
	}

	@objc func performCloseTabsToTheLeft(_ sender: Any?) {
		if _selectedTabIndex > 0 {
			closeTabs(at: IndexSet(integersIn: 0..<_selectedTabIndex), askToSaveChanges: true, createDocumentIfEmpty: true, activate: true)
		}
	}

	@objc func saveProjectState() {
		if treatAsProjectWindow, let projectPath = projectPath {
			DocumentWindowController.sharedProjectStateDB.setValue(sessionInfo(includingUntitledDocuments: false), forKey: projectPath)
		}
	}

	func windowShouldClose(_ sender: NSWindow) -> Bool {
		if !htmlOutputInWindow, let htmlOutputView = htmlOutputView, htmlOutputView.isRunningCommand {
			htmlOutputView.stopLoading(withUserInteraction: true) { didStop in
				if didStop {
					sender.perform(#selector(NSWindow.performClose(_:)), with: self, afterDelay: 0)
				}
			}
			return false
		}

		let documentsToSave = _documents.filter { $0.isDocumentEdited }
		if documentsToSave.isEmpty {
			saveProjectState()
			return true
		}

		showCloseWarningUI(forDocuments: documentsToSave) { [self] canClose in
			if canClose {
				saveProjectState()
				window.close()
			}
		}

		return false
	}

	@objc func fileBrowserWillDelete(_ notification: Notification) {
		guard let path = notification.userInfo?[FileBrowserPathKey] as? String else { return }

		let indexSet = IndexSet(_documents.indices.filter { !_documents[$0].isDocumentEdited && DWIsChildPath(_documents[$0].path, path) })

		closeTabs(at: indexSet, askToSaveChanges: false, createDocumentIfEmpty: true, activate: false)
	}

	@objc func fileBrowserDidDuplicate(_ notification: Notification) {
		guard let urls = notification.userInfo?[FileBrowserURLDictionaryKey] as? [URL: URL] else { return }
		for (url, duplicate) in urls {
			if url.path == selectedDocument?.path {
				openItems([ [ "path": duplicate.path ] ], closingOtherTabs: false, activate: false)
			}
		}
	}

	@objc class func saveSessionAndDetachBackups() {
		let restoresSession = !UserDefaults.standard.bool(forKey: kUserDefaultsDisableSessionRestoreKey)
		_ = DocumentWindowController.saveSession(includingUntitledDocuments: restoresSession)
		for controller in sortedControllers.reversed() {
			controller.saveProjectState()

			// Ensure we do not remove backup files, as they are used to restore untitled documents
			if restoresSession {
				for document in controller.documents {
					let backupPath = document.backupPath
					document.backupPath = nil
					if let backupPath = backupPath, document.path != nil {
						unlink((backupPath as NSString).fileSystemRepresentation)
					}
				}
			}
		}
	}

	@objc var documentsNeedingSaving: [OakDocument]? {
		let restoresSession = !UserDefaults.standard.bool(forKey: kUserDefaultsDisableSessionRestoreKey)

		var res: [OakDocument] = []
		for doc in _documents {
			if doc.isDocumentEdited && (doc.path != nil || !restoresSession) {
				res.append(doc)
			}
		}
		return res.isEmpty ? nil : res
	}

	private class func saveControllers(using iterator: IndexingIterator<[DocumentWindowController]>, completionHandler callback: ((OakDocumentIOResult) -> Void)?) {
		var iterator = iterator
		if let controller = iterator.next() {
			controller.saveDocuments(using: (controller.documentsNeedingSaving ?? []).makeIterator()) { result in
				if result == .success {
					saveControllers(using: iterator, completionHandler: callback)
				} else if let callback = callback {
					callback(result)
				}
			}
		} else if let callback = callback {
			callback(.success)
		}
	}

	@objc(applicationShouldTerminate:)
	class func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		var controllers: [DocumentWindowController] = []
		var documents: [OakDocument] = []
		for controller in sortedControllers {
			if let newDocs = controller.documentsNeedingSaving {
				controllers.append(controller)
				documents.append(contentsOf: newDocs)
			}
		}

		if controllers.isEmpty {
			saveSessionAndDetachBackups()
			return .terminateNow
		} else if controllers.count == 1 {
			let controller = controllers[0]
			controller.showCloseWarningUI(forDocuments: controller.documentsNeedingSaving ?? []) { canClose in
				if canClose {
					saveSessionAndDetachBackups()
				}
				NSApp.reply(toApplicationShouldTerminate: canClose)
			}
		} else {
			switch saveAlert(forDocuments: documents).runModal() {
				case .alertFirstButtonReturn: /* "Save" */
					saveControllers(using: controllers.makeIterator()) { result in
						if result == .success {
							saveSessionAndDetachBackups()
						}
						NSApp.reply(toApplicationShouldTerminate: result == .success)
					}

				case .alertSecondButtonReturn: /* "Cancel" */
					return .terminateCancel

				case .alertThirdButtonReturn: /* "Don't Save" */
					return .terminateNow

				default:
					break
			}
		}
		return .terminateLater
	}

	// =====================
	// = Document Tracking =
	// =====================

	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		let document = selectedDocument
		if keyPath == "selectedDocument.path" || keyPath == "selectedDocument.displayName" {
			documentPath = document?.virtualPath ?? document?.path
			if projectPath == nil {
				projectPath = (document?.path as NSString?)?.deletingLastPathComponent
			}
		}

		if keyPath == "selectedDocument.path" || keyPath == "selectedDocument.displayName" {
			updateWindowTitle()
		}
		if keyPath == "selectedDocument.documentEdited" {
			window.isDocumentEdited = document?.isDocumentEdited ?? false
		}
		if keyPath == "selectedDocument.onDisk" || keyPath == "selectedDocument.path" {
			window.representedFilename = (document?.isOnDisk == true ? document?.path : "") ?? ""
		}
		if keyPath == "selectedDocument.onDisk" || keyPath == "selectedDocument.icon" {
			window.standardWindowButton(.documentIconButton)?.image = document?.isOnDisk == true ? document?.icon : nil
		}

		if let keyPath = keyPath, keyPath.hasSuffix("arrangedObjects.path") || keyPath.hasSuffix("arrangedObjects.displayName") || keyPath.hasSuffix("arrangedObjects.documentEdited") {
			tabBarView.reloadData()
			DocumentWindowController.scheduleSessionBackup(self)
		}
	}

	@objc(isDocumentSticky:) func isDocumentSticky(_ aDocument: OakDocument) -> Bool {
		return stickyDocumentIdentifiers?.contains(aDocument.identifier) ?? false
	}

	@objc(setDocument:sticky:) func setDocument(_ aDocument: OakDocument, sticky stickyFlag: Bool) {
		if stickyFlag {
			if stickyDocumentIdentifiers == nil {
				stickyDocumentIdentifiers = Set()
			}
			stickyDocumentIdentifiers?.insert(aDocument.identifier)
		} else {
			stickyDocumentIdentifiers?.remove(aDocument.identifier)
		}
	}

	// ====================
	// = Create Documents =
	// ====================

	@objc func newDocumentInTab(_ sender: Any?) {
		takeNewTabIndexFrom(IndexSet(integer: _selectedTabIndex + 1) as NSIndexSet)
	}

	@objc func newDocumentInDirectory(_ sender: Any?) {
		guard fileBrowserVisible, let fileBrowser = fileBrowser else { return }

		if let url = fileBrowser.newFile(self), let doc = OakDocumentController.sharedInstance.document(withPath: url.path) {
			insertDocuments([ doc ], at: _selectedTabIndex + 1, selecting: doc, andClosing: disposableDocument.map { [ $0 ] })
			openAndSelectDocument(doc, activate: false)
		}
	}

	@objc func moveDocumentToNewWindow(_ sender: Any?) {
		if _documents.count > 1 {
			takeTabsToTearOffFrom(IndexSet(integer: _selectedTabIndex) as NSIndexSet)
		}
	}

	@objc func mergeAllWindows(_ sender: Any?) {
		var documents = _documents
		for delegate in DocumentWindowController.sortedControllers {
			if delegate !== self && !delegate.window.isMiniaturized {
				documents.append(contentsOf: delegate.documents)
			}
		}

		self.documents = documents

		for delegate in DocumentWindowController.sortedControllers {
			if delegate !== self && !delegate.window.isMiniaturized {
				delegate.window.close()
			}
		}
	}

	@objc var disposableDocument: UUID? {
		if _selectedTabIndex < _documents.count && DocumentWindowController.isDisposableDocument(_documents[_selectedTabIndex]) {
			return _documents[_selectedTabIndex].identifier
		}
		return nil
	}

	// A class method: it touches no instance state, and hoisting it is what lets it
	// be tested without standing up a whole window. The unconditional ++i/++j at the
	// end of the loop is on top of whichever branch already advanced one of them —
	// that reads like a bug, is load-bearing, and is pinned by
	// t_document_window_controller.mm.
	@objc(documents:hasCommonSubsequenceWithDocuments:)
	class func documents(_ lhs: [OakDocument], hasCommonSubsequenceWithDocuments rhs: [OakDocument]) -> Bool {
		var subsequence = Set(lhs.map { $0.identifier })
		subsequence.formIntersection(Set(rhs.map { $0.identifier }))

		var i = 0, j = 0
		while i < lhs.count && j < rhs.count {
			if !subsequence.contains(lhs[i].identifier) {
				i += 1
			} else if !subsequence.contains(rhs[j].identifier) {
				j += 1
			} else if lhs[i].identifier != rhs[j].identifier {
				return false
			}
			i += 1
			j += 1
		}

		return true
	}

	@objc(insertDocuments:atIndex:selecting:andClosing:)
	func insertDocuments(_ documents: [OakDocument], at index: Int, selecting selectDocument: OakDocument?, andClosing closeDocuments: [UUID]?) {
		let newUUIDs = Set(documents.map { $0.identifier })
		var oldUUIDs = Set(self.documents.map { $0.identifier })
		oldUUIDs.subtract(Set(closeDocuments ?? []))

		let shouldReorder = !UserDefaults.standard.bool(forKey: kUserDefaultsDisableTabReorderingKey)
		var newDocuments: [OakDocument] = []
		for i in 0..._documents.count {
			if i == min(index, _documents.count) {
				var didInsert = Set<UUID>()
				for j in 0..<documents.count {
					if !didInsert.contains(documents[j].identifier) && (shouldReorder || !oldUUIDs.contains(documents[j].identifier)) {
						newDocuments.append(documents[j])
						didInsert.insert(documents[j].identifier)
					}
				}
			}

			if i == _documents.count {
				break
			} else if shouldReorder && newUUIDs.contains(_documents[i].identifier) {
				continue
			} else if closeDocuments?.contains(_documents[i].identifier) == true {
				continue
			}

			newDocuments.append(_documents[i])
		}

		NSAnimationContext.runAnimationGroup({ [self] context in
			context.allowsImplicitAnimation = DocumentWindowController.documents(self.documents, hasCommonSubsequenceWithDocuments: newDocuments)
			self.documents = newDocuments
			selectedTabIndex = UInt(selectDocument.flatMap { _documents.firstIndex(of: $0) } ?? NSNotFound)
		}, completionHandler: {
		})
	}

	@objc(openItems:closingOtherTabs:activate:)
	func openItems(_ items: [[String: Any]], closingOtherTabs closeOtherTabsFlag: Bool, activate activateFlag: Bool) {
		var documents: [OakDocument] = []
		for item in items {
			var doc: OakDocument?
			if item["path"] == nil, let identifier = item["identifier"] as? String {
				doc = OakDocumentController.sharedInstance.findDocument(withIdentifier: UUID(uuidString: identifier) ?? UUID())
			}
			if doc == nil, let path = item["path"] as? String {
				doc = OakDocumentController.sharedInstance.document(withPath: path)
			}

			if let doc = doc {
				doc.isRecentTrackingDisabled = true
				if let selectionString = item["selectionString"] as? String {
					doc.selection = selectionString
				}
				documents.append(doc)
			}
		}

		if documents.isEmpty {
			return
		}

		var tabsToClose: [UUID] = []
		if closeOtherTabsFlag {
			for doc in self.documents {
				if !doc.isDocumentEdited && !isDocumentSticky(doc) {
					tabsToClose.append(doc.identifier)
				}
			}
		} else if let uuid = disposableDocument {
			tabsToClose.append(uuid)
		}

		insertDocuments(documents, at: _selectedTabIndex + 1, selecting: documents.last, andClosing: tabsToClose)
		openAndSelectDocument(documents.last!, activate: activateFlag)

		if tabBarView != nil && !UserDefaults.standard.bool(forKey: kUserDefaultsDisableTabAutoCloseKey) {
			let excessTabs = _documents.count - max(tabBarView.countOfVisibleTabs, 8)
			if excessTabs > 0 {
				// A std::multimap<NSInteger, NSUInteger> in the ObjC++: ordered by LRU
				// rank, and duplicate ranks kept in insertion order. A stable sort on the
				// index pairs gives the same walk.
				var ranked: [(rank: Int, index: Int)] = []
				for i in 0..<_documents.count {
					ranked.append((OakDocumentController.sharedInstance.lruRank(for: _documents[i]), i))
				}
				ranked.sort { $0.rank < $1.rank }

				let newUUIDs = Set(documents.map { $0.identifier })

				var indexSet = IndexSet()
				for pair in ranked {
					let doc = _documents[pair.index]
					if !doc.isDocumentEdited && !isDocumentSticky(doc) && doc.isOnDisk && !newUUIDs.contains(doc.identifier) {
						indexSet.insert(pair.index)
					}
					if indexSet.count == excessTabs {
						break
					}
				}

				closeTabs(at: indexSet, askToSaveChanges: false, createDocumentIfEmpty: false, activate: activateFlag)
			}
		}
	}

	// ================
	// = Document I/O =
	// ================

	// Misspelled in the original, and reached by -performSelector:, so the typo is
	// part of the interface rather than a slip to tidy up.
	@objc func didOpenDocuemntInTextView(_ textView: OakTextView) {
		DWPerformDidOpenCallbacks(textView)
	}

	@objc(openAndSelectDocument:activate:)
	func openAndSelectDocument(_ document: OakDocument, activate activateFlag: Bool) {
		DWLoadDocumentModalForWindow(document, window) { [self] result, errorMessage, filterUUID in
			if result == .success {
				let showBundleSuggestions = !UserDefaults.standard.bool(forKey: kUserDefaultsDisableBundleSuggestionsKey)
				if document.fileType == nil && showBundleSuggestions {
					var grammars = document.proposedGrammars() ?? []
					if let excludedGrammars = UserDefaults.standard.stringArray(forKey: kUserDefaultsGrammarsToNeverSuggestKey) {
						grammars = (grammars as NSArray).filtered(using: NSPredicate(format: "NOT (identifier.UUIDString IN %@)", excludedGrammars)) as! [BundleGrammar]
					}
					if let alreadySuggested = bundlesAlreadySuggested {
						grammars = (grammars as NSArray).filtered(using: NSPredicate(format: "NOT (bundle IN %@)", alreadySuggested)) as! [BundleGrammar]
					}

					if !grammars.isEmpty && DWCanReachBundleServer() {
						bundlesAlreadySuggested = (bundlesAlreadySuggested ?? []) + (grammars[0].bundle.map { [ $0 ] } ?? [])

						let installer = SelectGrammarViewController()
						installer.documentDisplayName = (document.path != nil || document.customName != nil) ? document.displayName : nil

						var documentCloseObserver: NSObjectProtocol?
						documentCloseObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.OakDocumentWillClose, object: document, queue: nil) { [weak installer] _ in
							installer?.dismissStrip()
							if let observer = documentCloseObserver {
								NotificationCenter.default.removeObserver(observer)
							}
						}

						installer.showGrammars(grammars, for: documentView) { [self] response, grammar in
							if response == .install, grammar?.bundle?.isInstalled == true {
								for doc in _documents {
									if doc == document || (doc.proposedGrammars() ?? []).contains(where: { $0 == grammar }) {
										doc.fileType = grammar?.fileType
									}
								}
							} else if response == .never {
								let excludedGrammars = UserDefaults.standard.stringArray(forKey: kUserDefaultsGrammarsToNeverSuggestKey) ?? []
								if let uuidString = grammar?.identifier?.uuidString {
									UserDefaults.standard.set(excludedGrammars + [ uuidString ], forKey: kUserDefaultsGrammarsToNeverSuggestKey)
								}
							}

							if let observer = documentCloseObserver {
								NotificationCenter.default.removeObserver(observer)
							}
						}
					}

					document.fileType = DWDefaultFileTypeForDocument(document, projectPath)
				}

				if activateFlag {
					makeTextViewFirstResponder(self)
				}

				// crash_reporter_info_t is RAII, so in the ObjC++ the breadcrumb was live
				// from its declaration to the end of this branch. The wrapper makes that
				// scope explicit — these three statements were the rest of the block.
				DWWithCrashReporterInfo("old selected document ‘\(_selectedDocument?.displayName ?? "nil")’, new selected document ‘\(document.displayName ?? "nil")’") { [self] in
					selectedDocument = document
					perform(#selector(didOpenDocuemntInTextView(_:)), with: documentView.textView, afterDelay: 0)
					document.close()
				}
			} else {
				if let filterUUID = filterUUID {
					DWShowCommandError(errorMessage, filterUUID, nil)
				}

				// Close the tab that failed to open
				if let i = _documents.firstIndex(of: document) {
					closeTabs(at: IndexSet(integer: i), askToSaveChanges: false, createDocumentIfEmpty: fileBrowserVisible, activate: activateFlag)
				}

				if _documents.isEmpty {
					close()
				}
			}
		}
	}

	@objc func saveDocument(_ sender: Any?) {
		guard let doc = selectedDocument else { return }

		if doc.path != nil {
			saveDocuments(using: [ doc ].makeIterator(), completionHandler: nil)
		} else {
			let suggestedFolder = untitledSavePath
			let suggestedName   = doc.displayName(withExtension: true)
			DWShowSavePanelForDocument(doc, suggestedName, suggestedFolder, window) { [self] path, newlines, charset in
				guard let path = path else { return }

				let paths = DWExpandBraces(path) ?? []
				assert(paths.count > 0)

				doc.path         = paths[0]
				doc.diskNewlines = newlines
				doc.diskEncoding = charset

				// if(doc.identifier == _scratchDocument)
				// 	self.scratchDocument = nil;

				if paths.count > 1 {
					// FIXME check if paths[0] already exists (overwrite)

					var documents: [OakDocument] = [ doc ]
					for i in 1..<paths.count {
						guard let newDocument = OakDocumentController.sharedInstance.document(withPath: paths[i]) else { continue }
						newDocument.diskNewlines = newlines
						newDocument.diskEncoding = charset
						documents.append(newDocument)
					}

					insertDocuments(documents, at: _selectedTabIndex, selecting: doc, andClosing: nil)
				}

				saveDocuments(using: [ doc ].makeIterator(), completionHandler: nil)
			}
		}
	}

	@objc func saveDocumentAs(_ sender: Any?) {
		guard let doc = selectedDocument else { return }

		let suggestedFolder = (doc.path as NSString?)?.deletingLastPathComponent ?? untitledSavePath
		let suggestedName   = (doc.path as NSString?)?.lastPathComponent ?? doc.displayName(withExtension: true)
		DWShowSavePanelForDocument(doc, suggestedName, suggestedFolder, window) { [self] path, newlines, charset in
			guard let path = path else { return }
			doc.path         = path
			doc.diskNewlines = newlines
			doc.diskEncoding = charset
			saveDocuments(using: [ doc ].makeIterator(), completionHandler: nil)
		}
	}

	private func saveDocuments(using iterator: IndexingIterator<[OakDocument]>, completionHandler callback: ((OakDocumentIOResult) -> Void)?) {
		var iterator = iterator
		if let document = iterator.next() {
			let token = NotificationCenter.default.addObserver(forName: NSNotification.Name.OakDocumentWillShowAlert, object: document, queue: nil) { [self] _ in
				if let i = _documents.firstIndex(of: document), document.isLoaded {
					if document != selectedDocument {
						selectedTabIndex = UInt(i)
						selectedDocument = document
					}

					if NSApp.isActive && (window.isMiniaturized || !window.isKeyWindow) {
						window.makeKeyAndOrderFront(self)
					}
				}
			}

			DWSaveDocumentModalForWindow(document, window) { [self] result, errorMessage, filterUUID in
				NotificationCenter.default.removeObserver(token)
				if result == .success {
					saveDocuments(using: iterator, completionHandler: callback)
				} else {
					if result == .failure {
						window.attachedSheet?.orderOut(self)
						if let filterUUID = filterUUID {
							DWShowCommandError(errorMessage, filterUUID, window)
						} else {
							// +tmAlertWithMessageText:informativeText:buttons: is an ObjC
							// variadic method, so Swift cannot call it. This is what it does.
							let alert = NSAlert()
							alert.messageText     = "The document “\(document.displayName ?? "")” could not be saved."
							alert.informativeText = errorMessage ?? "Please check Console output for reason."
							alert.addButton(withTitle: "OK")
							alert.beginSheetModal(for: window, completionHandler: nil)
						}
					}

					if let callback = callback {
						callback(result)
					}
				}
			}
		} else {
			if let callback = callback {
				callback(.success)
			}
		}
	}

	@objc func saveAllDocuments(_ sender: Any?) {
		let documentsToSave = _documents.filter { $0.isDocumentEdited }
		saveDocuments(using: documentsToSave.makeIterator(), completionHandler: nil)
	}

	@objc(saveAllEditedDocuments:completionHandler:)
	func saveAllEditedDocuments(_ includeAllFlag: Bool, completionHandler callback: @escaping (Bool) -> Void) {
		var documentsToSave: [OakDocument] = []
		if includeAllFlag {
			documentsToSave = _documents.filter { $0.isDocumentEdited && $0.path != nil }
		} else if let selectedDocument = selectedDocument, selectedDocument.isDocumentEdited || !selectedDocument.isOnDisk {
			documentsToSave = [ selectedDocument ]
		}

		saveDocuments(using: documentsToSave.makeIterator()) { result in
			callback(result == .success)
		}
	}

	@objc(htmlOutputView:forIdentifier:)
	func htmlOutputView(_ createFlag: Bool, forIdentifier identifier: UUID) -> OakHTMLOutputView? {
		// if createFlag == YES then return (potential new) OakHTMLOutputView where isRunningCommand == NO.
		// If createFlag == NO and there is non-busy OakHTMLOutputView with commandIdentifier == identifier then return it
		// otherwise return busy OakHTMLOutputView with commandIdentifier == identifier or nil.

		if !htmlOutputInWindow {
			let nonExistingOrNonBusy   = htmlOutputView == nil || !htmlOutputView!.isRunningCommand
			let existsForOurIdentifier = htmlOutputView != nil && htmlOutputView!.commandIdentifier == identifier
			if createFlag ? nonExistingOrNonBusy : existsForOurIdentifier {
				htmlOutputVisible = true
				return htmlOutputView
			}
		}

		var htmlOutputViews: [OakHTMLOutputView] = []
		if let controller = htmlOutputWindowController {
			htmlOutputViews.append(controller.htmlOutputView)
		}

		for window in NSApp.orderedWindows {
			if window.isVisible, !window.isMiniaturized, let controller = window.delegate as? HTMLOutputWindowController {
				htmlOutputViews.append(controller.htmlOutputView)
			}
		}

		let allHTMLViews = (htmlOutputViews as NSArray).filtered(using: NSPredicate(format: "needsNewWebView == NO AND isReusable == YES AND commandIdentifier == %@", identifier as NSUUID)) as! [OakHTMLOutputView]
		let nonBusyViews = (allHTMLViews as NSArray).filtered(using: NSPredicate(format: "isRunningCommand == NO")) as! [OakHTMLOutputView]

		if let view = nonBusyViews.first {
			return view
		} else if createFlag {
			htmlOutputWindowController = HTMLOutputWindowController(identifier: identifier)
			return htmlOutputWindowController?.htmlOutputView
		}
		return allHTMLViews.first
	}

	@objc func showDocument(_ aDocument: OakDocument) {
		OakDocumentController.sharedInstance.showDocument(aDocument, inProject: identifier, bringToFront: true)
	}

	// ================
	// = Window Title =
	// ================

	@objc func updateWindowTitle() {
		if let document = selectedDocument, document.displayName != nil {
			window.title = DWTitleForDocument(document, .window, projectPath, untitledSavePath, scopeAttributes(), scopeContext)
		} else {
			window.title = "«no documents»"
		}
	}

	// ========================
	// = OakTextView Delegate =
	// ========================

	// The one C++ line this used to have — converting scm::status::type to its
	// attribute fragment — is DWSCMStatusAttribute now, which is why the rest of it
	// could stay on this side rather than joining the ObjC++ category.
	@objc func scopeAttributes() -> String? {
		let statusAttribute = selectedDocument.flatMap { DWSCMStatusAttribute($0) }
		return scopeContext.scopeAttributes(withSCMStatusAttribute: statusAttribute)
	}

	@objc func updateExternalAttributes() {
		scopeContext.updateExternalAttributes(forDocumentPath: selectedDocument?.path)
	}

	@objc func takeProjectPathFrom(_ aMenuItem: NSMenuItem) {
		if let path = aMenuItem.representedObject as? String {
			projectPath = path
			defaultProjectPath = path
		}
	}

	// ==============
	// = Properties =
	// ==============

	@objc var untitledSavePath: String? {
		var res: String?
		if fileBrowserVisible, let fileBrowser = fileBrowser {
			res = fileBrowser.outlineView.numberOfSelectedRows == 1 ? fileBrowser.directoryURLForNewItems?.path : fileBrowser.path
		}
		return res ?? projectPath ?? (selectedDocument?.path as NSString?)?.deletingLastPathComponent
	}

	@objc var treatAsProjectWindow: Bool {
		return projectPath != nil && (fileBrowserVisible || _documents.count > 1)
	}

	@objc var positionForWindowUnderCaret: NSPoint {
		return textView.positionForWindowUnderCaret()
	}

	@objc func goToRelatedFile(_ sender: Any?) {
		guard let document = selectedDocument, document.path != nil else {
			return NSSound.beep()
		}

		guard let path = DWRelatedFilePath(document, _documents, projectPath, scopeAttributes(), scopeContext) else {
			return NSSound.beep()
		}

		openItems([ [ "path": path ] ], closingOtherTabs: false, activate: true)
	}

	// ===========================
	// = OakTabBarViewDataSource =
	// ===========================

	func numberOfRows(in aTabBarView: OakTabBarView) -> UInt { UInt(_documents.count) }
	func tabBarView(_ aTabBarView: OakTabBarView, titleFor anIndex: UInt) -> String { DWTitleForDocument(_documents[Int(anIndex)], .tab, projectPath, untitledSavePath, scopeAttributes(), scopeContext) }
	func tabBarView(_ aTabBarView: OakTabBarView, pathFor anIndex: UInt) -> String { _documents[Int(anIndex)].path ?? "" }
	func tabBarView(_ aTabBarView: OakTabBarView, uuidFor anIndex: UInt) -> UUID { _documents[Int(anIndex)].identifier }
	func tabBarView(_ aTabBarView: OakTabBarView, isEditedAt anIndex: UInt) -> Bool { _documents[Int(anIndex)].isDocumentEdited }

	// ==============================
	// = OakTabBarView Context Menu =
	// ==============================

	@objc func tryObtainIndexSet(from sender: Any?) -> IndexSet? {
		let res: Any? = (sender as AnyObject?)?.responds(to: #selector(getter: NSMenuItem.representedObject)) == true ? (sender as AnyObject?)?.representedObject : sender
		if let indexSet = res as? IndexSet {
			return indexSet
		} else if let indexSet = res as? NSIndexSet {
			return indexSet as IndexSet
		} else if !_documents.isEmpty {
			return IndexSet(integer: Int(selectedTabIndex))
		}
		return nil
	}

	@objc func takeNewTabIndexFrom(_ sender: Any?) {
		if let indexSet = tryObtainIndexSet(from: sender), let first = indexSet.first {
			guard let doc = OakDocumentController.sharedInstance.untitledDocument() else { return }
			insertDocuments([ doc ], at: first, selecting: doc, andClosing: nil)
			openAndSelectDocument(doc, activate: true)
		}
	}

	@objc func takeTabsToCloseFrom(_ sender: Any?) {
		if let indexSet = tryObtainIndexSet(from: sender) {
			closeTabs(at: indexSet, askToSaveChanges: true, createDocumentIfEmpty: true, activate: true)
		}
	}

	@objc func takeTabsToTearOffFrom(_ sender: Any?) {
		if let indexSet = tryObtainIndexSet(from: sender) {
			let documents = indexSet.compactMap { $0 < _documents.count ? _documents[$0] : nil }
			if documents.count == 1 {
				let controller = DocumentWindowController()
				controller.documents = documents
				if DWIsChildPath(documents[0].path, projectPath) {
					controller.defaultProjectPath = projectPath
				}
				controller.openAndSelectDocument(documents[0], activate: true)
				controller.showWindow(self)
				closeTabs(at: indexSet, askToSaveChanges: false, createDocumentIfEmpty: true, activate: true)
			}
		}
	}

	@objc func toggleSticky(_ sender: Any?) {
		if let indexSet = tryObtainIndexSet(from: sender) {
			for doc in indexSet.compactMap({ $0 < _documents.count ? _documents[$0] : nil }) {
				setDocument(doc, sticky: !isDocumentSticky(doc))
			}
		}
	}

	func menu(for aTabBarView: OakTabBarView) -> NSMenu {
		let tabIndex = aTabBarView.tag
		let total    = _documents.count

		let newTabAtTab   = NSMutableIndexSet(index: tabIndex == -1 ? total : tabIndex + 1)
		let clickedTab    = tabIndex == -1 ? NSMutableIndexSet() : NSMutableIndexSet(index: tabIndex)
		let otherTabs     = tabIndex == -1 ? NSMutableIndexSet() : NSMutableIndexSet(indexesIn: NSRange(location: 0, length: total))
		let rightSideTabs = tabIndex == -1 ? NSMutableIndexSet() : NSMutableIndexSet(indexesIn: NSRange(location: 0, length: total))
		let leftSideTabs  = tabIndex == -1 ? NSMutableIndexSet() : NSMutableIndexSet(indexesIn: NSRange(location: 0, length: tabIndex))

		if tabIndex != -1 {
			otherTabs.remove(tabIndex)
			rightSideTabs.remove(in: NSRange(location: 0, length: tabIndex + 1))
			// No need to modify leftSideTabs
		}

		for i in 0..<_documents.count {
			if isDocumentSticky(_documents[i]) {
				otherTabs.remove(i)
				rightSideTabs.remove(i)
				leftSideTabs.remove(i)
			}
		}

		let closeSingleTabSelector = tabIndex == _selectedTabIndex ? #selector(performCloseTab(_:)) : #selector(takeTabsToCloseFrom(_:))

		// Hand-rolled rather than MBCreateMenu, which takes a C++ MBMenu of
		// designated initializers. MBCreateMenuItem's defaults are reproduced here:
		// a nil title makes a **separator**, keyEquivalentModifierMask defaults to
		// Command and is set on every item even when there is no key equivalent, and
		// target stays nil so the loop below can fill it in.
		let menu = NSMenu(title: "AMainMenu")

		func addItem(_ title: String?, _ action: Selector? = nil, modifierFlags: NSEvent.ModifierFlags = .command, alternate: Bool = false, representedObject: Any? = nil) {
			let item: NSMenuItem
			if let title = title {
				item = NSMenuItem(title: title, action: action, keyEquivalent: "")
			} else {
				item = NSMenuItem.separator()
			}
			item.keyEquivalentModifierMask = modifierFlags
			item.isAlternate               = alternate
			item.representedObject         = representedObject
			menu.addItem(item)
		}

		addItem("New Tab",                 #selector(takeNewTabIndexFrom(_:)),   representedObject: newTabAtTab)
		addItem("Move Tab to New Window",  #selector(takeTabsToTearOffFrom(_:)), representedObject: total > 1 ? clickedTab : NSIndexSet())
		addItem(nil)
		addItem("Close Tab",               closeSingleTabSelector,               representedObject: clickedTab)
		addItem("Close Other Tabs",        #selector(takeTabsToCloseFrom(_:)),   representedObject: otherTabs)
		addItem("Close Tabs to the Right", #selector(takeTabsToCloseFrom(_:)),   representedObject: rightSideTabs)
		addItem("Close Tabs to the Left",  #selector(takeTabsToCloseFrom(_:)),   modifierFlags: .option, alternate: true, representedObject: leftSideTabs)
		addItem(nil)
		addItem("Sticky",                  #selector(toggleSticky(_:)),          representedObject: clickedTab)

		for item in menu.items {
			// In fullscreen mode the window’s delegate is ignored as a target for menu actions, therefore we have to manually set the target for these menu items (as a workaround for what I can only assume is an OS bug)

			if item.target == nil, let action = item.action {
				item.target = NSApp.target(forAction: action) as AnyObject?
			}
		}
		return menu
	}

	// =========================
	// = OakTabBarViewDelegate =
	// =========================

	func tabBarView(_ aTabBarView: OakTabBarView, shouldSelect anIndex: UInt) -> Bool {
		openAndSelectDocument(_documents[Int(anIndex)], activate: true)
		selectedTabIndex = anIndex
		return true
	}

	func tabBarView(_ aTabBarView: OakTabBarView, didDoubleClick anIndex: UInt) {
		if _documents.count > 1 {
			takeTabsToTearOffFrom(NSMutableIndexSet(index: Int(anIndex)))
		}
	}

	func tabBarViewDidDoubleClick(_ aTabBarView: OakTabBarView) {
		takeNewTabIndexFrom(NSIndexSet(index: _documents.count))
	}

	// ================
	// = Tab Dragging =
	// ================

	// `fromTabBar:`/`toTabBar:` rather than the `from:`/`to:` Swift would normally
	// prefer: that is the name the importer gives OakTabBarViewDelegate's method,
	// and the protocol is @optional — so the shorter spelling compiles, satisfies
	// nothing, exposes no selector, and dragging a tab between windows silently
	// does nothing. Pinned by test_document_window_controller_keeps_its_delegate_methods.
	func performDrop(ofTabItem tabItemUUID: UUID, fromTabBar sourceTabBar: OakTabBarView, index dragIndex: UInt, toTabBar destTabBar: OakTabBarView, index droppedIndex: UInt, operation: NSDragOperation) -> Bool {
		guard let srcDocument = OakDocumentController.sharedInstance.findDocument(withIdentifier: tabItemUUID) else {
			return false
		}

		insertDocuments([ srcDocument ], at: Int(droppedIndex), selecting: selectedDocument, andClosing: [ srcDocument.identifier ])

		if operation == .move && sourceTabBar !== destTabBar {
			for delegate in DocumentWindowController.sortedControllers {
				if delegate === (sourceTabBar.delegate as AnyObject?) {
					let wasSelected = Int(dragIndex) == sourceTabBar.selectedTabIndex

					if delegate.fileBrowserVisible || delegate.documents.count > 1 {
						delegate.closeTabs(at: IndexSet(integer: Int(dragIndex)), askToSaveChanges: false, createDocumentIfEmpty: true, activate: true)
					} else {
						delegate.close()
					}

					if wasSelected {
						selectedTabIndex = UInt(documents.firstIndex(of: srcDocument) ?? NSNotFound)
						openAndSelectDocument(srcDocument, activate: true)
					}

					return true
				}
			}
		}

		return true
	}

	@objc func selectNextTab(_ sender: Any?)            { selectedTabIndex = UInt((_selectedTabIndex + 1) % _documents.count);                    openAndSelectDocument(_documents[_selectedTabIndex], activate: true) }
	@objc func selectPreviousTab(_ sender: Any?)        { selectedTabIndex = UInt((_selectedTabIndex + _documents.count - 1) % _documents.count); openAndSelectDocument(_documents[_selectedTabIndex], activate: true) }
	@objc func takeSelectedTabIndexFrom(_ sender: Any?) { selectedTabIndex = UInt((sender as AnyObject?)?.tag ?? 0);                              openAndSelectDocument(_documents[_selectedTabIndex], activate: true) }

	// ==================
	// = OakFileBrowser =
	// ==================

	func fileBrowser(_ fileBrowser: FileBrowserViewController, openURLs someURLs: [Any]) {
		var items: [[String: Any]] = []
		for case let url as URL in someURLs {
			if url.isFileURL {
				items.append([ "path": url.path ])
			}
		}
		openItems(items, closingOtherTabs: OakIsAlternateKeyOrMouseEvent(NSEvent.ModifierFlags.option.rawValue, NSApp.currentEvent), activate: true)
	}

	func fileBrowser(_ fileBrowser: FileBrowserViewController, close anURL: URL) {
		guard anURL.isFileURL else { return }

		let indexSet = IndexSet(_documents.indices.filter { _documents[$0].path == anURL.path })
		closeTabs(at: indexSet, askToSaveChanges: true, createDocumentIfEmpty: true, activate: false)
	}

	@objc var fileBrowserVisible: Bool {
		get { _fileBrowserVisible }
		set {
			if _fileBrowserVisible != newValue {
				_fileBrowserVisible = newValue
				if fileBrowser == nil && newValue {
					let browser = FileBrowserViewController()
					fileBrowser = browser
					browser.delegate = self
					browser.setupView(withState: _fileBrowserHistory)
					if _fileBrowserHistory == nil {
						if let path = projectPath ?? defaultProjectPath {
							browser.go(to: URL(fileURLWithPath: path))
						}
					}

					NotificationCenter.default.addObserver(self, selector: #selector(fileBrowserDidDuplicate(_:)), name: NSNotification.Name.FileBrowserDidDuplicate, object: nil)
				}

				if !newValue, let responder = window.firstResponder as? NSView, let fileBrowserView = layoutView.fileBrowserView, responder.isDescendant(of: fileBrowserView) {
					makeTextViewFirstResponder(self)
				}

				layoutView.fileBrowserView = newValue ? fileBrowser?.view : nil

				if newValue {
					if autoRevealFile && selectedDocument?.path != nil {
						revealFileInProject(self)
					}
				}

				if !disableFileBrowserWindowResize && !window.styleMask.contains(.fullScreen) {
					var windowFrame = window.frame

					if NSEqualRects(windowFrame, newWindowFrame) {
						windowFrame = oldWindowFrame
					} else if newValue {
						let screenFrame = window.screen?.visibleFrame ?? .zero
						var minX = NSMinX(windowFrame)
						var maxX = NSMaxX(windowFrame)

						if layoutView.fileBrowserOnRight {
							maxX += fileBrowserWidth + 1
						} else {
							minX -= fileBrowserWidth + 1
						}

						if minX < NSMinX(screenFrame) {
							maxX += NSMinX(screenFrame) - minX
						}
						if maxX > NSMaxX(screenFrame) {
							minX -= maxX - NSMaxX(screenFrame)
						}

						minX = max(minX, NSMinX(screenFrame))
						maxX = min(maxX, NSMaxX(screenFrame))

						windowFrame.origin.x   = minX
						windowFrame.size.width = maxX - minX
					} else {
						windowFrame.size.width -= fileBrowserWidth + 1
						if !layoutView.fileBrowserOnRight {
							windowFrame.origin.x += fileBrowserWidth + 1
						}
					}

					oldWindowFrame = window.frame
					window.setFrame(windowFrame, display: true)
					newWindowFrame = window.frame
				}
			}
			DocumentWindowController.scheduleSessionBackup(self)
		}
	}
	private var _fileBrowserVisible: Bool = false

	@objc func toggleFileBrowser(_ sender: Any?) { fileBrowserVisible = !fileBrowserVisible }

	@objc var fileBrowserHistory: Any? {
		get { fileBrowser?.sessionState ?? _fileBrowserHistory }
		set { _fileBrowserHistory = newValue }
	}
	private var _fileBrowserHistory: Any?

	@objc var fileBrowserWidth: CGFloat {
		get { layoutView.fileBrowserWidth }
		set { layoutView.fileBrowserWidth = newValue }
	}

	@objc func newFolder(_ sender: Any?)   { if let fileBrowser = fileBrowser { _ = fileBrowser.newFolder(sender) } }
	@objc func reload(_ sender: Any?)      { if let fileBrowser = fileBrowser { fileBrowser.reload(sender) } }
	@objc func deselectAll(_ sender: Any?) { if let fileBrowser = fileBrowser { fileBrowser.deselectAll(sender) } }

	@objc func revealFileInProject(_ sender: Any?) {
		if let selectedDocument = selectedDocument, let path = selectedDocument.path {
			fileBrowserVisible = true
			fileBrowser?.selectURL(URL(fileURLWithPath: path), withParentURL: projectPath.map { URL(fileURLWithPath: $0) })
		}
	}

	@objc func goToProjectFolder(_ sender: Any?) {
		fileBrowserVisible = true
		if let projectPath = projectPath {
			fileBrowser?.go(to: URL(fileURLWithPath: projectPath))
		}
	}

	@objc func goBack(_ sender: Any?)               { fileBrowserVisible = true; fileBrowser?.goBack(sender) }
	@objc func goForward(_ sender: Any?)            { fileBrowserVisible = true; fileBrowser?.goForward(sender) }
	@objc func goToParentFolder(_ sender: Any?)     { fileBrowserVisible = true; fileBrowser?.goToParentFolder(sender) }

	@objc func goToComputer(_ sender: Any?)         { fileBrowserVisible = true; fileBrowser?.goToComputer(sender) }
	@objc func goToHome(_ sender: Any?)             { fileBrowserVisible = true; fileBrowser?.goToHome(sender) }
	@objc func goToDesktop(_ sender: Any?)          { fileBrowserVisible = true; fileBrowser?.goToDesktop(sender) }
	@objc func goToFavorites(_ sender: Any?)        { fileBrowserVisible = true; fileBrowser?.goToFavorites(sender) }
	@objc func goToSCMDataSource(_ sender: Any?)    { fileBrowserVisible = true; fileBrowser?.goToSCMDataSource(sender) }
	@objc func orderFrontGoToFolder(_ sender: Any?) { fileBrowserVisible = true; fileBrowser?.orderFrontGoToFolder(sender) }

	// ===============
	// = HTML Output =
	// ===============

	@objc var htmlOutputSize: NSSize {
		get { layoutView.htmlOutputSize }
		set { layoutView.htmlOutputSize = newValue }
	}

	@objc var htmlOutputVisible: Bool {
		get {
			return htmlOutputInWindow ? (htmlOutputWindowController?.window?.isVisible ?? false) : layoutView.htmlOutputView != nil
		}
		set {
			if htmlOutputVisible == newValue {
				return
			}

			if newValue {
				if htmlOutputInWindow {
					htmlOutputWindowController?.showWindow(self)
				} else {
					if htmlOutputView == nil || htmlOutputView!.needsNewWebView {
						htmlOutputView = OakHTMLOutputView(frame: .zero)
					}
					layoutView.htmlOutputView = htmlOutputView
				}
			} else {
				if let outputView = layoutView.htmlOutputView, let responder = window.firstResponder as? NSView, responder.isDescendant(of: outputView) {
					makeTextViewFirstResponder(self)
				}

				if layoutView.htmlOutputView != nil {
					layoutView.htmlOutputView = nil
				} else {
					htmlOutputWindowController?.close()
				}
			}
		}
	}

	@objc var htmlOutputInWindow: Bool {
		get { _htmlOutputInWindow }
		set {
			if _htmlOutputInWindow == newValue {
				return
			}

			_htmlOutputInWindow = newValue
			if newValue {
				layoutView.htmlOutputView = nil
				htmlOutputView = nil
			} else {
				htmlOutputWindowController = nil
			}
		}
	}
	private var _htmlOutputInWindow: Bool = false

	@objc func toggleHTMLOutput(_ sender: Any?) {
		if htmlOutputVisible && htmlOutputInWindow && htmlOutputWindowController?.window?.isKeyWindow != true {
			htmlOutputWindowController?.showWindow(self)
		} else {
			htmlOutputVisible = !htmlOutputVisible
		}
	}

	// =============================
	// = Opening Auxiliary Windows =
	// =============================

	@objc func positionWindow(_ aWindow: NSWindow) {
		if !aWindow.isVisible {
			aWindow.layoutIfNeeded()
			var frame  = aWindow.frame
			let parent = window.convertToScreen(textView.convert(textView.visibleRect, to: nil))

			frame.origin.x = NSMinX(parent) + ((NSWidth(parent)  - NSWidth(frame))  * 1 / 4).rounded()
			frame.origin.y = NSMinY(parent) + ((NSHeight(parent) - NSHeight(frame)) * 3 / 4).rounded()
			aWindow.setFrame(frame, display: false)
		}
	}

	@objc var selectedDocumentUUID: UUID? {
		return selectedDocument?.identifier
	}

	@objc func prepareAndReturnFindPanel() -> Find {
		let find = Find.sharedInstance!
		find.documentIdentifier = selectedDocumentUUID
		find.projectFolder      = projectPath ?? untitledSavePath ?? NSHomeDirectory()
		DWSetFindDelegate(find, self)

		var items: [String] = []
		if fileBrowserVisible, let fileBrowser = fileBrowser {
			items = fileBrowser.selectedFileURLs.map { $0.path }
			if items.isEmpty {
				items = [ fileBrowser.path ?? find.projectFolder ]
			}
		}
		find.fileBrowserItems = items.isEmpty ? nil : items

		return find
	}

	@objc func orderFrontFindPanel(_ sender: Any?) {
		let find          = Find.sharedInstance!
		let didOwnDialog  = (find.delegate as AnyObject?) === self
		_ = prepareAndReturnFindPanel()

		var mode = (sender as AnyObject?)?.responds(to: #selector(getter: NSMenuItem.tag)) == true ? ((sender as AnyObject?)?.tag ?? FFSearchTarget.document.rawValue) : FFSearchTarget.document.rawValue
		if mode == FFSearchTarget.document.rawValue && !UserDefaults.standard.bool(forKey: kUserDefaultsAlwaysFindInDocument) && window.isKeyWindow && textView.hasMultiLineSelection {
			mode = FFSearchTarget.selection.rawValue
		}

		switch FFSearchTarget(rawValue: mode) {
			case .document:  find.searchTarget = .document
			case .selection: find.searchTarget = .selection
			case .other:     return find.showFolderSelectionPanel(self)

			case .project:
				// Only reset search target if the dialog is not already showing potential search results from “Other…”
				if !find.isVisible || !didOwnDialog || find.searchTarget == .document || find.searchTarget == .selection {
					let fileBrowserHasFocus = (window.firstResponder as? NSView).flatMap { responder in fileBrowser.map { responder.isDescendant(of: $0.view) } } ?? false
					find.searchTarget = fileBrowserHasFocus ? .fileBrowserItems : .project
				}

			default:
				break
		}
		find.showWindow(self)
	}

	@objc func orderFrontFindPanelForFileBrowser(_ sender: Any?) {
		let find = prepareAndReturnFindPanel()
		find.searchTarget = .fileBrowserItems
		find.showWindow(self)
	}

	@objc func orderFrontFindPanelForProject(_ sender: Any?) {
		let find = prepareAndReturnFindPanel()
		find.searchTarget = .project
		find.showWindow(self)
	}

	@objc func orderFrontRunCommandWindow(_ sender: Any?) {
		let runCommand = OakRunCommandWindowController.sharedInstance
		positionWindow(runCommand.window!)
		runCommand.showWindow(nil as Any?)
	}

	// ==================
	// = OakFileChooser =
	// ==================

	@objc func goToFile(_ sender: Any?) {
		let fc = FileChooser.sharedInstance!

		fc.path            = nil // Disable potential work when updating filterString/currentDocument
		fc.filterString    = ""
		fc.currentDocument = selectedDocumentUUID
		fc.target          = self
		fc.action          = #selector(fileChooserDidSelectItems(_:))
		fc.path            = projectPath ?? untitledSavePath ?? NSHomeDirectory()

		if let entry = OakPasteboard.find.current() {
			if let filterString = DWFindClipboardFilterString(entry.string, fc.path) {
				fc.filterString = filterString
			}
		}

		fc.showWindowRelative(toFrame: window.convertToScreen(textView.convert(textView.visibleRect, to: nil)))
	}

	@objc func fileChooserDidSelectItems(_ sender: FileChooser) {
		assert(sender.responds(to: #selector(getter: OakChooser.selectedItems)))
		openItems(sender.selectedItems as? [[String: Any]] ?? [], closingOtherTabs: OakIsAlternateKeyOrMouseEvent(NSEvent.ModifierFlags.option.rawValue, NSApp.currentEvent), activate: true)
	}

	// ==========================
	// = Show Tab Menu Delegate =
	// ==========================

	@objc func updateShowTabMenu(_ aMenu: NSMenu) {
		if !window.isKeyWindow {
			aMenu.addItem(withTitle: "No Tabs", action: Selector(("nop:")), keyEquivalent: "")
			return
		}

		var i = 0
		for document in _documents {
			let item = aMenu.addItem(withTitle: document.displayName ?? "", action: #selector(takeSelectedTabIndexFrom(_:)), keyEquivalent: i < 8 ? String(UnicodeScalar(UInt8(0x31 + i))) : "")
			item.tag     = i
			item.toolTip = (document.path as NSString?)?.abbreviatingWithTildeInPath
			if aMenu.propertiesToUpdate.contains(.propertyItemImage) {
				item.image = document.icon?.copy() as? NSImage
				item.image?.size = NSMakeSize(16, 16)
			}
			if i == _selectedTabIndex {
				item.state = .on
			} else if document.isDocumentEdited {
				item.setModifiedState(true)
			}
			i += 1
		}

		if i == 0 {
			aMenu.addItem(withTitle: "No Tabs Open", action: Selector(("nop:")), keyEquivalent: "")
		} else {
			aMenu.addItem(NSMenuItem.separator())

			let item = aMenu.addItem(withTitle: "Last Tab", action: #selector(takeSelectedTabIndexFrom(_:)), keyEquivalent: "9")
			item.tag     = _documents.count - 1
			item.toolTip = _documents.last?.displayName
		}
	}

	// ====================
	// = NSMenuValidation =
	// ====================

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		let delegateToFileBrowser: Set<Selector> = [
			#selector(newFolder(_:)), #selector(goBack(_:)), #selector(goForward(_:)),
			#selector(reload(_:)), #selector(deselectAll(_:))
		]

		var active = true
		if menuItem.action == #selector(toggleFileBrowser(_:)) {
			menuItem.title = fileBrowserVisible ? "Hide File Browser" : "Show File Browser"
		} else if menuItem.action == #selector(toggleHTMLOutput(_:)) {
			let isVisibleAndKey = htmlOutputVisible && (!htmlOutputInWindow || htmlOutputWindowController?.window?.isKeyWindow == true)
			menuItem.title = isVisibleAndKey ? "Hide HTML Output" : "Show HTML Output"
			active = !htmlOutputInWindow || htmlOutputWindowController != nil
		} else if menuItem.action == #selector(newDocumentInDirectory(_:)) {
			active = fileBrowserVisible && fileBrowser?.directoryURLForNewItems != nil
			menuItem.setDynamicTitle(active ? "New File in “\(FileManager.default.displayName(atPath: fileBrowser?.directoryURLForNewItems?.path ?? ""))”" : "New File")
		} else if let action = menuItem.action, delegateToFileBrowser.contains(action) {
			active = fileBrowserVisible && ((fileBrowser as? NSMenuItemValidation)?.validateMenuItem(menuItem) ?? false)
		} else if menuItem.action == #selector(moveDocumentToNewWindow(_:)) {
			active = _documents.count > 1
		} else if menuItem.action == #selector(selectNextTab(_:)) || menuItem.action == #selector(selectPreviousTab(_:)) {
			active = _documents.count > 1
		} else if menuItem.action == #selector(revealFileInProject(_:)) || menuItem.action == Selector(("revealFileInProjectByExpandingAncestors:")) {
			active = selectedDocument?.path != nil
			menuItem.setDynamicTitle(active ? "Select “\(selectedDocument?.displayName ?? "")”" : "Select Document")
		} else if menuItem.action == #selector(goToProjectFolder(_:)) {
			active = projectPath != nil
		} else if menuItem.action == #selector(goToParentFolder(_:)) {
			active = window.firstResponder !== textView
		} else if menuItem.action == #selector(moveFocus(_:)) {
			menuItem.title = window.firstResponder === textView ? "Move Focus to File Browser" : "Move Focus to Document"
		} else if menuItem.action == #selector(takeProjectPathFrom(_:)) {
			menuItem.state = (defaultProjectPath == menuItem.representedObject as? String) ? .on : .off
		} else if menuItem.action == #selector(performCloseOtherTabsXYZ(_:)) {
			active = _documents.count > 1
		} else if menuItem.action == #selector(performCloseTabsToTheRight(_:)) {
			active = _selectedTabIndex + 1 < _documents.count
		} else if menuItem.action == #selector(performCloseTabsToTheLeft(_:)) {
			active = _selectedTabIndex > 0
		} else if menuItem.action == Selector(("performBundleItemWithUUIDStringFrom:")) {
			active = (textView as? NSMenuItemValidation)?.validateMenuItem(menuItem) ?? true
		}

		// `takeNewTabIndexFrom::` — two colons — names no method that exists, so a
		// New Tab item never reaches the index-set check below. Kept verbatim from
		// the ObjC++: correcting it would be a behaviour change, and the change it
		// would make is nothing, because that item's represented object is always a
		// one-element index set and `active` is already YES.
		let tabBarActions: [Selector] = [ #selector(performCloseTab(_:)), Selector(("takeNewTabIndexFrom::")), #selector(takeTabsToCloseFrom(_:)), #selector(takeTabsToTearOffFrom(_:)), #selector(toggleSticky(_:)) ]
		if let action = menuItem.action, tabBarActions.contains(action) {
			if let indexSet = tryObtainIndexSet(from: menuItem) {
				active = !indexSet.isEmpty
				if active && menuItem.action == #selector(toggleSticky(_:)), let first = indexSet.first, first < _documents.count {
					menuItem.state = isDocumentSticky(_documents[first]) ? .on : .off
				}
			}
		}

		return active
	}

	// =============
	// = Touch Bar =
	// =============

	private static let kTouchBarCustomizationIdentifier = NSTouchBar.CustomizationIdentifier("com.j23software.TextMate-NG.touch-bar.customization-identifier")
	private static let kTouchBarTabNavigationIdentifier = NSTouchBarItem.Identifier("com.j23software.TextMate-NG.touch-bar.tab-navigation")
	private static let kTouchBarNewTabItemIdentifier    = NSTouchBarItem.Identifier("com.j23software.TextMate-NG.touch-bar.new-tab")
	private static let kTouchBarQuickOpenItemIdentifier = NSTouchBarItem.Identifier("com.j23software.TextMate-NG.touch-bar.quick-open")
	private static let kTouchBarFindItemIdentifier      = NSTouchBarItem.Identifier("com.j23software.TextMate-NG.touch-bar.find")
	private static let kTouchBarFavoritesItemIdentifier = NSTouchBarItem.Identifier("com.j23software.TextMate-NG.touch-bar.favorites")

	override func makeTouchBar() -> NSTouchBar? {
		let bar = NSTouchBar()
		bar.delegate = self
		bar.defaultItemIdentifiers = [
			.otherItemsProxy,
			Self.kTouchBarTabNavigationIdentifier,
			Self.kTouchBarNewTabItemIdentifier,
			Self.kTouchBarQuickOpenItemIdentifier,
			.flexibleSpace,
			Self.kTouchBarFindItemIdentifier,
			Self.kTouchBarFavoritesItemIdentifier,
		]
		bar.customizationIdentifier = Self.kTouchBarCustomizationIdentifier
		bar.customizationAllowedItemIdentifiers = [
			Self.kTouchBarTabNavigationIdentifier,
			Self.kTouchBarNewTabItemIdentifier,
			Self.kTouchBarQuickOpenItemIdentifier,
			.flexibleSpace,
			Self.kTouchBarFindItemIdentifier,
			Self.kTouchBarFavoritesItemIdentifier,
		]
		return bar
	}

	@objc func updateTouchBarButtons() {
		previousNextTouchBarControl?.isEnabled = _documents.count > 1
	}

	func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
		var res: NSCustomTouchBarItem?
		if identifier == Self.kTouchBarTabNavigationIdentifier {
			if previousNextTouchBarControl == nil {
				let control = NSSegmentedControl(images: [ NSImage(named: NSImage.touchBarGoBackTemplateName)!, NSImage(named: NSImage.touchBarGoForwardTemplateName)! ], trackingMode: .momentary, target: self, action: #selector(didClickPreviousNextTouchBarControl(_:)))
				control.segmentStyle = .separated
				control.isEnabled    = _documents.count > 1
				previousNextTouchBarControl = control
			}

			res = NSCustomTouchBarItem(identifier: identifier)
			res?.view = previousNextTouchBarControl!
			res?.customizationLabel = "Back/Forward Tab"
		} else if identifier == Self.kTouchBarNewTabItemIdentifier {
			let newTabImage = NSImage(named: "TouchBarNewTabTemplate")
			newTabImage?.accessibilityDescription = "new tab"
			res = NSCustomTouchBarItem(identifier: identifier)
			res?.view = NSButton(image: newTabImage ?? NSImage(), target: self, action: #selector(newDocumentInTab(_:)))
			res?.visibilityPriority = .normal
			res?.customizationLabel = "New Tab"
		} else if identifier == Self.kTouchBarQuickOpenItemIdentifier {
			let quickOpenImage = NSImage(named: "TouchBarQuickOpenTemplate")
			quickOpenImage?.accessibilityDescription = "quick open"
			res = NSCustomTouchBarItem(identifier: identifier)
			res?.view = NSButton(image: quickOpenImage ?? NSImage(), target: self, action: #selector(goToFile(_:)))
			res?.visibilityPriority = .normal
			res?.customizationLabel = "Quick Open"
		} else if identifier == Self.kTouchBarFindItemIdentifier {
			let findInProjectButton = NSButton(image: NSImage(named: NSImage.touchBarSearchTemplateName)!, target: self, action: #selector(orderFrontFindPanel(_:)))
			findInProjectButton.tag = Int(FFSearchTarget.project.rawValue)
			res = NSCustomTouchBarItem(identifier: identifier)
			res?.view = findInProjectButton
			res?.visibilityPriority = .normal
			res?.customizationLabel = "Find"
		} else if identifier == Self.kTouchBarFavoritesItemIdentifier {
			let favoritesProjectsImage = NSImage(named: NSImage.touchBarBookmarksTemplateName)
			favoritesProjectsImage?.accessibilityDescription = "favorite projects"
			res = NSCustomTouchBarItem(identifier: identifier)
			res?.view = NSButton(image: favoritesProjectsImage ?? NSImage(), target: nil, action: Selector(("openFavorites:")))
			res?.visibilityPriority = .normal
			res?.customizationLabel = "Favorite Projects"
		}
		return res
	}

	@objc func didClickPreviousNextTouchBarControl(_ control: NSSegmentedControl) {
		switch control.selectedSegment {
			case 0: selectPreviousTab(control)
			case 1: selectNextTab(control)
			default: break
		}
	}

	// ======================
	// = Session Management =
	// ======================

	// +initialize is not available to a Swift class. The one-shot notification
	// registration it did is triggered from +scheduleSessionBackup: instead, which
	// is what every one of those notifications called anyway.
	private static let installSessionBackupObservers: Void = {
		for notification in [ NSWindow.didBecomeKeyNotification, NSWindow.didDeminiaturizeNotification, NSWindow.didExposeNotification, NSWindow.didMiniaturizeNotification, NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.willCloseNotification ] {
			NotificationCenter.default.addObserver(DocumentWindowController.self, selector: #selector(DocumentWindowController.scheduleSessionBackup(_:)), name: notification, object: nil)
		}
	}()

	@objc class func backupSessionFiredTimer(_ aTimer: Timer) {
		_ = saveSession(includingUntitledDocuments: true)
	}

	@objc class func scheduleSessionBackup(_ sender: Any?) {
		_ = installSessionBackupObservers
		SessionBackupTimer?.invalidate()
		SessionBackupTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(backupSessionFiredTimer(_:)), userInfo: nil, repeats: false)
	}

	@objc class var sessionPath: String {
		return DWSessionPath()
	}

	@objc class func disableSessionSave() { DisableSessionSavingCount += 1 }
	@objc class func enableSessionSave()  { DisableSessionSavingCount -= 1 }

	@objc class func restoreSession() -> Bool {
		var res = false
		DisableSessionSavingCount += 1

		var keyWindow: NSWindow?

		let session = NSDictionary(contentsOfFile: sessionPath) as? [String: Any]
		for project in (session?["projects"] as? [[String: Any]]) ?? [] {
			let controller = DocumentWindowController()
			controller.setupController(forProject: project, skipMissingFiles: false)
			if controller.documents.isEmpty {
				continue
			}

			if let windowFrame = project["windowFrame"] as? String {
				if windowFrame.hasPrefix("{") { // Legacy NSRect
					controller.window.setFrame(NSRectFromString(windowFrame), display: false)
				} else {
					controller.window.setFrame(from: windowFrame)
				}
			}

			if (project["miniaturized"] as? Bool) == true {
				controller.window.miniaturize(nil)
			} else {
				if (project["fullScreen"] as? Bool) == true {
					controller.window.toggleFullScreen(self)
				} else if (project["zoomed"] as? Bool) == true {
					controller.window.zoom(self)
				}

				controller.window.order(.above, relativeTo: 0)
				keyWindow = controller.window
			}

			res = true
		}

		keyWindow?.makeKey()

		DisableSessionSavingCount -= 1
		return res
	}

	@objc(setupControllerForProject:skipMissingFiles:)
	func setupController(forProject project: [String: Any], skipMissingFiles skipMissing: Bool) {
		if let fileBrowserWidth = project["fileBrowserWidth"] {
			self.fileBrowserWidth = CGFloat((fileBrowserWidth as AnyObject).floatValue)
		}
		if let htmlOutputSize = project["htmlOutputSize"] as? String {
			self.htmlOutputSize = NSSizeFromString(htmlOutputSize)
		}

		defaultProjectPath = project["projectPath"] as? String
		projectPath        = project["projectPath"] as? String
		fileBrowserHistory = project["archivedFileBrowserState"] ?? project["fileBrowserState"]
		fileBrowserVisible = (project["fileBrowserVisible"] as? Bool) ?? false

		var documents: [OakDocument] = []
		var selectedTabIndex = 0

		for info in (project["documents"] as? [[String: Any]]) ?? [] {
			var doc: OakDocument?
			let identifier = info["identifier"] as? String
			let existing = identifier.flatMap { UUID(uuidString: $0) }.flatMap { OakDocument(identifier: $0) }
			if existing == nil {
				let path = info["path"] as? String
				if let path = path, skipMissing, access((path as NSString).fileSystemRepresentation, F_OK) != 0 {
					continue
				}

				doc = OakDocumentController.sharedInstance.document(withPath: path)
				if let fileType = info["fileType"] as? String {
					doc?.fileType = fileType
				}
				if let displayName = info["displayName"] as? String {
					doc?.customName = displayName
				}
				if (info["sticky"] as? Bool) == true, let doc = doc {
					setDocument(doc, sticky: true)
				}
			} else {
				doc = existing
			}

			guard let document = doc else { continue }

			if document.path == nil { // Add untitled documents to LRU-list
				OakDocumentController.sharedInstance.didTouchDocument(document)
			}

			document.isRecentTrackingDisabled = true
			documents.append(document)

			if (info["selected"] as? Bool) == true {
				selectedTabIndex = documents.count - 1
			}
		}

		if documents.isEmpty {
			if let untitled = OakDocumentController.sharedInstance.untitledDocument() { documents.append(untitled) }
		}

		self.documents        = documents
		self.selectedTabIndex = UInt(selectedTabIndex)

		openAndSelectDocument(documents[selectedTabIndex], activate: true)
	}

	@objc(sessionInfoIncludingUntitledDocuments:)
	func sessionInfo(includingUntitledDocuments includeUntitled: Bool) -> [String: Any] {
		var res: [String: Any] = [:]

		if let projectPath = defaultProjectPath {
			res["projectPath"] = projectPath
		}
		if let history = fileBrowserHistory {
			res["archivedFileBrowserState"] = history
		}

		if window.styleMask.contains(.fullScreen) {
			res["fullScreen"] = true
		} else if window.isZoomed {
			res["zoomed"] = true
		} else {
			res["windowFrame"] = window.frameDescriptor
		}

		res["miniaturized"]       = window.isMiniaturized
		res["htmlOutputSize"]     = NSStringFromSize(htmlOutputSize)
		res["fileBrowserVisible"] = fileBrowserVisible
		res["fileBrowserWidth"]   = fileBrowserWidth

		var docs: [[String: Any]] = []
		for document in _documents {
			if !includeUntitled && (document.path == nil || !DWPathExists(document.path)) {
				continue
			}

			var doc: [String: Any] = [:]
			if document.isDocumentEdited || document.path == nil {
				doc["identifier"] = document.identifier.uuidString
				if document.isLoaded {
					document.saveBackup(self)
				}
			}
			if let path = document.path {
				doc["path"] = path
			}
			if let fileType = document.fileType { // TODO Only necessary when document.isBufferEmpty
				doc["fileType"] = fileType
			}
			if let displayName = document.displayName {
				doc["displayName"] = displayName
			}
			if document == selectedDocument {
				doc["selected"] = true
			}
			if isDocumentSticky(document) {
				doc["sticky"] = true
			}
			docs.append(doc)
		}
		res["documents"] = docs
		res["lastRecentlyUsed"] = Date()
		return res
	}

	@objc(saveSessionIncludingUntitledDocuments:)
	class func saveSession(includingUntitledDocuments includeUntitled: Bool) -> Bool {
		if DisableSessionSavingCount != 0 {
			return false
		}

		var controllers: [DocumentWindowController]? = sortedControllers
		if controllers?.count == 1 {
			let controller = controllers![0]
			if controller.projectPath == nil && !controller.fileBrowserVisible && controller.documents.count == 1 && isDisposableDocument(controller.selectedDocument) {
				controllers = nil
			}
		}

		var projects: [[String: Any]] = []
		for controller in (controllers ?? []).reversed() {
			projects.append(controller.sessionInfo(includingUntitledDocuments: includeUntitled))
		}

		let session: [String: Any] = [ "projects": projects ]
		return (session as NSDictionary).write(toFile: sessionPath, atomically: true)
	}

	@objc(controllerForDocument:)
	class func controllerForDocument(_ aDocument: OakDocument?) -> DocumentWindowController? {
		guard let aDocument = aDocument else { return nil }

		for delegate in sortedControllers {
			if delegate.fileBrowserVisible, let path = aDocument.path, let projectPath = delegate.projectPath, path.hasPrefix(projectPath) {
				return delegate
			}

			for document in delegate.documents {
				if aDocument == document {
					return delegate
				}
			}
		}
		return nil
	}

	@objc func bringToFront() {
		showWindow(nil)
		if NSApp.isActive {
			// If we call ‘mate -w’ in quick succession there is a chance that we have a pending “re-activate the terminal app” when this code is executed, which will make ‘isActive’ return ‘YES’ but shortly after, our application will become inactive. For this reason, we monitor the NSApplicationDidResignActiveNotification for 200 ms and re-activate TextMate if we see the notification.

			var token: NSObjectProtocol?
			token = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: nil) { _ in
				if let token = token {
					NotificationCenter.default.removeObserver(token)
				}
				NSApp.activate(ignoringOtherApps: true)
			}

			DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
				if let token = token {
					NotificationCenter.default.removeObserver(token)
				}
			}
		} else {
			var token: NSObjectProtocol?
			token = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: nil) { [weak self] _ in
				// If our window is not on the active desktop but another one is, the system gives focus to the wrong window.
				self?.showWindow(nil)
				if let token = token {
					NotificationCenter.default.removeObserver(token)
				}
			}
			NSApp.activate(ignoringOtherApps: true)
		}
	}
}
