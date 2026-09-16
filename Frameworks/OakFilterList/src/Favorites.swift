import AppKit

// Ported from Favorites.mm — the "Open Recent Project" window: a scope bar
// switching between the recent-projects database and the user's Favorites
// folder, a filter over whichever is showing, and a remove button per row that
// forgets a recent project or trashes a favourite's symlink. Pinned by
// t_favorites.mm, written first.
//
// The class lived in the app until the previous commit and stayed ObjC++ there
// for rule 56: a Swift subclass of a Swift OakChooser, reached across a module
// boundary through a hand-written header, trapped in the runtime the moment
// the scope bar observed `sourceIndex`. Moving it beside OakChooser — the
// exit rule 56 names — is what let this port happen. Same module, no trap.
//
// Favorites.h stays as the hand-written declaration (rule 23) for the app's
// ObjC++ menu handler. The C++ — the Favorites folder walk and the ranking —
// is FavoritesSupport, extracted before the move (rule 25); the recent-
// projects half of loading is KVDB, sort descriptors and access(2), which
// Swift reaches directly.
//
// `sourceIndex` is `@objc dynamic` (rule 1): the scope bar binds to it on
// self, so the two-way binding needs KVO to see both ends.

private let kUserDefaultsOpenProjectSourceIndex = "openProjectSourceIndex"

private let kOakSourceIndexRecentProjects: UInt = 0
private let kOakSourceIndexFavorites: UInt      = 1

@objc(FavoriteChooser)
class FavoriteChooser: OakChooser {
	// +initialize registered the default; it now runs where the only caller
	// reaches the class (rule 24), as SoftwareUpdate's does.
	@objc static let sharedInstance: FavoriteChooser = {
		registerDefaults()
		return FavoriteChooser()
	}()

	@objc static func registerDefaults() {
		_ = registerDefaultsOnce
	}

	private static let registerDefaultsOnce: Void = {
		UserDefaults.standard.register(defaults: [
			kUserDefaultsOpenProjectSourceIndex: 0,
		])
	}()

	private var originalItems: [FavoritesItem] = []
	private var scopeBar: OakScopeBarViewController!
	@objc private(set) var sourceListLabels: [String] = []

	private var sharedProjectStateDB: KVDB {
		let appSupport = (NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)[0] as NSString).appendingPathComponent("TextMate")

		// KVDB does not create the directory, and sqlite3_open fails rather than
		// creating one, so this threw KVDBExceptionDBOpen wherever ~/Library/
		// Application Support/TextMate did not already exist. Nothing guarantees it:
		// oak::application_t::support only joins the path. In the app some other
		// subsystem has always got there first; on a CI runner nothing had, which is
		// how this surfaced.
		try? FileManager.default.createDirectory(atPath: appSupport, withIntermediateDirectories: true, attributes: nil)

