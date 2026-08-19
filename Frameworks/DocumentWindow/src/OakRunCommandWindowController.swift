import AppKit

// Filter Through Command: a command line, a destination for its output, and
// Execute. The whole window is built in code — no nib — which is why it stands
// up in a test process.
//
// The one thing here that outlives the window is the output destination, which
// is written to user defaults as a raw integer. That integer is an `output::type`
// value, so it crosses the boundary as DWOutputType — the NS_ENUM split
// DWOutputType.h explains and DocumentWindowSupport.mm pins with static_assert.
// Nothing else in this file is C++: the one call that was,
// -filterDocumentThroughCommand:input:output:, is now DWFilterDocumentThroughCommand.

private let kUserDefaultsFilterOutputType = "filterOutputType"

@objc(OakRunCommandWindowController)
class OakRunCommandWindowController: NSWindowController, NSWindowDelegate {

	@objc static let sharedInstance = OakRunCommandWindowController()

	private let commandLabel: NSTextField
	private let resultLabel: NSTextField
	@objc private(set) var commandComboBox: NSComboBox
	@objc private(set) var resultPopUpButton: NSPopUpButton
	@objc private(set) var executeButton: NSButton
	private let cancelButton: NSButton

	private var objectController: NSObjectController!
	@objc dynamic var commandHistoryList: OakHistoryList<NSString>?

	private var outputTypeStorage: DWOutputType = .replaceInput

	// Zero is not stored: an absent `filterOutputType` key and an explicit
	// "replace input" are the same state, which is why setting it back to zero
	// *removes* the key rather than writing 0. Pinned by t_run_command_window.mm.
	@objc var outputType: DWOutputType {
		get { outputTypeStorage }
		set {
			guard outputTypeStorage != newValue else { return }

			outputTypeStorage = newValue
			resultPopUpButton.selectItem(withTag: newValue.rawValue)

			if newValue != .replaceInput {
				UserDefaults.standard.set(newValue.rawValue, forKey: kUserDefaultsFilterOutputType)
			} else {
				UserDefaults.standard.removeObject(forKey: kUserDefaultsFilterOutputType)
			}
		}
	}

	// `@objc`, not `@objc override`: NSWindowController's designated initializers
	// are init(window:) and init(coder:), so this is a new one. It has to exist
	// because +sharedInstance and the tests both use +new — Swift stops inheriting
	// -init the moment another initializer exists. Same shape as Find's.
	@objc init() {
		commandLabel      = OakCreateLabel("Command:", nil, .right, .byTruncatingMiddle)!
		commandComboBox   = OakCreateComboBox(nil)!
		resultLabel       = OakCreateLabel("Result:", nil, .right, .byTruncatingMiddle)!
		resultPopUpButton = OakCreatePopUpButton(false, nil, nil)!
		executeButton     = OakCreateButton("Execute", .rounded)!
		cancelButton      = OakCreateButton("Cancel", .rounded)!

		let panel = NSPanel(contentRect: .zero, styleMask: [ .titled, .closable, .resizable, .miniaturizable ], backing: .buffered, defer: false)
		super.init(window: panel)

		// The four destinations the menu offers, out of the eight DWOutputType has.
		// The tag *is* the output type, which is what lets them share one action.
		let outputOptions: [(title: String, keyEquivalent: String, outputOption: DWOutputType)] = [
			("Replace Input",      "1", .replaceInput),
			("Insert After Input", "2", .afterInput),
			("New Document",       "3", .newWindow),
			("Tool Tip",           "4", .toolTip),
		]

		let menu = resultPopUpButton.menu
		menu?.removeAllItems()
		for info in outputOptions {
			menu?.addItem(withTitle: info.title, action: #selector(takeOutputTypeFrom(_:)), keyEquivalent: info.keyEquivalent).tag = info.outputOption.rawValue
		}

		executeButton.action = #selector(execute(_:))
		cancelButton.action  = #selector(cancel(_:))

		objectController   = NSObjectController(content: self)
		// The array spelling, added to OakHistoryList for this port: the variadic
		// -initWithName:stackSize:defaultItems: is a C variadic and therefore
		// uncallable from Swift. The variadic one now funnels into the array one,
		// so there is still a single implementation.
		commandHistoryList = OakHistoryList(name: "Filter Through Command History", stackSize: 10, defaultItemsArray: [ "sort|uniq -c", "seq 100", "cat -n" ])

		window?.title    = "Filter Through Command"
		window?.delegate = self

		commandComboBox.bind(.value,         to: objectController!, withKeyPath: "content.commandHistoryList.head", options: nil)
		commandComboBox.bind(.contentValues, to: objectController!, withKeyPath: "content.commandHistoryList.list", options: nil)

		NotificationCenter.default.addObserver(self, selector: #selector(commandChanged(_:)), name: NSControl.textDidChangeNotification, object: commandComboBox)
		commandChanged(nil)

		let views: [String: NSView] = [
			"commandLabel": commandLabel,
			"command":      commandComboBox,
			"resultLabel":  resultLabel,
			"result":       resultPopUpButton,
			"execute":      executeButton,
			"cancel":       cancelButton,
		]

		guard let contentView = window?.contentView else { return }
		OakAddAutoLayoutViewsToSuperview(Array(views.values), contentView)

		var constraints: [NSLayoutConstraint] = []
		func constrain(_ format: String, _ options: NSLayoutConstraint.FormatOptions) {
			constraints.append(contentsOf: NSLayoutConstraint.constraints(withVisualFormat: format, options: options, metrics: nil, views: views))
		}

		constrain("H:|-[commandLabel]-[command(>=250)]-|", .alignAllFirstBaseline)
		constrain("H:|-[resultLabel(==commandLabel)]-[result]-(>=20)-|", .alignAllFirstBaseline)
		constrain("H:|-(>=20)-[cancel]-[execute]-|", .alignAllFirstBaseline)
		constrain("V:|-[command]-[result]", .alignAllLeft)
		constrain("V:[result]-[execute]-|", [])

		contentView.addConstraints(constraints)
		window?.defaultButtonCell = executeButton.cell as? NSButtonCell

		outputType = DWOutputType(rawValue: UserDefaults.standard.integer(forKey: kUserDefaultsFilterOutputType)) ?? .replaceInput
	}

	required init?(coder: NSCoder) {
		fatalError("OakRunCommandWindowController is built in code and reached through +sharedInstance")
	}

	@objc func takeOutputTypeFrom(_ sender: Any?) {
		if let tag = (sender as? NSMenuItem)?.tag, let type = DWOutputType(rawValue: tag) {
			outputType = type
		}
	}

	// Whitespace is empty: a command of spaces would otherwise run a shell for
	// nothing. The trim is the part worth keeping, and t_run_command_window.mm
	// pins it.
	@objc func commandChanged(_ notification: Notification?) {
		executeButton.isEnabled = OakNotEmptyString(commandComboBox.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
	}

	@objc func execute(_ sender: Any?) {
		guard objectController.commitEditing() else { return }

		DWFilterDocumentThroughCommand(commandComboBox.stringValue, outputType)

		close()
	}

	@objc func cancel(_ sender: Any?) {
		close()
	}
}
