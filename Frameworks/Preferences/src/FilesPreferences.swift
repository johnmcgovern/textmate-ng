import AppKit

@objc(FilesPreferences) final class FilesPreferences: PreferencesPane {
	init() {
		super.init(nibName: nil, label: "Files", image: NSImage(named: NSImage.multipleDocumentsName))

		OakStringListTransformer.createTransformer(withName: "OakLineEndingsSettingsTransformer", andObjectsArray: ["\\n", "\\r", "\\r\\n"])

		defaultsProperties = [
			"disableSessionRestore":         kUserDefaultsDisableSessionRestoreKey,
			"disableDocumentAtStartup":      kUserDefaultsDisableNewDocumentAtStartupKey,
			"disableDocumentAtReactivation": kUserDefaultsDisableNewDocumentAtReactivationKey,
		]

		tmProperties = [
			"encoding":    PWSettingsEncodingKey(),
			"lineEndings": PWSettingsLineEndingsKey(),
		]
	}

	@objc private func selectNewFileType(_ sender: NSMenuItem) {
		PWSettingsSet(PWSettingsFileTypeKey(), sender.representedObject as? String, "attr.untitled")
	}

	@objc private func selectUnknownFileType(_ sender: NSMenuItem) {
		PWSettingsSet(PWSettingsFileTypeKey(), sender.representedObject as? String, "attr.file.unknown-type")
	}

	override func loadView() {
		// Explicit types throughout: the Oak* constructors are unannotated C++
		// functions, so Swift imports them as implicitly-unwrapped optionals — and
		// an IUO decays to a plain Optional wherever the type is inferred.
		let restoreDocumentsCheckBox: NSButton        = OakCreateCheckBox("Open documents from last session")
		let createAtStartupCheckBox: NSButton         = OakCreateCheckBox("Create one at startup")
		let createOnActivationCheckBox: NSButton      = OakCreateCheckBox("Create one when re-activated")
		let newDocumentTypesPopUp: NSPopUpButton      = OakCreatePopUpButton(false, nil, nil)
		let unknownDocumentTypesPopUp: NSPopUpButton  = OakCreatePopUpButton(false, nil, nil)
		let encodingPopUp                             = OakEncodingPopUpButton()
		let lineEndingsPopUp: NSPopUpButton           = OakCreatePopUpButton(false, nil, nil)

		func label(_ text: String, _ font: NSFont? = nil) -> NSTextField {
			OakCreateLabel(text, font, .left, .byTruncatingMiddle)
		}

		// The ObjC++ original built these three through MenuBuilder's MBMenu, a
		// C++ designated-initializer aggregate Swift cannot construct. For a
		// title+tag menu the two are equivalent.
		for (index, title) in ["LF (recommended)", "CR (Mac Classic)", "CRLF (Windows)"].enumerated() {
			lineEndingsPopUp.menu?.addItem(withTitle: title, action: nil, keyEquivalent: "").tag = index
		}

		let smallFont = NSFont.messageFont(ofSize: NSFont.systemFontSize(for: .small))
		let gridView = NSGridView(views: [
			[label("At startup:"),             restoreDocumentsCheckBox],
			[NSGridCell.emptyContentView,      label("Hold shift (⇧) to bypass", smallFont)],
			[label("With no open documents:"), createAtStartupCheckBox],
			[NSGridCell.emptyContentView,      createOnActivationCheckBox],

			[],

			[label("New document type:"),      newDocumentTypesPopUp],
			[label("Unknown document type:"),  unknownDocumentTypesPopUp],
			[label("Encoding:"),               encodingPopUp],
			[label("Line endings:"),           lineEndingsPopUp],
		])

		let label = gridView.cell(atColumnIndex: 1, rowIndex: 0).contentView
		let sublabel = gridView.cell(atColumnIndex: 1, rowIndex: 1)
		sublabel.xPlacement = NSGridCell.Placement.none
		if let sublabelView = sublabel.contentView, let label {
			sublabel.customPlacementConstraints = [sublabelView.leadingAnchor.constraint(equalTo: label.leadingAnchor, constant: 19)]
		}

		for popUpButton in [unknownDocumentTypesPopUp, encodingPopUp, lineEndingsPopUp] as [NSView] {
			popUpButton.widthAnchor.constraint(equalTo: newDocumentTypesPopUp.widthAnchor).isActive = true
		}

		view = PWSetupGridView(gridView, [4])

		restoreDocumentsCheckBox.bind(.value,   to: self, withKeyPath: "disableSessionRestore",         options: [.valueTransformerName: NSValueTransformerName.negateBooleanTransformerName])
		createAtStartupCheckBox.bind(.value,    to: self, withKeyPath: "disableDocumentAtStartup",      options: [.valueTransformerName: NSValueTransformerName.negateBooleanTransformerName])
		createOnActivationCheckBox.bind(.value, to: self, withKeyPath: "disableDocumentAtReactivation", options: [.valueTransformerName: NSValueTransformerName.negateBooleanTransformerName])
		encodingPopUp.bind(NSBindingName("encoding"), to: self, withKeyPath: "encoding", options: nil)
		lineEndingsPopUp.bind(.selectedTag,     to: self, withKeyPath: "lineEndings",                   options: [.valueTransformerName: NSValueTransformerName("OakLineEndingsSettingsTransformer")])

		// ================================
		// = Create Language Pop-up Menus =
		// ================================

		guard let newDocumentTypesMenu = newDocumentTypesPopUp.menu, let unknownDocumentTypesMenu = unknownDocumentTypesPopUp.menu else { return }

		newDocumentTypesMenu.removeAllItems()
		unknownDocumentTypesMenu.removeAllItems()

		let promptItem = unknownDocumentTypesMenu.addItem(withTitle: "Prompt for type", action: #selector(selectUnknownFileType(_:)), keyEquivalent: "")
		promptItem.representedObject = nil
		promptItem.target = self
		unknownDocumentTypesMenu.addItem(NSMenuItem.separator())

		let grammars = PWGrammarList()
		guard !grammars.isEmpty else { return }

		let defaultNewFileType     = PWSettingsRawGet(PWSettingsFileTypeKey(), "attr.untitled")
		let defaultUnknownFileType = PWSettingsRawGet(PWSettingsFileTypeKey(), "attr.file.unknown-type")

		for grammar in grammars {
			guard let name = grammar["name"], let fileType = grammar["scope"] else { continue }

			let newItem = newDocumentTypesMenu.addItem(withTitle: name, action: #selector(selectNewFileType(_:)), keyEquivalent: "")
			newItem.representedObject = fileType
			newItem.target = self
			if fileType == defaultNewFileType {
				newDocumentTypesPopUp.select(newItem)
			}

			let unknownItem = unknownDocumentTypesMenu.addItem(withTitle: name, action: #selector(selectUnknownFileType(_:)), keyEquivalent: "")
			unknownItem.representedObject = fileType
			unknownItem.target = self
			if fileType == defaultUnknownFileType {
				unknownDocumentTypesPopUp.select(unknownItem)
			}
		}
	}
}