		return KVDB.sharedDB(usingFile: "RecentProjects.db", inDirectory: appSupport)
	}

	@objc override init() {
		super.init()

		sourceListLabels = [ "Recent Projects", "Favorites" ]

		window?.title = "Open Recent Project"
		tableView.allowsTypeSelect        = false
		tableView.allowsMultipleSelection = true
		tableView.refusesFirstResponder   = false
		tableView.rowHeight               = 38

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

		let footerViews: [String: NSView] = [
			"dividerView":        OakCreateNSBoxSeparator(),
			"statusTextField":    statusTextField,
			"itemCountTextField": itemCountTextField,
		]

		let footer = footerView
		OakAddAutoLayoutViewsToSuperview(Array(footerViews.values), footer)

		footer.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[dividerView]|",                                 options: [], metrics: nil, views: footerViews))
		footer.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[statusTextField]-[itemCountTextField]-|",      options: .alignAllCenterY, metrics: nil, views: footerViews))
		footer.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[dividerView(==1)]-(4)-[statusTextField]-(5)-|", options: [], metrics: nil, views: footerViews))

		updateScrollViewInsets()

		OakSetupKeyViewLoop([ tableView, searchField, scopeBar.view ])
		window?.initialFirstResponder = tableView

		// The ObjC++ seeded the ivar with NSNotFound so that this assignment went
		// through the setter and loaded the list. Swift does not run didSet from
		// the declaring class's own initializer, so the load is spelled out.
		sourceIndex = UInt(UserDefaults.standard.integer(forKey: kUserDefaultsOpenProjectSourceIndex))
		loadItems(self)
		updateItems(self)
		scopeBar.bind(.value, to: self, withKeyPath: "sourceIndex", options: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	@objc func selectNextTab(_ sender: Any?)     { scopeBar.selectNextButton(sender) }
	@objc func selectPreviousTab(_ sender: Any?) { scopeBar.selectPreviousButton(sender) }
	@objc(updateShowTabMenu:) func updateShowTabMenu(_ menu: NSMenu) { scopeBar.updateGo(to: menu) }

	override func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard let identifier = tableColumn?.identifier else {
			return nil
		}

		var res = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
		if res == nil {
			let removeTemplateImage = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { dstRect in
				NSColor.black.set()
				NSInsetRect(dstRect, 0, floor(dstRect.height/2)-1).fill()
				return true
			}
			removeTemplateImage.isTemplate = true

			let removeButton = NSButton()
			removeButton.controlSize          = .small
			removeButton.refusesFirstResponder = true
			removeButton.bezelStyle           = .roundRect
			removeButton.setButtonType(.momentaryPushIn)
			removeButton.image                = removeTemplateImage
			removeButton.target               = self
			removeButton.action               = #selector(takeItemToRemoveFrom(_:))

			let cellView = OakFileTableCellView(closeButton: removeButton)
			cellView.identifier = identifier

			removeButton.bind(.hidden, to: cellView, withKeyPath: "objectValue.isRemovable", options: [ .valueTransformerName: NSValueTransformerName.negateBooleanTransformerName ])
			res = cellView
		}

		res?.objectValue = items[row]
		return res
	}

	@objc dynamic var sourceIndex: UInt = 0 {
		didSet {
			if sourceIndex == oldValue {
				return
			}

			loadItems(self)
			updateItems(self)
			UserDefaults.standard.set(Int(sourceIndex), forKey: kUserDefaultsOpenProjectSourceIndex)
		}
	}

	@objc func loadItems(_ sender: Any?) {
		var items: [FavoritesItem] = []
		if sourceIndex == kOakSourceIndexRecentProjects {
			let descriptors = [
				NSSortDescriptor(key: "value.lastRecentlyUsed", ascending: false),
				NSSortDescriptor(key: "key.lastPathComponent", ascending: true, selector: #selector(NSString.localizedCompare(_:))),
			]
			// -allObjects returns nil, not an empty array, when the table is empty — a
			// fresh install, or a CI runner, where the ObjC++ nil-messaged its way to
			// an empty list (rule 33). Force-unwrapping it here trapped on the runner.
			let allObjects = (sharedProjectStateDB.allObjects() as NSArray?) ?? []
			for case let pair as [String: Any] in allObjects.sortedArray(using: descriptors) {
				if let key = pair["key"] as? String, access((key as NSString).fileSystemRepresentation, F_OK) == 0 {
					items.append(FavoritesItem(path: key, isLink: false, isRemovable: true))
				}
			}
		}
		else if sourceIndex == kOakSourceIndexFavorites {
			items.append(contentsOf: FavoritesSupport.favoritesFolderItems())
		}

		// Already sorted by display name when it came from the Favorites folder — see
		// +favoritesFolderItems, which does that as part of the walk.
		originalItems = items
	}

	override func showWindow(_ sender: Any?) {
		if window?.isVisible != true {
			filterString = ""
			loadItems(self)
			updateItems(self)
			if tableView.numberOfRows != 0 {
				tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
			}
		}
		super.showWindow(sender)
	}

	override func updateItems(_ sender: Any?) {
		let bindings = OakAbbreviations.abbreviations(forName: "OakFavoriteChooserBindings").strings(forAbbreviation: filterString)
		items = FavoritesSupport.rankItems(originalItems, filterString: filterString, bindings: bindings)
	}

	override func updateStatusText(_ sender: Any?) {
		if tableView.selectedRow != -1, let item = items[tableView.selectedRow] as? FavoritesItem {
			statusTextField.stringValue = ((item.path ?? "") as NSString).abbreviatingWithTildeInPath
		}
		else {
			statusTextField.stringValue = ""
		}
	}

	override func accept(_ sender: Any?) {
		if let filterString {
			for case let item as FavoritesItem in selectedItems {
				if let path = item.path {
					OakAbbreviations.abbreviations(forName: "OakFavoriteChooserBindings").learn(abbreviation: filterString, forString: path)
				}
			}
		}

		for case let item as FavoritesItem in selectedItems {
			if let path = item.path, var tmp = sharedProjectStateDB.value(forKey: path) as? [String: Any] {
				tmp["lastRecentlyUsed"] = Date()
				sharedProjectStateDB.setValue(tmp, forKey: path)
			}
		}

		super.accept(sender)
	}

	@discardableResult override func removeItems(at anIndexSet: IndexSet) -> UInt {
		let items = self.items
		let indexSet = IndexSet(anIndexSet.filter { ($0 < items.count) && ((items[$0] as? FavoritesItem)?.isRemovable ?? false) })

		for case let item as FavoritesItem in indexSet.map({ items[$0] }) {
			if let link = item.link {
				try? FileManager.default.trashItem(at: URL(fileURLWithPath: link), resultingItemURL: nil)
			}
			else if let path = item.path {
				sharedProjectStateDB.removeObject(forKey: path)
			}
		}

		loadItems(self) // update originalItems
		return super.removeItems(at: indexSet)
	}

	@objc private func takeItemToRemoveFrom(_ sender: NSButton) {
		let row = tableView.row(for: sender)
		if row != -1 {
			removeItems(at: IndexSet(integer: row))
		}
	}

	override func deleteForward(_ sender: Any?) {
		let itemsRemoved = removeItems(at: tableView.selectedRowIndexes)
		if itemsRemoved == 0 {
			NSSound.beep()
		}
	}

	override func deleteBackward(_ sender: Any?) {
		let index = tableView.selectedRowIndexes.first
		let itemsRemoved = removeItems(at: tableView.selectedRowIndexes)
		if itemsRemoved == 0 {
			NSSound.beep()
		}
		else if let index, index != 0, tableView.numberOfRows != 0 {
			tableView.selectRowIndexes(IndexSet(integer: index-1), byExtendingSelection: false)
		}
	}

	override func insertText(_ aString: Any) {
		filterString = aString as? String
		window?.makeFirstResponder(searchField)
		if let fieldEditor = window?.firstResponder as? NSText {
			fieldEditor.selectedRange = NSRange(location: (fieldEditor.string as NSString).length, length: 0)
		}
	}

	override func doCommand(by aSelector: Selector) {
		if responds(to: aSelector) {
			super.doCommand(by: aSelector)
		}
		else {
			let res = OakPerformTableViewActionFromSelector(tableView, aSelector)
			if res == OakPerformTableViewActionResult.moveAcceptReturn.rawValue {
				accept(self)
			} else if res == OakPerformTableViewActionResult.moveCancelReturn.rawValue {
				cancel(self)
			}
		}
	}

	override func keyDown(with anEvent: NSEvent) { interpretKeyEvents([anEvent]) }
	override func insertTab(_ sender: Any?)      { window?.selectNextKeyView(self) }
	override func insertBacktab(_ sender: Any?)  { window?.selectPreviousKeyView(self) }
}
