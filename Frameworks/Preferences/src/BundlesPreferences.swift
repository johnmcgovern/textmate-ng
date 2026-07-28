import AppKit

private let kTableColumnIdentifierInstalled   = NSUserInterfaceItemIdentifier("Installed")
private let kTableColumnIdentifierBundleName  = NSUserInterfaceItemIdentifier("BundleName")
private let kTableColumnIdentifierWebLink     = NSUserInterfaceItemIdentifier("WebLink")
private let kTableColumnIdentifierUpdated     = NSUserInterfaceItemIdentifier("Updated")
private let kTableColumnIdentifierDescription = NSUserInterfaceItemIdentifier("Description")

// =======================
// = BundleInstallHelper =
// =======================

@objc(BundleInstallHelper) final class BundleInstallHelper: NSObject {
	// Main-thread-only by convention, exactly as the ObjC singleton was: it is
	// only ever touched from bindings and from BundlesManager's completion
	// handlers, both of which run on the main thread.
	@objc nonisolated(unsafe) static let sharedInstance = BundleInstallHelper()

	@objc dynamic var bundlesBeingInstalled = NSMutableSet()
	@objc dynamic var bundleInstallActivityText: String?

	@objc class func keyPathsForValuesAffectingBusy() -> Set<String> { ["bundlesBeingInstalled"] }
	@objc class func keyPathsForValuesAffectingActivityText() -> Set<String> { ["bundleInstallActivityText"] }

	@objc dynamic var isBusy: Bool { bundlesBeingInstalled.count != 0 }

	@objc dynamic var activityText: String {
		if let bundleInstallActivityText {
			return bundleInstallActivityText
		}

		if let date = UserDefaults.standard.object(forKey: kUserDefaultsLastBundleUpdateCheckKey) as? Date {
			let dateString = -date.timeIntervalSinceNow < 5 ? "Just now" : RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date.now)
			return "Bundle index last updated: \(dateString)"
		}

		return ""
	}

	func install(_ bundle: TMBundle) {
		guard !bundlesBeingInstalled.contains(bundle) else { return }

		willChangeValue(forKey: "bundlesBeingInstalled")
		bundlesBeingInstalled.add(bundle)
		didChangeValue(forKey: "bundlesBeingInstalled")

		bundleInstallActivityText = "Installing ‘\(bundle.name ?? "")’ bundle…"

		BundlesManager.sharedInstance.installBundles([bundle]) { [weak self] installed in
			guard let self else { return }
			let bundles = installed ?? []
			let name = bundle.name ?? ""
			if !bundle.isInstalled {
				self.bundleInstallActivityText = "Error installing ‘\(name)’ bundle."
			} else if bundles.count == 1 {
				self.bundleInstallActivityText = "Installed ‘\(name)’ bundle."
			} else if bundles.count == 2 {
				self.bundleInstallActivityText = "Installed ‘\(name)’ bundle and one dependency."
			} else {
				self.bundleInstallActivityText = "Installed ‘\(name)’ bundle and \(bundles.count - 1) dependencies."
			}

			self.willChangeValue(forKey: "bundlesBeingInstalled")
			self.bundlesBeingInstalled.remove(bundle)
			self.didChangeValue(forKey: "bundlesBeingInstalled")
		}
	}

	func uninstall(_ bundle: TMBundle) {
		BundlesManager.sharedInstance.uninstallBundle(bundle)
		bundleInstallActivityText = "Uninstalled ‘\(bundle.name ?? "")’ bundle."
	}
}

// ===========================================
// = Bundle + the table's tri-state checkbox =
// ===========================================

// A Swift extension of an ObjC class emits a real ObjC category, so the
// installedCellState the table column binds to is visible to KVC exactly as the
// original @interface Bundle (BundlesInstallPreferences) was.
extension TMBundle {
	@objc class func keyPathsForValuesAffectingInstalledCellState() -> Set<String> {
		["installed", "bundleInstallHelper.bundlesBeingInstalled"]
	}

	@objc dynamic var bundleInstallHelper: BundleInstallHelper { BundleInstallHelper.sharedInstance }

	@objc dynamic var installedCellState: NSControl.StateValue {
		get {
			if bundleInstallHelper.bundlesBeingInstalled.contains(self) {
				return .mixed
			}
			return isInstalled ? .on : .off
		}
		set {
			if installedCellState == .off && newValue != .off {
				bundleInstallHelper.install(self)
			} else if installedCellState == .on && newValue != .on {
				bundleInstallHelper.uninstall(self)
			}
		}
	}
}

