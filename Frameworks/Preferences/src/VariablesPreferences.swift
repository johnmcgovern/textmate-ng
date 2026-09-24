import AppKit

private let kVariableKeyEnabled = "enabled"
private let kVariableKeyName    = "name"
private let kVariableKeyValue   = "value"

// **Not `final`.** This class is a Cocoa Bindings target for its own properties
// (`bind(…, to: self, …)`), so AppKit registers KVO on it and Foundation builds
// an NSKVONotifying_ subclass of it at run time. That is the rule aaf4395586
// earned — a Swift class ObjC can see must not be `final` if anything subclasses
// it, and KVO counts — applied to the cases that commit's survey missed: it
// looked for *source* subclassing, and "binds to self" is the marker for the
// runtime kind. Symptom is not a clean trap but intermittent heap corruption
// surfacing later at unrelated allocations (2026-08-18).
@objc(VariablesPreferences) class VariablesPreferences: PreferencesPane, NSTableViewDelegate, NSTableViewDataSource {
	private var variablesTableView: NSTableView!
	private var variables: [[String: Any]] = []
	@objc dynamic private var canRemove = false

	// ==================
	// = Project folders =
	// ==================
	//
	// Every folder the user has answered the folder-trust question for, either
	// way, so a mistaken answer can be seen and changed. Until 2026-09-24 the only
	// way to undo "Allow" was `defaults delete`, which the alpha.33 release notes
	// had to spell out.
	//
	// The checkbox flips the answer; the minus button *forgets* it, which is not
	// the same as refusing — the folder is asked about again the next time it is
	// opened. Reloaded whenever the pane appears, because the answers are given
	// in project windows, not here.
	private var answeredTableView: NSTableView!
	private var answered: [(path: String, allowed: Bool)] = []
	@objc dynamic private var canForget = false

	private static let kAnsweredAllowed = "allowed"
	private static let kAnsweredFolder  = "folder"

	private func reloadAnswered() {
		let trust = FolderTrust.shared
		answered = (trust.trustedFolders.map { ($0, true) } + trust.refusedFolders.map { ($0, false) })
			.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
		answeredTableView?.reloadData()
		canForget = answeredTableView != nil && answeredTableView.selectedRow != -1 && !answered.isEmpty
	}

	@objc private func forgetFolder(_ sender: Any?) {
		let row = answeredTableView.selectedRow
		guard row != -1, row < answered.count else { return }
		FolderTrust.shared.forget(answered[row].path)
		reloadAnswered()
		if !answered.isEmpty {
			answeredTableView.selectRowIndexes(IndexSet(integer: min(row, answered.count - 1)), byExtendingSelection: false)
		}
	}

	override func viewWillAppear() {
		super.viewWillAppear()
		reloadAnswered()
	}

	override var toolbarItemImage: NSImage? {
		NSImage(named: "Variables", inSameBundleAsClass: VariablesPreferences.self)
	}

	// @objc so the pane can be created from Objective-C by -init (the tests do);
	// without it -init reaches NSViewController's and the Swift runtime traps.
	@objc init() {
		super.init(nibName: nil, label: "Variables", image: nil)
		variables = (UserDefaults.standard.array(forKey: kUserDefaultsEnvironmentVariablesKey) as? [[String: Any]]) ?? []
	}

	private func saveVariables() {
		UserDefaults.standard.set(variables, forKey: kUserDefaultsEnvironmentVariablesKey)
	}

	@objc private func addVariable(_ sender: Any?) {
		let entry: [String: Any] = [
			kVariableKeyEnabled: true,
			kVariableKeyName:    "VARIABLE_NAME",
			kVariableKeyValue:   "variable value",
		]

		let pos = variablesTableView.selectedRow != -1 ? variablesTableView.selectedRow : variables.count
		variables.insert(entry, at: pos)
		saveVariables()
		variablesTableView.reloadData()
		variablesTableView.selectRowIndexes(IndexSet(integer: pos), byExtendingSelection: false)
		variablesTableView.editColumn(1, row: pos, with: nil, select: true)
	}

