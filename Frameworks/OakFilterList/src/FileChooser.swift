import AppKit

// Ported from FileChooser.mm (2026-08-20). The ⌘T "Open Quickly" panel: three sources (all
// files under the project path, open documents, uncommitted changes), an incremental
// background search, and a filter field with its own mini-syntax. Its C++ was extracted
// first — the row model into FileChooserItem (std::string ivars, rule 20) and the globs,
// scm::info handle, filter parsing and path helpers into FileChooserSupport — so what is
// here is the controller. Contract pinned by t_file_chooser.mm (rule 18).
//
// DocumentWindowController.swift drives this from Swift and OakDocumentView.mm from ObjC++,
// both through the hand-declaration in FileChooser.h.
//
// The search is the delicate part and is translated faithfully rather than modernised: a
// background enumeration appends documents to shared state, a semaphore lets the panel show
// its first results without waiting for the whole walk, a timer drains the buffer with a
// doubling interval, and a token invalidates a search that has been superseded. The shared
// state lives in the small locked box below, which is what @synchronized(_searchResults)
// was; everything else stays on the main actor, inherited from OakChooser.

// Kept nonisolated and lock-guarded because the producer runs on a global queue while the
// consumer runs on the main actor. The token lives here too: it is compared on the producer
// side under the same lock, which is what makes cancellation race-free.
private final class FileChooserSearchState: @unchecked Sendable {
	private let lock = NSLock()
	private var results: [OakDocument] = []
	private var token: UInt = 0

	var currentToken: UInt {
		lock.lock(); defer { lock.unlock() }
		return token
	}

	func invalidate() {
		lock.lock(); defer { lock.unlock() }
		token &+= 1
	}

	func removeAll() {
		lock.lock(); defer { lock.unlock() }
		results.removeAll()
	}

	// False when the search has been superseded, which tells the enumeration to stop.
	func append(_ document: OakDocument, ifToken searchToken: UInt) -> Bool {
		lock.lock(); defer { lock.unlock() }
		guard searchToken == token else {
			return false
		}
		results.append(document)
		return true
	}

	// Drains and reports the last path in one step, because the original read
	// -lastObject.path and emptied the array inside a single @synchronized block.
	func drain() -> (documents: [OakDocument], lastPath: String?) {
		lock.lock(); defer { lock.unlock() }
		let documents = results
		let lastPath = results.last?.path
		results.removeAll()
		return (documents, lastPath)
	}
}

@objc(FileChooser)
class FileChooser: OakChooser {
	@objc static let sharedInstance = FileChooser()

	private static let userDefaultsSourceIndexKey = "fileChooserSourceIndex"

	// Private to the panel now: the three indices were exported from FileChooser.h as
	// extern NSUInteger constants (which Swift cannot provide, rule 19), but nothing outside
	// this file ever read them, so the declarations went away with the port.
	private static let allSourceIndex: UInt                = 0
	private static let openDocumentsSourceIndex: UInt      = 1
	private static let uncommittedChangesSourceIndex: UInt = 2

	private var scopeBar: OakScopeBarViewController!
	private var sourceListLabels: [String] = []
	private var progressIndicator: NSProgressIndicator!

	private var pollTimer: Timer?
	private var pollInterval: TimeInterval = 0

	private var scmInfo: FileChooserSCMInfo?
	private var records: NSMutableArray = []
	private var filter: FileChooserFilter?

	private var searching = false
	private var searchPath: String?
	private let searchState = FileChooserSearchState()