// ======================
// = BundlesPreferences =
// ======================

@objc(BundlesPreferences) final class BundlesPreferences: PreferencesPane, NSTableViewDelegate {
	private var enabledCategories = Set<String>()
	private let arrayController = NSArrayController()
	private let scopeBar = OakScopeBarViewController()
	private var searchField: NSSearchField!
	private var bundlesTableView: NSTableView!

	// Compare unsigned-to-unsigned, exactly as the ObjC++ original did. Converting
	// to Int first traps ("Not enough bits to represent the passed value"): with
	// allowsEmptySelection the scope bar reports no selection as NSUInteger's max,
	// which is not representable as Int. Swift's checked conversions turn what was
	// a silently-wrapping ObjC comparison into a hard crash, so the bounds check
	// has to stay in the unsigned domain and the Int conversion happens only after
	// it has passed.
	@objc dynamic var selectedIndex: UInt = UInt(NSNotFound) {
		didSet {
			enabledCategories.removeAll()
			if let labels = scopeBar.labels as? [String], selectedIndex < UInt(labels.count) {
				enabledCategories.insert(labels[Int(selectedIndex)])
			}
			filterStringDidChange(self)
		}
	}

	override var toolbarItemImage: NSImage? {
		NSWorkspace.shared.icon(forFileType: "tmbundle")
	}

	init() {
		super.init(nibName: nil, label: "Bundles", image: nil)
		scopeBar.allowsEmptySelection = true
		scopeBar.controlSize = .small
	}

	private func column(identifier: NSUserInterfaceItemIdentifier, title: String, editable: Bool, width: CGFloat, resizingMask: NSTableColumn.ResizingOptions) -> NSTableColumn {
		let tableColumn = NSTableColumn(identifier: identifier)
		tableColumn.title = title
		tableColumn.isEditable = editable
		tableColumn.width = width
		tableColumn.resizingMask = resizingMask
		if resizingMask.isEmpty {
			tableColumn.minWidth = width
			tableColumn.maxWidth = width
		}
		return tableColumn
	}

	override func loadView() {
		var categories = Set<String>()
		for bundle in BundlesManager.sharedInstance.bundles ?? [] {
			if let category = bundle.category {
				categories.insert(category)
			}
		}
		scopeBar.labels = categories.sorted { $0.localizedCompare($1) == .orderedAscending }

		searchField = NSSearchField(frame: .zero)
		searchField.controlSize = .small
		searchField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
		searchField.target = self
		searchField.action = #selector(filterStringDidChange(_:))
		(searchField.cell as? NSSearchFieldCell)?.isScrollable = true
		(searchField.cell as? NSSearchFieldCell)?.sendsSearchStringImmediately = true

		arrayController.avoidsEmptySelection = false
		arrayController.sortDescriptors = [
			NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedCompare(_:))),
			NSSortDescriptor(key: "installed", ascending: true),
			NSSortDescriptor(key: "downloadLastUpdated", ascending: true),
			NSSortDescriptor(key: "textSummary", ascending: true, selector: #selector(NSString.localizedCompare(_:))),
		]

		let installedTableColumn   = column(identifier: kTableColumnIdentifierInstalled,   title: "",            editable: true,  width: 16,  resizingMask: [])
		let bundleTableColumn      = column(identifier: kTableColumnIdentifierBundleName,  title: "Bundle",      editable: false, width: 140, resizingMask: .userResizingMask)
		let linkTableColumn        = column(identifier: kTableColumnIdentifierWebLink,     title: "",            editable: false, width: 16,  resizingMask: [])
		let updatedTableColumn     = column(identifier: kTableColumnIdentifierUpdated,     title: "Updated",     editable: false, width: 90,  resizingMask: [])
		let descriptionTableColumn = column(identifier: kTableColumnIdentifierDescription, title: "Description", editable: false, width: 140, resizingMask: .autoresizingMask)

		let installedCell = NSButtonCell()
		installedCell.setButtonType(.switch)
		installedCell.allowsMixedState = true
		installedCell.controlSize = .small
		installedCell.title = ""
		installedTableColumn.dataCell = installedCell