	@objc private func delete(_ sender: Any?) {
		var row = variablesTableView.selectedRow
		guard row != -1 else { return }

		if variablesTableView.editedColumn != -1 {
			variablesTableView.abortEditing()
			view.window?.makeFirstResponder(variablesTableView)
		}

		variables.remove(at: row)
		saveVariables()
		variablesTableView.reloadData()
		if row > 0 {
			row -= 1
		}

		if row < variables.count {
			variablesTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
			variablesTableView.scrollRowToVisible(row)
		}
	}

	override func commitEditing() -> Bool {
		let firstResponder = view.window?.firstResponder
		if let textView = firstResponder as? NSTextView, textView.delegate === variablesTableView {
			view.window?.makeFirstResponder(variablesTableView)
		}
		return true
	}

	private func column(identifier: String, title: String, editable: Bool, width: CGFloat, resizingMask: NSTableColumn.ResizingOptions) -> NSTableColumn {
		let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
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
		let enabledTableColumn = column(identifier: kVariableKeyEnabled, title: "",              editable: true, width: 16,  resizingMask: [])
		let nameTableColumn    = column(identifier: kVariableKeyName,    title: "Variable Name", editable: true, width: 140, resizingMask: .userResizingMask)
		let valueTableColumn   = column(identifier: kVariableKeyValue,   title: "Value",         editable: true, width: 200, resizingMask: .autoresizingMask)

		let enabledCell = NSButtonCell()
		enabledCell.setButtonType(.switch)
		enabledCell.controlSize = .small
		enabledCell.title = ""
		enabledTableColumn.dataCell = enabledCell

		variablesTableView = NSTableView(frame: .zero)
		variablesTableView.allowsColumnReordering = false
		variablesTableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
		variablesTableView.delegate = self
		variablesTableView.dataSource = self

		for tableColumn in [enabledTableColumn, nameTableColumn, valueTableColumn] {
			variablesTableView.addTableColumn(tableColumn)
		}

		let scrollView = NSScrollView(frame: .zero)
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers = true
		scrollView.borderType = .bezelBorder
		scrollView.documentView = variablesTableView

		let addButton    = NSButton(image: NSImage(named: NSImage.addTemplateName)!, target: self, action: #selector(addVariable(_:)))
		let removeButton = NSButton(image: NSImage(named: NSImage.removeTemplateName)!, target: self, action: #selector(delete(_:)))
		for button in [addButton, removeButton] {
			button.bezelStyle = .smallSquare
		}

		// Project folders
		let answeredTitle = NSTextField(labelWithString: "Project Folders")
		answeredTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

		let answeredNote = NSTextField(wrappingLabelWithString: "Folders whose own .tm_properties sets environment variables. An allowed folder’s variables are passed to bundle commands; the others are ignored. A folder’s editor settings apply either way. Removing a folder here means you are asked again the next time it is opened.")
		answeredNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		answeredNote.textColor = .secondaryLabelColor
		answeredNote.preferredMaxLayoutWidth = 582

		let allowedColumn = column(identifier: Self.kAnsweredAllowed, title: "Allowed", editable: true, width: 60, resizingMask: [])
		let folderColumn  = column(identifier: Self.kAnsweredFolder, title: "Folder", editable: false, width: 400, resizingMask: .autoresizingMask)
		let allowedCell = NSButtonCell()
		allowedCell.setButtonType(.switch)
		allowedCell.controlSize = .small
		allowedCell.title = ""
		allowedColumn.dataCell = allowedCell
		let folderCell = NSTextFieldCell()
		folderCell.lineBreakMode = .byTruncatingMiddle
		folderColumn.dataCell = folderCell

		answeredTableView = NSTableView(frame: .zero)
		answeredTableView.identifier = NSUserInterfaceItemIdentifier("answeredFolders")
		answeredTableView.allowsColumnReordering = false
		answeredTableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
		answeredTableView.delegate = self
		answeredTableView.dataSource = self
		answeredTableView.addTableColumn(allowedColumn)
		answeredTableView.addTableColumn(folderColumn)

		let answeredScrollView = NSScrollView(frame: .zero)
		answeredScrollView.hasVerticalScroller = true
		answeredScrollView.hasHorizontalScroller = false
		answeredScrollView.autohidesScrollers = true
		answeredScrollView.borderType = .bezelBorder
		answeredScrollView.documentView = answeredTableView

		let forgetButton = NSButton(image: NSImage(named: NSImage.removeTemplateName)!, target: self, action: #selector(forgetFolder(_:)))
		forgetButton.bezelStyle = .smallSquare
		forgetButton.identifier = NSUserInterfaceItemIdentifier("forgetFolder")
		forgetButton.toolTip = "Forget the answer for this folder, so it is asked about again"

		let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 622, height: 454))

		let views: [String: NSView] = [
			"scrollView":    scrollView,
			"add":           addButton,
			"remove":        removeButton,
			"answeredTitle": answeredTitle,
			"answeredNote":  answeredNote,
			"answered":      answeredScrollView,
			"forget":        forgetButton,
		]

		OakAddAutoLayoutViewsToSuperview(Array(views.values), contentView)

		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[scrollView(>=50)]-|", options: [], metrics: nil, views: views))
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[add(==20)]-(-1)-[remove(==add)]-(>=20)-|", options: [.alignAllTop, .alignAllBottom], metrics: nil, views: views))
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[answeredTitle]-|", options: [], metrics: nil, views: views))
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[answeredNote]-|", options: [], metrics: nil, views: views))
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[answered(>=50)]-|", options: [], metrics: nil, views: views))
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[forget(==20)]-(>=20)-|", options: [], metrics: nil, views: views))
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-[scrollView(>=50)]-8-[add(==19)]-20-[answeredTitle]-4-[answeredNote]-8-[answered(==120)]-8-[forget(==19)]-|", options: [], metrics: nil, views: views))

		removeButton.bind(.enabled, to: self, withKeyPath: "canRemove", options: nil)
		forgetButton.bind(.enabled, to: self, withKeyPath: "canForget", options: nil)
		reloadAnswered()

		view = contentView
	}

	// ========================
	// = NSTableView Delegate =
	// ========================

	func tableViewSelectionDidChange(_ notification: Notification) {
		if (notification.object as? NSTableView) === answeredTableView {
			canForget = answeredTableView.selectedRow != -1 && !answered.isEmpty
		} else {
			canRemove = variablesTableView.selectedRow != -1 && !variables.isEmpty
		}
	}

	// ==========================
	// = NSTableView DataSource =
	// ==========================

	func numberOfRows(in tableView: NSTableView) -> Int {
		tableView === answeredTableView ? answered.count : variables.count
	}

	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
		guard let identifier = tableColumn?.identifier.rawValue else { return nil }
		if tableView === answeredTableView {
			guard row < answered.count else { return nil }
			return identifier == Self.kAnsweredAllowed ? answered[row].allowed as NSNumber : (answered[row].path as NSString).abbreviatingWithTildeInPath
		}
		return variables[row][identifier]
	}

	func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
		guard let identifier = tableColumn?.identifier.rawValue else { return }
		if tableView === answeredTableView {
			guard identifier == Self.kAnsweredAllowed, row < answered.count else { return }
			let path = answered[row].path
			if (object as? NSNumber)?.boolValue == true {
				FolderTrust.shared.trust(path)
			} else {
				FolderTrust.shared.refuse(path)
			}
			reloadAnswered()
			return
		}
		var newValue = variables[row]
		newValue[identifier] = object
		// Editing a name or value re-enables a disabled row (the original's rule).
		if identifier != kVariableKeyEnabled, (newValue[kVariableKeyEnabled] as? Bool) != true {
			newValue[kVariableKeyEnabled] = true
		}
		variables[row] = newValue
		saveVariables()
	}
}
