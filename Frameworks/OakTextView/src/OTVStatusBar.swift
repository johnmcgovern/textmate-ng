import AppKit
import CoreText

// Ported from OTVStatusBar.mm. The two bundles::query calls went ahead of it into
// OTVStatusBarSupport (see that header for why they are not TMBundleItem's own
// query), leaving one std::clamp — which is Swift's min/max — as the whole of the
// remaining C++.
//
// Two things here are not translations:
//
//   * The tab-size menu is rebuilt with plain NSMenu calls. MenuBuilder's API is a
//     C++ DSL (MBMenu is a braced-initialiser list of designated initialisers), so
//     it cannot be called from Swift at all. t_status_bar.mm pins the resulting
//     menu title-by-title so "rebuilt" is checkable rather than asserted.
//   * -setKeyEquivalentCxxString: became -setKeyEquivalentString:, an ObjC-clean
//     spelling added to OakAppKit's NSMenuItem category for this port. It *binds*
//     the shortcut; -setInactiveKeyEquivalent: only draws the glyphs, and swapping
//     them would silently stop every grammar shortcut from firing.
//
// The class's ObjC face is the hand declaration in OTVStatusBar.h (rule 23), and
// tests reach the private controls through OakTextViewTesting.h.

private func OakCreateTextField(_ label: String) -> NSTextField {
	let res = NSTextField(frame: .zero)
	res.isBordered      = false
	res.isEditable      = false
	res.isSelectable    = false
	res.isBezeled       = false
	res.drawsBackground = false
	res.font            = OakStatusBarFont()
	res.stringValue     = label
	res.alignment       = .right
	res.cell?.lineBreakMode = .byTruncatingMiddle

	// This is to match the other controls in the status bar
	res.textColor = NSColor.secondaryLabelColor

	return res
}

private func OakCreateStatusBarPopUpButton(_ initialItemTitle: String? = nil, _ accessibilityLabel: String? = nil) -> NSPopUpButton {
	let res: NSPopUpButton = OakCreatePopUpButton(false, initialItemTitle, nil)
	res.font       = OakStatusBarFont()
	res.isBordered = false
	res.setAccessibilityLabel(accessibilityLabel)
	return res
}

private func OakCreateImageToggleButton(_ image: NSImage, _ accessibilityLabel: String) -> NSButton {
	let res = NSButton()
	res.setAccessibilityLabel(accessibilityLabel)
	res.setButtonType(.toggle)
	res.isBordered     = false
	res.image          = image
	res.imagePosition  = .imageOnly
	return res
}

@objc(OTVStatusBar)
class OTVStatusBar: NSVisualEffectView, @preconcurrency NSMenuDelegate {
	// None of these action selectors is declared in a header — they are dispatched
	// through the responder chain or against `target` — so #selector cannot name
	// them and NSSelectorFromString has to.
	private static let takeTabSizeFrom        = NSSelectorFromString("takeTabSizeFrom:")
	private static let showTabSizeSelectorPanel = NSSelectorFromString("showTabSizeSelectorPanel:")
	private static let setIndentWithTabs      = NSSelectorFromString("setIndentWithTabs:")
	private static let setIndentWithSpaces    = NSSelectorFromString("setIndentWithSpaces:")
	private static let takeGrammarUUIDFrom    = NSSelectorFromString("takeGrammarUUIDFrom:")
	private static let toggleMacroRecording   = NSSelectorFromString("toggleMacroRecording:")
	private static let nop                    = NSSelectorFromString("nop:")

	@objc var recordingTime: CGFloat = 0

	private var _recordingTimer: Timer?
	@objc var recordingTimer: Timer? {
		get { _recordingTimer }
		set {
			if _recordingTimer !== newValue {
				// Invalidated rather than dropped: an orphaned timer would keep firing
				// against the bar forever.
				_recordingTimer?.invalidate()
				_recordingTimer = newValue
			}
		}
	}

	@objc var selectionField: NSTextField!
	@objc var grammarPopUp: NSPopUpButton!
	@objc var tabSizePopUp: NSPopUpButton!
	@objc var bundleItemsPopUp: NSPopUpButton!
	@objc var symbolPopUp: NSPopUpButton!
	@objc var macroRecordingButton: NSButton!

	@objc weak var delegate: OTVStatusBarDelegate?