		let linkCell = NSButtonCell()
		linkCell.setButtonType(.momentaryChange)
		linkCell.bezelStyle = .inline
		linkCell.isBordered = false
		linkCell.controlSize = .small
		linkCell.title = ""
		linkCell.action = #selector(didClickBundleLink(_:))
		linkCell.target = self
		linkTableColumn.dataCell = linkCell

		let updatedFormatter = DateFormatter()
		updatedFormatter.dateStyle = .medium

		let updatedCell = NSTextFieldCell(textCell: "")
		updatedCell.alignment = .right
		updatedCell.formatter = updatedFormatter
		updatedTableColumn.dataCell = updatedCell

		bundlesTableView = NSTableView(frame: .zero)
		bundlesTableView.allowsColumnReordering = false
		bundlesTableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
		bundlesTableView.delegate = self

		for tableColumn in [installedTableColumn, bundleTableColumn, linkTableColumn, updatedTableColumn, descriptionTableColumn] {
			bundlesTableView.addTableColumn(tableColumn)
		}
		bundlesTableView.setIndicatorImage(NSImage(named: "NSAscendingSortIndicator"), in: bundleTableColumn)

		let scrollView = NSScrollView(frame: .zero)
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers = true
		scrollView.borderType = .bezelBorder
		scrollView.documentView = bundlesTableView

		let updateBundlesCheckbox = NSButton(checkboxWithTitle: "Check for and install updates automatically", target: nil, action: nil)

		let statusTextField = NSTextField(labelWithString: "")
		statusTextField.textColor = .secondaryLabelColor
		statusTextField.font = NSFont.messageFont(ofSize: NSFont.smallSystemFontSize)

		let progressIndicator = NSProgressIndicator(frame: .zero)
		progressIndicator.controlSize = .small
		progressIndicator.isDisplayedWhenStopped = false
		progressIndicator.style = .spinning

		let footerView = NSVisualEffectView(frame: .zero)
		footerView.blendingMode = .withinWindow
		footerView.material = .titlebar

		let divider: NSView = OakCreateNSBoxSeparator()
		let footerViews: [String: NSView] = [
			"divider": divider,
			"spinner": progressIndicator,
			"status":  statusTextField,
		]
		OakAddAutoLayoutViewsToSuperview(Array(footerViews.values), footerView)
		footerView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[divider]|", options: [], metrics: nil, views: footerViews))
		footerView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[spinner]-(>=8)-[status]-(>=8)-|", options: .alignAllCenterY, metrics: nil, views: footerViews))
		footerView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[divider(==1)]-4-[status]-4-|", options: [], metrics: nil, views: footerViews))
		statusTextField.centerXAnchor.constraint(equalTo: footerView.centerXAnchor).isActive = true

		let views: [String: NSView] = [
			"scopeBar":      scopeBar.view,
			"search":        searchField,
			"scrollView":    scrollView,
			"updateBundles": updateBundlesCheckbox,
			"footer":        footerView,
		]