	@objc override init() {
		super.init()

		sourceListLabels = ["All", "Open Documents", "Uncommitted Documents"]

		tableView.allowsMultipleSelection = true
		tableView.rowHeight = 38

		scopeBar = OakScopeBarViewController()
		scopeBar.labels = sourceListLabels

		let titlebarViews: [String: NSView] = [
			"searchField": searchField,
			"dividerView": OakCreateNSBoxSeparator(),
			"scopeBar":    scopeBar.view,
		]

		let titlebarView = NSView(frame: .zero)
		OakAddAutoLayoutViewsToSuperview(Array(titlebarViews.values), titlebarView)

		titlebarView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(8)-[searchField]-(8)-|", options: [], metrics: nil, views: titlebarViews))
		titlebarView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[dividerView]|", options: [], metrics: nil, views: titlebarViews))
		titlebarView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(8)-[scopeBar]-(>=8)-|", options: [], metrics: nil, views: titlebarViews))
		titlebarView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-(4)-[searchField]-(8)-[dividerView(==1)]-(4)-[scopeBar]-(4)-|", options: [], metrics: nil, views: titlebarViews))
		addTitlebarAccessoryView(titlebarView)

		progressIndicator = NSProgressIndicator(frame: .zero)
		progressIndicator.style                = .spinning
		progressIndicator.controlSize          = .small
		progressIndicator.isDisplayedWhenStopped = false

		let footerViews: [String: NSView] = [
			"dividerView":        OakCreateNSBoxSeparator(),
			"statusTextField":    statusTextField,
			"itemCountTextField": itemCountTextField,
			"progressIndicator":  progressIndicator,
		]

		let footer = footerView
		OakAddAutoLayoutViewsToSuperview(Array(footerViews.values), footer)

		footer.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[dividerView]|", options: [], metrics: nil, views: footerViews))
		footer.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(24)-[statusTextField]-[itemCountTextField]-(4)-[progressIndicator]-(4)-|", options: .alignAllCenterY, metrics: nil, views: footerViews))
		footer.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[dividerView(==1)]-(4)-[statusTextField]-(5)-|", options: [], metrics: nil, views: footerViews))

		updateScrollViewInsets()

		OakSetupKeyViewLoop([searchField, scopeBar.view])
		window?.initialFirstResponder = searchField

		sourceIndex = UInt(UserDefaults.standard.integer(forKey: Self.userDefaultsSourceIndexKey))
		updateWindowTitle()
		scopeBar.bind(.value, to: self, withKeyPath: "sourceIndex", options: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	@objc func selectNextTab(_ sender: Any?) { scopeBar.selectNextButton(sender) }
	@objc func selectPreviousTab(_ sender: Any?) { scopeBar.selectPreviousButton(sender) }
	@objc(updateShowTabMenu:) func updateShowTabMenu(_ menu: NSMenu) { scopeBar.updateGo(to: menu) }

	func windowWillClose(_ notification: Notification) {
		stopSearch()
		scmInfo = nil
		records = []

		items = []
	}

	private func updateWindowTitle() {
		var src: String?
		switch sourceIndex {
			case Self.allSourceIndex:                src = (path as NSString?)?.abbreviatingWithTildeInPath
			case Self.openDocumentsSourceIndex:      src = "Open Documents"
			case Self.uncommittedChangesSourceIndex: src = "Uncommitted Documents"
			default:                                 break
		}
		window?.title = src ?? "Open Quickly"
	}

	@objc var currentDocument: NSUUID? {
		didSet {
			if currentDocument === oldValue || currentDocument?.isEqual(oldValue) == true {
				return
			}
			reload()
		}
	}

	@objc var sourceIndex: UInt = 0 {
		didSet {
			guard sourceIndex != oldValue else {
				return
			}
			updateWindowTitle()
			reload()

			if sourceIndex == 0 {
				UserDefaults.standard.removeObject(forKey: Self.userDefaultsSourceIndexKey)
			} else {
				UserDefaults.standard.set(sourceIndex, forKey: Self.userDefaultsSourceIndexKey)
			}
		}
	}

	private func addRecords(for documents: [OakDocument]) {
		let firstDirty = records.count
		for document in documents {
			if let item = FileChooserItem(document: document, base: path, isCurrent: document.identifier == currentDocument as UUID?) {
				records.add(item)
			}
		}

		updateRecords(from: UInt(firstDirty))
	}

	private func updateRecords(from first: UInt) {
		// OakNotEmptyString, matching the batch ranker's own test exactly: the original only
		// looked up abbreviations on the filter branch, and a nil-vs-empty mismatch here
		// would silently drop the user's learned bindings.
		let bindings = OakNotEmptyString(filter?.globString) ? nil : OakAbbreviations.abbreviations(forName: "OakFileChooserBindings").strings(forAbbreviation: filter?.filterString)
		items = FileChooserItem.rankedItems(fromRecords: (records as? [FileChooserItem]) ?? [], from: UInt(first), globString: filter?.globString, filterString: filter?.filterString, bindings: bindings)
	}

	// MARK: - Path

	@objc var path: String? {
		didSet {
			if path == oldValue {
				return
			}
			scmInfo = nil

			if sourceIndex == Self.allSourceIndex {
				startSearch(path)
			} else if sourceIndex == Self.uncommittedChangesSourceIndex {
				reloadSCMStatus()
			}
			updateWindowTitle()
		}
	}

	private func reload() {
		stopSearch()
		scmInfo = nil

		switch sourceIndex {
			case Self.allSourceIndex:
				startSearch(path)

			case Self.openDocumentsSourceIndex:
				records = []
				addRecords(for: OakDocumentController.sharedInstance.openDocuments())

			case Self.uncommittedChangesSourceIndex:
				reloadSCMStatus()

			default:
				break
		}
	}

	private func reloadSCMStatus() {
		if scmInfo == nil {
			scmInfo = FileChooserSCMInfo(forPath: path)
			if let scmInfo {
				scmInfo.addStatusCallback { [weak self] in
					MainActor.assumeIsolated {
						guard let self, self.sourceIndex == Self.uncommittedChangesSourceIndex else { return }
						self.reloadSCMStatus()
					}
				}
			}
		}

		records = []
		if let scmInfo {
			let scmStatus = scmInfo.uncommittedPaths().compactMap { OakDocument(path: $0) }
			addRecords(for: scmStatus)
		}
	}

	private func startSearch(_ path: String?) {
		if searching {
			stopSearch()
		}

		items = []
		records = []

		guard let path else {
			return
		}

		// Built once here and only read on the background queue, never mutated after — which
		// the plist-shaped dictionary's type cannot express to the compiler.
		nonisolated(unsafe) let options = FileChooserSupport.searchOptions(forPath: path)

		let searchToken = searchState.currentToken
		searching = true
		searchState.removeAll()

		let sem = DispatchSemaphore(value: 0)
		let state = searchState

		DispatchQueue.global(qos: .default).async { [weak self] in
			// Touched only on this queue, so a box rather than any synchronisation: it
			// records whether the semaphore was already signalled by the first unopened
			// document, which is what lets the panel paint before the walk finishes.
			final class Flag { var didSignal = false }
			let flag = Flag()

			OakDocumentController.sharedInstance.enumerateDocuments(atPath: path, options: options) { document, stop in
				guard let document else {
					return
				}

				if document.isOpen == false, !flag.didSignal {
					sem.signal()
					flag.didSignal = true
				}

				if !state.append(document, ifToken: searchToken) {
					stop?.pointee = true
				}
			}

			if flag.didSignal == false {
				sem.signal()
			}

			DispatchQueue.main.async {
				MainActor.assumeIsolated {
					guard let self, searchToken == state.currentToken else { return }
					self.searching = false
					self.handleSearchResults(nil)
				}
			}
		}

		sem.wait()
		handleSearchResults(nil)

		pollInterval = 0.02
		pollTimer = Timer.scheduledTimer(timeInterval: pollInterval, target: self, selector: #selector(handleSearchResults(_:)), userInfo: nil, repeats: false)
		progressIndicator.perform(#selector(NSProgressIndicator.startAnimation(_:)), with: self, afterDelay: 0.2)
	}

	@objc private func handleSearchResults(_ timer: Timer?) {
		// The drain is atomic; the ranking that follows is not held under the lock the way
		// the ObjC++ held it. Nothing is lost — anything the producer appends meanwhile lands
		// in the emptied buffer and is picked up by the next poll — and it stops a long rank
		// from blocking the background walk.
		let (documents, lastPath) = searchState.drain()
		if !documents.isEmpty || !searching {
			searchPath = searching ? (lastPath as NSString?)?.deletingLastPathComponent : nil
		}
		addRecords(for: documents)

		if searching {
			pollInterval = min(pollInterval * 2, 0.32)
			pollTimer = Timer.scheduledTimer(timeInterval: pollInterval, target: self, selector: #selector(handleSearchResults(_:)), userInfo: nil, repeats: false)
		} else {
			stopSearch()
			updateStatusText(self)
		}
	}

	private func stopSearch() {
		if searching {
			searching = false
			searchState.invalidate()
		}

		NSObject.cancelPreviousPerformRequests(withTarget: progressIndicator as Any, selector: #selector(NSProgressIndicator.startAnimation(_:)), object: self)
		progressIndicator.stopAnimation(self)
		pollTimer?.invalidate()
		pollTimer = nil
	}

	override func updateFilterString(_ string: String?) {
		let oldFilter = filter?.effectiveFilter ?? ""
		filter = FileChooserFilter(string: string)

		if oldFilter != filter?.effectiveFilter {
			super.updateFilterString(string)
		}
	}

	override func updateItems(_ sender: Any?) {
		updateRecords(from: 0)
	}

	override func updateStatusText(_ sender: Any?) {
		if searching {
			let relative = FileChooserSupport.path(searchPath, relativeTo: path)
			statusTextField.cell?.lineBreakMode = .byTruncatingMiddle
			statusTextField.stringValue = "Searching “\(relative ?? "")”…"
		} else if tableView.selectedRow == -1 {
			statusTextField.stringValue = ""
		} else if let record = (items as? [FileChooserItem])?[tableView.selectedRow] {
			var displayPath = record.document?.path
			if let path = displayPath {
				if let base = self.path, path.hasPrefix(base) {
					displayPath = FileChooserSupport.path(path, relativeTo: base)
				} else {
					displayPath = (path as NSString).abbreviatingWithTildeInPath
				}
			} else { // untitled file
				displayPath = record.document?.displayName
			}

			statusTextField.cell?.lineBreakMode = .byTruncatingHead
			statusTextField.stringValue = displayPath ?? ""
		}
	}

	override var selectedItems: [Any] {
		var res: [[String: String]] = []
		for record in selectedRecords() {
			var item: [String: String] = [:]
			if OakNotEmptyString(filter?.selectionString), let selectionString = filter?.selectionString {
				item["selectionString"] = selectionString
			}
			if let path = record.document?.path {
				item["path"] = path
			} else if let identifier = record.document?.identifier?.uuidString {
				item["identifier"] = identifier
			}
			res.append(item)
		}
		return res
	}

	private func selectedRecords() -> [FileChooserItem] {
		guard let records = items as? [FileChooserItem] else {
			return []
		}
		return tableView.selectedRowIndexes.compactMap { $0 < records.count ? records[$0] : nil }
	}

	// MARK: - NSTableViewDelegate

	override func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard let identifier = tableColumn?.identifier else {
			return nil
		}

		var res = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
		if res == nil {
			let closeButton = OakCreateCloseButton()!
			closeButton.target = self
			closeButton.action = #selector(takeItemToCloseFrom(_:))

			let cellView = OakFileTableCellView(closeButton: closeButton)
			cellView.identifier = identifier
			closeButton.bind(.hidden, to: cellView, withKeyPath: "objectValue.closeDisabled", options: nil)
			res = cellView
		}

		res?.objectValue = items[row]
		return res
	}

	// MARK: - Actions

	override func accept(_ sender: Any?) {
		if OakNotEmptyString(filter?.filterString), let filterString = filter?.filterString {
			for item in selectedRecords() {
				if !item.isDirectoryMatched, let path = item.document?.path {
					OakAbbreviations.abbreviations(forName: "OakFileChooserBindings").learn(abbreviation: filterString, forString: path)
				}
			}
		}

		super.accept(sender)
	}

	@objc private func takeItemToCloseFrom(_ sender: NSButton) {
		let row = tableView.row(for: sender)
		guard row != -1, let item = (items as? [FileChooserItem])?[row], let path = item.document?.path else {
			return
		}

		// FIXME We need a proper interface to close documents
		if let target = NSApp.target(forAction: #selector(FileBrowserClosing.fileBrowser(_:closeURL:))) as? FileBrowserClosing {
			target.fileBrowser(nil, closeURL: URL(fileURLWithPath: path))
		}
	}

	@objc func goToParentFolder(_ sender: Any?) {
		path = (path as NSString?)?.deletingLastPathComponent
	}

	@objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
		var activate = true
		if item.action == #selector(goToParentFolder(_:)) {
			activate = sourceIndex == Self.allSourceIndex && FileChooserSupport.pathHasParent(path)
		}
		return activate
	}
}

// The informal protocol the ObjC++ declared as a category on NSObject to reach whatever
// object in the responder chain knows how to close a document. Kept as an @objc protocol so
// the -targetForAction: lookup still finds the same selector.
@objc private protocol FileBrowserClosing {
	@objc(fileBrowser:closeURL:)
	func fileBrowser(_ fileBrowser: Any?, closeURL url: URL)
}