	private weak var _target: AnyObject?
	@objc var target: AnyObject? {
		get { _target }
		set {
			_target = newValue
			setupTabSizeMenu(self)
		}
	}

	override init(frame aRect: NSRect) {
		super.init(frame: aRect)

		let recordMacroImage = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { dstRect in
			NSColor.systemRed.set()
			NSBezierPath(ovalIn: dstRect.insetBy(dx: 2, dy: 2)).fill()
			return true
		}

		wantsLayer   = true
		material     = .titlebar
		blendingMode = .withinWindow
		state        = .followsWindowActiveState

		selectionField                = OakCreateTextField("1:1")
		grammarPopUp                  = OakCreateStatusBarPopUpButton("", "Grammar")
		tabSizePopUp                  = OakCreateStatusBarPopUpButton()
		tabSizePopUp.pullsDown        = true
		bundleItemsPopUp              = OakCreateStatusBarPopUpButton(nil, "Bundle Item")
		symbolPopUp                   = OakCreateStatusBarPopUpButton("", "Symbol")
		macroRecordingButton          = OakCreateImageToggleButton(recordMacroImage, "Record a macro")
		macroRecordingButton.action   = Self.toggleMacroRecording
		macroRecordingButton.toolTip  = "Click to start recording a macro"

		if let descriptor = selectionField.font?.fontDescriptor.addingAttributes([
			.featureSettings: [ [ NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType, NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector ] ]
		]) {
			selectionField.font = NSFont(descriptor: descriptor, size: 0)
		}

		setupTabSizeMenu(self)

		// ===========================
		// = Wrap/Clip Bundles PopUp =
		// ===========================

		let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
		item.image = NSImage(named: NSImage.actionTemplateName)
		if let cell = bundleItemsPopUp.cell as? NSPopUpButtonCell {
			cell.usesItemFromMenu = false
			cell.menuItem = item
		}

		let wrappedBundleItemsPopUpButton = NSView()
		OakAddAutoLayoutViewsToSuperview([bundleItemsPopUp], wrappedBundleItemsPopUpButton)
		wrappedBundleItemsPopUpButton.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:[popup]|", options: [], metrics: nil, views: [ "popup": bundleItemsPopUp! ]))
		wrappedBundleItemsPopUpButton.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[popup]|", options: [], metrics: nil, views: [ "popup": bundleItemsPopUp! ]))

		let topDivider   = OakCreateNSBoxSeparator()!
		let line         = OakCreateTextField("Line:")
		let dividerOne   = OakCreateNSBoxSeparator()!
		let dividerTwo   = OakCreateNSBoxSeparator()!
		let dividerThree = OakCreateNSBoxSeparator()!
		let dividerFour  = OakCreateNSBoxSeparator()!
		let dividerFive  = OakCreateNSBoxSeparator()!

		let views: [String: NSView] = [
			"topDivider":   topDivider,
			"line":         line,
			"selection":    selectionField,
			"dividerOne":   dividerOne,
			"grammar":      grammarPopUp,
			"dividerTwo":   dividerTwo,
			"items":        wrappedBundleItemsPopUpButton,
			"dividerThree": dividerThree,
			"tabSize":      tabSizePopUp,
			"dividerFour":  dividerFour,
			"symbol":       symbolPopUp,
			"dividerFive":  dividerFive,
			"recording":    macroRecordingButton,
		]

		OakAddAutoLayoutViewsToSuperview(Array(views.values), self)
		OakSetupKeyViewLoop([ self, grammarPopUp, tabSizePopUp, bundleItemsPopUp, symbolPopUp, macroRecordingButton ])

		selectionField.setContentHuggingPriority(.defaultLow, for: .horizontal)
		selectionField.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.defaultLow.rawValue + 2), for: .horizontal)
		selectionField.cell?.lineBreakMode = .byTruncatingTail

		grammarPopUp.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.defaultLow.rawValue + 1), for: .horizontal)

		symbolPopUp.setContentHuggingPriority(NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.defaultLow.rawValue - 1), for: .horizontal)
		symbolPopUp.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.defaultLow.rawValue - 1), for: .horizontal)

		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-10-[line]-[selection(>=50,<=225)]-8-[dividerOne(==1)]-2-[grammar(>=125@400,>=50,<=225)]-5-[dividerTwo(==1)]-2-[tabSize]-4-[dividerThree(==1)]-5-[items(==31)]-4-[dividerFour(==1)]-2-[symbol(>=125@450,>=50)]-5-[dividerFive(==1)]-6-[recording]-7-|", options: [], metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[topDivider]|", options: [], metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[topDivider(==1)]", options: [], metrics: nil, views: views))

		// Baseline align text-controls
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:[line]-[selection]-(>=1)-[grammar]-(>=1)-[tabSize]-(>=1)-[symbol]", options: .alignAllLastBaseline, metrics: nil, views: views))

		// Center non-text control
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:[selection]-(>=1)-[dividerOne]-(>=1)-[dividerTwo]-(>=1)-[dividerThree]-(>=1)-[items]-(>=1)-[dividerFour]-(>=1)-[dividerFive]-(>=1)-[recording]", options: .alignAllCenterY, metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-5-[dividerOne(==15,==dividerTwo,==dividerThree,==dividerFour,==dividerFive)]-5-|", options: [], metrics: nil, views: views))

		NotificationCenter.default.addObserver(self, selector: #selector(grammarPopUpButtonWillPopUp(_:)), name: NSPopUpButton.willPopUpNotification, object: grammarPopUp)
		NotificationCenter.default.addObserver(self, selector: #selector(bundleItemsPopUpButtonWillPopUp(_:)), name: NSPopUpButton.willPopUpNotification, object: bundleItemsPopUp)
		NotificationCenter.default.addObserver(self, selector: #selector(symbolPopUpButtonWillPopUp(_:)), name: NSPopUpButton.willPopUpNotification, object: symbolPopUp)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	// MenuBuilder's MBMenu is a braced list of C++ designated initialisers, so this
	// menu is assembled by hand. The shape is pinned in t_status_bar.mm.
	@objc func setupTabSizeMenu(_ sender: Any?) {
		let menu = NSMenu()

		// The caption row gets *no* action, not even -nop:. It is the pull-down's
		// title row, and NSPopUpButtonCell installs its own private action on it when
		// the menu is assigned below; giving it one here would take it away from
		// AppKit.
		menu.addItem(withTitle: "Current Indent", action: nil, keyEquivalent: "")

		menu.addItem(withTitle: "Indent Size", action: Self.nop, keyEquivalent: "")
		for size in [ 2, 3, 4, 8 ] {
			let item = menu.addItem(withTitle: "\(size)", action: Self.takeTabSizeFrom, keyEquivalent: "")
			item.tag = size
			item.indentationLevel = 1
			item.target = _target
		}
		let other = menu.addItem(withTitle: "Other…", action: Self.showTabSizeSelectorPanel, keyEquivalent: "")
		other.indentationLevel = 1
		other.target = _target

		menu.addItem(.separator())

		menu.addItem(withTitle: "Indent Using", action: Self.nop, keyEquivalent: "")
		for (title, action) in [ ("Tabs", Self.setIndentWithTabs), ("Spaces", Self.setIndentWithSpaces) ] {
			let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
			item.indentationLevel = 1
			item.target = _target
		}

		tabSizePopUp.menu = menu
	}

	@objc func updateMacroRecordingAnimation(_ aTimer: Timer?) {
		let fraction = min(max(0.70 + 0.30 * cos(Double.pi + recordingTime), 0.00), 1.0)
		macroRecordingButton.alphaValue = fraction
		recordingTime += 0.075
	}

	@objc func grammarPopUpButtonWillPopUp(_ aNotification: Notification?) {
		guard let grammarMenu = grammarPopUp.menu else {
			return
		}
		grammarMenu.removeAllItems()

		let grammars = OTVStatusBarSupport.grammarsForMenu()

		for grammar in grammars {
			if !grammar.isHiddenFromUser {
				let item = grammarMenu.addItem(withTitle: grammar.name ?? "", action: Self.takeGrammarUUIDFrom, keyEquivalent: "")
				// -setKeyEquivalentString:, not -setInactiveKeyEquivalent:. The first
				// *binds* the shortcut; the second only draws the glyphs. These items
				// are meant to fire on their key equivalent. nil is what the ObjC++
				// spelled NULL_STR, and clears rather than binds.
				item.setKeyEquivalentString(grammar.keyEquivalent)
				item.representedObject = grammar.uuidString
				item.target = _target
			}
		}

		// The emptiness test is on the *unfiltered* list, as it was on the multimap:
		// a bundle set whose grammars are all hidden yields an empty menu rather than
		// "No Grammars Loaded".
		if grammars.count == 0 {
			grammarMenu.addItem(withTitle: "No Grammars Loaded", action: Self.nop, keyEquivalent: "")
		}

		grammarMenu.update()

		for item in grammarMenu.items {
			if item.state == .on {
				grammarPopUp.select(item)
			}
		}
	}

	@objc func bundleItemsPopUpButtonWillPopUp(_ aNotification: Notification?) {
		delegate?.showBundleItemSelector(bundleItemsPopUp)
	}

	@objc func symbolPopUpButtonWillPopUp(_ aNotification: Notification?) {
		delegate?.showSymbolSelector(symbolPopUp)
	}

	// ===========
	// = Actions =
	// ===========

	@objc func showBundlesMenu(_ sender: Any?) {
		bundleItemsPopUp.performClick(self)
	}

	// ==============
	// = Properties =
	// ==============

	private var _selectionString: String?
	@objc var selectionString: String? {
		get { _selectionString }
		set {
			guard _selectionString != newValue else {
				return
			}
			_selectionString = newValue

			// A display transformation only — the property keeps what it was handed.
			// "&" separates multiple carets and "x" marks a rectangular selection.
			//
			// `?? ""` is the one place this does not reproduce the ObjC++ exactly. There
			// a nil would have reached -setStringValue: as nil, which is declared
			// non-null; the guard above means that is only reachable by going *back* to
			// nil from a real value, and an empty field is what that was meant to show.
			var display = newValue?.replacingOccurrences(of: "&", with: ", ")
			display = display?.replacingOccurrences(of: "x", with: "×")
			selectionField.stringValue = display ?? ""
		}
	}

	private var _grammarName: String?
	@objc var grammarName: String? {
		get { _grammarName }
		set {
			guard _grammarName != newValue else {
				return
			}
			_grammarName = newValue
			grammarPopUp.menu?.removeAllItems()
			grammarPopUp.addItem(withTitle: newValue ?? "(no grammar)")
		}
	}

	private var _symbolName: String?
	@objc var symbolName: String? {
		get { _symbolName }
		set {
			guard _symbolName != newValue else {
				return
			}
			_symbolName = newValue
			symbolPopUp.menu?.removeAllItems()
			symbolPopUp.addItem(withTitle: newValue ?? "Symbols")
		}
	}

	// NSString rather than String, and `===` rather than `==`, because the ObjC++
	// guarded this one on *pointer* identity while its two neighbours used
	// -isEqualToString:. That is observable: re-setting an equal-but-distinct file
	// type re-derives grammarName, which matters after the user has picked a
	// grammar by hand. Kept as it was rather than tidied into value equality.
	private var _fileType: NSString?
	@objc var fileType: NSString? {
		get { _fileType }
		set {
			guard _fileType !== newValue else {
				return
			}
			_fileType = newValue
			if let name = OTVStatusBarSupport.grammarName(forFileType: newValue as String?) {
				grammarName = name
			}
		}
	}

	private var _recordingMacro: Bool = false
	@objc var recordingMacro: Bool {
		// rule 4: the getter is spelled isRecordingMacro while the setter is
		// setRecordingMacro:. Swift generates only one of those unless told both.
		@objc(isRecordingMacro) get { _recordingMacro }
		@objc(setRecordingMacro:) set {
			_recordingMacro = newValue
			if _recordingMacro {
				recordingTimer = Timer.scheduledTimer(timeInterval: 0.02, target: self, selector: #selector(updateMacroRecordingAnimation(_:)), userInfo: nil, repeats: true)
			}
			else {
				recordingTimer = nil
				recordingTime = 0
				updateMacroRecordingAnimation(nil)
			}
		}
	}

	@objc var softTabs: Bool = false {
		didSet {
			updateTabSettings()
		}
	}

	@objc var tabSize: UInt = 0 {
		didSet {
			updateTabSettings()
		}
	}

	private func updateTabSettings() {
		// U+2003 EM SPACE, written as an escape on purpose: as a literal it is
		// invisible in a diff and indistinguishable from a run of spaces.
		tabSizePopUp.title = "\(softTabs ? "Soft Tabs" : "Tab Size"):\u{2003}\(tabSize)"
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
		// The timer setter is main-actor-isolated and deinit is not; a view is
		// deallocated on the main thread.
		MainActor.assumeIsolated {
			recordingTimer = nil
		}
	}
}
