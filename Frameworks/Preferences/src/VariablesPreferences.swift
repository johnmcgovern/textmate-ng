import AppKit

private let kVariableKeyEnabled = "enabled"
private let kVariableKeyName    = "name"
private let kVariableKeyValue   = "value"

@objc(VariablesPreferences) final class VariablesPreferences: PreferencesPane, NSTableViewDelegate, NSTableViewDataSource {
	private var variablesTableView: NSTableView!
	private var variables: [[String: Any]] = []
	@objc dynamic private var canRemove = false

	override var toolbarItemImage: NSImage? {
		NSImage(named: "Variables", inSameBundleAsClass: VariablesPreferences.self)
	}

	init() {
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

		let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 622, height: 454))

		let views: [String: NSView] = [
			"scrollView": scrollView,
			"add":        addButton,
			"remove":     removeButton,
		]

		OakAddAutoLayoutViewsToSuperview(Array(views.values), contentView)

		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[scrollView(>=50)]-|", options: [], metrics: nil, views: views))
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[add(==20)]-(-1)-[remove(==add)]-(>=20)-|", options: [.alignAllTop, .alignAllBottom], metrics: nil, views: views))
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-[scrollView(>=50)]-8-[add(==19)]-|", options: [], metrics: nil, views: views))

		removeButton.bind(.enabled, to: self, withKeyPath: "canRemove", options: nil)

		view = contentView
	}

	// ========================
	// = NSTableView Delegate =
	// ========================

	func tableViewSelectionDidChange(_ notification: Notification) {
		canRemove = variablesTableView.selectedRow != -1 && !variables.isEmpty
	}

	// ==========================
	// = NSTableView DataSource =
	// ==========================

	func numberOfRows(in tableView: NSTableView) -> Int {
		variables.count
	}

	func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
		guard let identifier = tableColumn?.identifier.rawValue else { return nil }
		return variables[row][identifier]
	}

	func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
		guard let identifier = tableColumn?.identifier.rawValue else { return }
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