		let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 622, height: 454))
		OakAddAutoLayoutViewsToSuperview(Array(views.values), contentView)

		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-8-[scopeBar]-(>=8)-[search(>=50,<=100,==100@250)]-8-|", options: .alignAllCenterY, metrics: nil, views: views))
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[scrollView(>=50)]-|", options: [], metrics: nil, views: views))
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[updateBundles]-(>=8)-|", options: [], metrics: nil, views: views))
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[footer]|", options: .alignAllCenterY, metrics: nil, views: views))
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-8-[search]-8-[scrollView(>=50)]-[updateBundles]-20-[footer]|", options: [], metrics: nil, views: views))

		// ============
		// = Bindings =
		// ============

		arrayController.bind(.content, to: BundlesManager.sharedInstance, withKeyPath: "bundles", options: nil)
		scopeBar.bind(.value, to: self, withKeyPath: "selectedIndex", options: nil)

		bundlesTableView.bind(.content, to: arrayController, withKeyPath: "arrangedObjects", options: nil)
		bundlesTableView.bind(.selectionIndexes, to: arrayController, withKeyPath: "selectionIndexes", options: nil)

		installedTableColumn.bind(.value,   to: arrayController, withKeyPath: "arrangedObjects.installedCellState", options: nil)
		bundleTableColumn.bind(.value,      to: arrayController, withKeyPath: "arrangedObjects.name", options: nil)
		updatedTableColumn.bind(.value,     to: arrayController, withKeyPath: "arrangedObjects.downloadLastUpdated", options: nil)
		descriptionTableColumn.bind(.value, to: arrayController, withKeyPath: "arrangedObjects.textSummary", options: nil)

		updateBundlesCheckbox.bind(.value, to: NSUserDefaultsController.shared, withKeyPath: "values.disableBundleUpdates", options: [.valueTransformerName: NSValueTransformerName.negateBooleanTransformerName])

		progressIndicator.bind(.animate, to: BundleInstallHelper.sharedInstance, withKeyPath: "busy", options: nil)
		statusTextField.bind(.value, to: BundleInstallHelper.sharedInstance, withKeyPath: "activityText", options: nil)

		view = contentView
	}

	override func viewWillAppear() {
		BundleInstallHelper.sharedInstance.bundleInstallActivityText = nil
	}

	override func viewDidAppear() {
		let firstResponder = view.window?.firstResponder
		if firstResponder == nil || firstResponder === view.window || ((firstResponder as? NSView)?.isDescendant(of: view) ?? false) {
			view.window?.makeFirstResponder(bundlesTableView)
		}
	}

	@objc private func filterStringDidChange(_ sender: Any?) {
		var predicates: [NSPredicate] = []
		if OakNotEmptyString(searchField.stringValue) {
			predicates.append(NSPredicate(format: "name CONTAINS[cd] %@", searchField.stringValue))
		}
		if !enabledCategories.isEmpty {
			predicates.append(NSPredicate(format: "category IN %@", enabledCategories))
		}
		arrayController.filterPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
		arrayController.rearrangeObjects()
	}

	private var arrangedBundles: [TMBundle] {
		arrayController.arrangedObjects as? [TMBundle] ?? []
	}

	// ========================
	// = NSTableView Delegate =
	// ========================

	func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
		let map: [NSUserInterfaceItemIdentifier: String] = [
			kTableColumnIdentifierInstalled:   "installed",
			kTableColumnIdentifierBundleName:  "name",
			kTableColumnIdentifierUpdated:     "downloadLastUpdated",
			kTableColumnIdentifierDescription: "textSummary",
		]

		guard let key = map[tableColumn.identifier] else { return }

		var descriptors = arrayController.sortDescriptors
		guard let index = descriptors.firstIndex(where: { $0.key == key }) else { return }

		var descriptor = descriptors[index]
		if index == 0 || !descriptor.ascending {
			descriptor = descriptor.reversedSortDescriptor as! NSSortDescriptor
		}
		descriptors.remove(at: index)
		descriptors.insert(descriptor, at: 0)

		arrayController.sortDescriptors = descriptors

		for column in bundlesTableView.tableColumns {
			tableView.setIndicatorImage(nil, in: column)
		}
		tableView.setIndicatorImage(NSImage(named: descriptor.ascending ? "NSAscendingSortIndicator" : "NSDescendingSortIndicator"), in: tableColumn)
	}

	func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, row: Int) {
		guard let identifier = tableColumn?.identifier, row < arrangedBundles.count else { return }
		let bundle = arrangedBundles[row]

		if identifier == kTableColumnIdentifierWebLink {
			let enabled = bundle.htmlURL != nil
			(cell as? NSCell)?.isEnabled = enabled
			(cell as? NSButtonCell)?.image = enabled ? NSImage(named: "NSFollowLinkFreestandingTemplate") : nil
		} else if identifier == kTableColumnIdentifierInstalled {
			(cell as? NSCell)?.isEnabled = !bundle.isMandatory || !bundle.isInstalled
		}
	}

	func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
		guard tableColumn?.identifier == kTableColumnIdentifierInstalled, row < arrangedBundles.count else { return false }
		return arrangedBundles[row].installedCellState != .mixed
	}

	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		let clickedColumn = tableView.clickedColumn
		return clickedColumn != tableView.column(withIdentifier: kTableColumnIdentifierInstalled)
			&& clickedColumn != tableView.column(withIdentifier: kTableColumnIdentifierWebLink)
	}

	@objc private func didClickBundleLink(_ tableView: NSTableView) {
		let rowIndex = tableView.clickedRow
		guard rowIndex >= 0, rowIndex < arrangedBundles.count, let url = arrangedBundles[rowIndex].htmlURL else { return }
		NSWorkspace.shared.open(url)
	}
}
