import AppKit

// Ported from OakDocumentView.mm — this framework's integration point. It owns the
// gutter, the status bar and the text view, and answers four protocols on their
// behalf.
//
// The C++ went ahead of it into OakDocumentViewSupport (cfe7f95a, 7e7f7545) for
// three separate reasons: settings_t::set takes a std::string, bundles deals in
// shared_ptr, and -[OakTextView theme] is a *property* of type theme_ptr that
// Swift cannot read at all. What was left here is std::min and oak::contains,
// which are one stdlib call each.
//
// GutterViewDelegate came across whole, which contradicts what this port was
// planned around. -lineRecordForPosition: and -lineFragmentForLine:column: return
// GVLineRecord, a C++ struct *by value*, and the plan was an ObjC++ category for
// them. It is not needed: the importer brings trivially-copyable C++ structs into
// Swift, so the two methods are declared, called and their fields read here. Rule
// 17 is about C++ types Swift cannot *represent*; a plain aggregate is not one.
//
// GutterView still cannot be ported, but for a different reason than assumed —
// rule 20, not rule 17. Its state is C++ ivars: a std::vector<data_source_t>, a
// std::string and two std::vector<CGRect>. A category can add methods to a Swift
// class but never storage.
//
// The class's ObjC face is the hand declaration in OakDocumentView.h (rule 23).

private let kUserDefaultsLineNumberScaleFactorKey = "lineNumberScaleFactor"
private let kUserDefaultsLineNumberFontNameKey    = "lineNumberFontName"

private let kBookmarksColumnIdentifier = "bookmarks"
private let kFoldingsColumnIdentifier  = "foldings"

private let kUserDefaultsDisableLineNumbersKey = "DocumentView Disable Line Numbers"

@objc(OakDocumentView)
class OakDocumentView: NSView, NSAccessibilityGroup, @preconcurrency NSMenuItemValidation, @preconcurrency GutterViewDelegate, @preconcurrency GutterViewColumnDataSource, @preconcurrency GutterViewColumnDelegate, @preconcurrency OTVStatusBarDelegate {
	// Dispatched through the responder chain rather than declared anywhere, so
	// #selector cannot name them.
	private static let nop = NSSelectorFromString("nop:")

	private var gutterScrollView: NSScrollView!
	private var gutterView: GutterView!
	// The NSNull is the ObjC++'s own sentinel and is load-bearing: it caches "there
	// is no image by this name" so the lookup and its NSLog happen once, not on
	// every redraw of every line.
	private var gutterImages: [String: Any] = [:]

	private var gutterDividerView: OakBackgroundFillView!
	private var textScrollView: NSScrollView!

	private var topAuxiliaryViews: [NSView] = []
	private var bottomAuxiliaryViews: [NSView] = []

	@IBOutlet @objc var tabSizeSelectorPanel: NSPanel?

	// Get-only computed rather than `@objc private(set)`: the latter still emits a
	// -setTextView: entry point, and t_document_view.mm pins that the property is
	// readonly from ObjC. Same for the status bar, which the Testing category also
	// declares readonly.
	private var _textView: OakTextView!
	@objc var textView: OakTextView! { _textView }

	private var _statusBar: OTVStatusBar?
	@objc var statusBar: OTVStatusBar? { _statusBar }

	@objc var observedKeys: [String] = []

	override init(frame aRect: NSRect) {
		super.init(frame: aRect)

		setAccessibilityRole(.group)
		setAccessibilityLabel("Editor")

		_textView = OakTextView(frame: .zero)
		textView.autoresizingMask = [.width, .height]

		textScrollView = NSScrollView(frame: .zero)
		textScrollView.hasVerticalScroller      = true
		textScrollView.verticalScrollElasticity = .allowed
		textScrollView.hasHorizontalScroller    = true
		textScrollView.autohidesScrollers       = true
		textScrollView.borderType               = .noBorder
		textScrollView.documentView             = textView

		gutterView = GutterView(frame: .zero)
		gutterView.partnerView = textView
		gutterView.delegate    = self
		gutterView.insertColumn(withIdentifier: kBookmarksColumnIdentifier, atPosition: 0, dataSource: self, delegate: self)
		gutterView.insertColumn(withIdentifier: kFoldingsColumnIdentifier, atPosition: 2, dataSource: self, delegate: self)
		if UserDefaults.standard.bool(forKey: kUserDefaultsDisableLineNumbersKey) {
			gutterView.setVisibility(false, forColumnWithIdentifier: GVLineNumbersColumnIdentifier)
		}
		gutterView.translatesAutoresizingMaskIntoConstraints = false

		gutterScrollView = NSScrollView(frame: .zero)
		gutterScrollView.setAccessibilityElement(false)
		gutterScrollView.borderType   = .noBorder
		gutterScrollView.documentView = gutterView

		for attribute: NSLayoutConstraint.Attribute in [ .left, .top, .right ] {
			gutterScrollView.contentView.addConstraint(NSLayoutConstraint(item: gutterView!, attribute: attribute, relatedBy: .equal, toItem: gutterScrollView.contentView, attribute: attribute, multiplier: 1.0, constant: 0.0))
		}

		gutterDividerView = OakCreateVerticalLine(.none)

		let statusBar = OTVStatusBar(frame: .zero)
		statusBar.delegate = self
		statusBar.target   = self
		_statusBar = statusBar

		OakAddAutoLayoutViewsToSuperview([ gutterScrollView, gutterDividerView, textScrollView, statusBar ], self)
		OakSetupKeyViewLoop([ self, textView, statusBar ])

		document = OakDocument(string: "", fileType: "text.plain", customName: "placeholder")

		observedKeys = [ "selectionString", "symbol", "recordingMacro", "themeUUID" ]
		for keyPath in observedKeys {
			textView.addObserver(self, forKeyPath: keyPath, options: .initial, context: nil)
		}
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func updateConstraints() {
		removeConstraints(constraints)
		super.updateConstraints()

		var stackedViews: [NSView] = []
		stackedViews.append(contentsOf: topAuxiliaryViews)
		stackedViews.append(gutterScrollView)
		stackedViews.append(contentsOf: bottomAuxiliaryViews)

		if let statusBar {
			stackedViews.append(statusBar)
			// The binding is named "_statusBar" because the ObjC++ used
			// NSDictionaryOfVariableBindings on the ivar, and the format string
			// still says so.
			addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[_statusBar]|", options: [], metrics: nil, views: [ "_statusBar": statusBar ]))
		}

		let views: [String: NSView] = [
			"gutterScrollView":  gutterScrollView,
			"gutterView":        gutterView,
			"gutterDividerView": gutterDividerView,
			"textScrollView":    textScrollView,
		]

		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[gutterScrollView(==gutterView)][gutterDividerView][textScrollView(>=100)]|", options: [.alignAllTop, .alignAllBottom], metrics: nil, views: views))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[topView]", options: [], metrics: nil, views: [ "topView": stackedViews[0] ]))
		addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[bottomView]|", options: [], metrics: nil, views: [ "bottomView": stackedViews[stackedViews.count-1] ]))

		for i in 0..<(stackedViews.count-1) {
			addConstraint(NSLayoutConstraint(item: stackedViews[i], attribute: .bottom, relatedBy: .equal, toItem: stackedViews[i+1], attribute: .top, multiplier: 1, constant: 0))
		}

		for views in [ topAuxiliaryViews, bottomAuxiliaryViews ] {
			for view in views {
				addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[view]|", options: [], metrics: nil, views: [ "view": view ]))
			}
		}
	}

	private var _hideStatusBar: Bool = false
	@objc var hideStatusBar: Bool {
		get { _hideStatusBar }
		set {
			guard _hideStatusBar != newValue else {
				return
			}

			_hideStatusBar = newValue
			if _hideStatusBar {
				// Destroyed rather than hidden, so nothing may cache it across a toggle.
				_statusBar?.removeFromSuperview()
				_statusBar?.delegate = nil
				_statusBar?.target = nil
				_statusBar = nil
			}
			else {
				let statusBar = OTVStatusBar(frame: .zero)
				statusBar.delegate = self
				statusBar.target   = self
				_statusBar = statusBar

				OakAddAutoLayoutViewsToSuperview([ statusBar ], self)
			}
			needsUpdateConstraints = true
		}
	}

	@objc var lineHeight: CGFloat {
		// A nil font messages nil in the ObjC++ and yields zero from every term.
		guard let font = textView.font else {
			return 0
		}
		return round(min(1.5 * font.capHeight, font.ascender - font.descender + font.leading))
	}

	private func gutterImage(_ aName: String) -> NSImage? {
		if let cached = gutterImages[aName] {
			return cached as? NSImage
		}

		var image: NSImage? = aName.hasPrefix("/") ? NSImage(contentsOfFile: aName) : NSImage(named: aName, inSameBundleAsClass: Self.self)
		if image == nil && !aName.hasPrefix("/") && !aName.hasSuffix(" Template") {
			image = NSImage(named: aName + " Template", inSameBundleAsClass: Self.self)
		}

		if aName.hasPrefix("/") && (aName as NSString).deletingPathExtension.hasSuffix(" Template") {
			image?.isTemplate = true
		}

		let res: Any
		if let found = image {
			let imageWidth  = found.size.width
			let imageHeight = found.size.height

			let viewWidth  = widthForColumn(withIdentifier: nil)
			let viewHeight = lineHeight

			let copy = found.copy() as! NSImage
			if imageWidth / imageHeight < viewWidth / viewHeight {
				copy.size = NSSize(width: round(viewHeight * imageWidth / imageHeight), height: viewHeight)
			}
			else {
				copy.size = NSSize(width: viewWidth, height: round(viewWidth * imageHeight / imageWidth))
			}
			res = copy
		}
		else {
			res = NSNull()
			NSLog("%@ no image named ‘%@’", "gutterImage:", aName)
		}

		gutterImages[aName] = res
		return res as? NSImage
	}

	@objc func updateGutterViewFont(_ sender: Any?) {
		let scaleFactor = UserDefaults.standard.float(forKey: kUserDefaultsLineNumberScaleFactorKey) != 0 ? CGFloat(UserDefaults.standard.float(forKey: kUserDefaultsLineNumberScaleFactorKey)) : 0.8
		let lineNumberFontName = UserDefaults.standard.string(forKey: kUserDefaultsLineNumberFontNameKey) ?? textView.font?.fontName

		gutterImages = [:] // force image sizes to be recalculated
		if let lineNumberFontName {
			gutterView.lineNumberFont = NSFont(name: lineNumberFontName, size: round(scaleFactor * (textView.font?.pointSize ?? 0) * textView.fontScaleFactor))
		}
		gutterView.reloadData(self)
	}

	@objc func makeTextLarger(_ sender: Any?) {
		textView.fontScaleFactor += 0.1
		updateGutterViewFont(self)
	}

	@objc func makeTextSmaller(_ sender: Any?) {
		if textView.fontScaleFactor > 0.1 {
			textView.fontScaleFactor -= 0.1
			updateGutterViewFont(self)
		}
	}

	@objc func makeTextStandardSize(_ sender: Any?) {
		textView.fontScaleFactor = 1
		updateGutterViewFont(self)
	}

	@objc func changeFont(_ sender: NSFontManager?) {
		let defaultFont = NSFont.userFixedPitchFont(ofSize: 0)
		if let newFont = sender?.convert(textView.font ?? defaultFont!) {
			// nil is NULL_STR: matching the default font removes the key rather than
			// recording the default's name.
			let fontName = newFont.fontName == defaultFont?.fontName ? nil : newFont.fontName
			OakDocumentViewSupport.setFontName(fontName)
			OakDocumentViewSupport.setFontSize(newFont.pointSize)
			textView.font = newFont
			updateGutterViewFont(self)
		}
	}

	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		if keyPath == "selectionString" {
			let str = textView.value(forKey: "selectionString") as? String
			gutterView.setHighlightedRangeString(str ?? "1")
			statusBar?.selectionString = str
			symbolChooser?.selectionString = str
		}
		else if keyPath == "symbol" {
			statusBar?.symbolName = textView.symbol
		}
		else if keyPath == "recordingMacro" {
			statusBar?.recordingMacro = textView.isRecordingMacro
		}
		else if keyPath == "fileType" {
			statusBar?.fileType = document?.fileType as NSString?
		}
		else if keyPath == "tabSize" {
			statusBar?.tabSize = document?.tabSize ?? 0
		}
		else if keyPath == "softTabs" {
			statusBar?.softTabs = document?.softTabs ?? false
		}
		else if keyPath == "themeUUID" {
			updateStyle()
		}
	}

	deinit {
		MainActor.assumeIsolated {
			for keyPath in observedKeys {
				textView.removeObserver(self, forKeyPath: keyPath)
			}
			NotificationCenter.default.removeObserver(self)

			document = nil
			symbolChooser = nil
		}
	}

	private static let documentKeys = [ "fileType", "tabSize", "softTabs" ]

	private var _document: OakDocument?
	@objc var document: OakDocument? {
		get { _document }
		set {
			let oldDocument = _document
			if let oldDocument {
				for key in Self.documentKeys {
					oldDocument.removeObserver(self, forKeyPath: key)
				}
				NotificationCenter.default.removeObserver(self, name: NSNotification.Name.OakDocumentMarksDidChange, object: oldDocument)
			}

			newValue?.loadModal(for: window, completionHandler: nil)

			_document = newValue
			if let document = _document {
				NotificationCenter.default.addObserver(self, selector: #selector(documentMarksDidChange(_:)), name: NSNotification.Name.OakDocumentMarksDidChange, object: document)
				for key in Self.documentKeys {
					document.addObserver(self, forKeyPath: key, options: .initial, context: nil)
				}
			}

			textView.document = _document
			gutterView.reloadData(self)
			updateStyle()

			if let symbolChooser {
				symbolChooser.tmDocument      = _document
				symbolChooser.selectionString = textView.selectionString
			}

			oldDocument?.close()
		}
	}

	private func updateStyle() {
		// nil is the `if(theme_ptr theme = _textView.theme)` the ObjC++ opened with.
		guard let styles = OakDocumentViewSupport.gutterStyles(for: textView, fileType: document?.fileType) else {
			return
		}

		textScrollView.backgroundColor  = styles.documentBackground
		textScrollView.scrollerKnobStyle = styles.isDark ? .light : .dark

		textView.ibeamCursor = NSCursor.iBeam

		updateGutterViewFont(self) // trigger update of gutter view’s line number font

		gutterView.foregroundColor           = styles.foreground
		gutterView.backgroundColor           = styles.background
		gutterView.iconColor                 = styles.icons
		gutterView.iconHoverColor            = styles.iconsHover
		gutterView.iconPressedColor          = styles.iconsPressed
		gutterView.selectionForegroundColor  = styles.selectionForeground
		gutterView.selectionBackgroundColor  = styles.selectionBackground
		gutterView.selectionIconColor        = styles.selectionIcons
		gutterView.selectionIconHoverColor   = styles.selectionIconsHover
		gutterView.selectionIconPressedColor = styles.selectionIconsPressed
		gutterView.selectionBorderColor      = styles.selectionBorder
		gutterScrollView.backgroundColor     = gutterView.backgroundColor
		gutterDividerView.activeBackgroundColor = styles.divider

		gutterView.needsDisplay = true
	}

	@objc func toggleLineNumbers(_ sender: Any?) {
		let isVisibleFlag = !gutterView.visibilityForColumn(withIdentifier: GVLineNumbersColumnIdentifier)
		gutterView.setVisibility(isVisibleFlag, forColumnWithIdentifier: GVLineNumbersColumnIdentifier)
		if isVisibleFlag {
			// Removed rather than set to NO, so the default stays the absence of a value.
			UserDefaults.standard.removeObject(forKey: kUserDefaultsDisableLineNumbersKey)
		}
		else {
			UserDefaults.standard.set(true, forKey: kUserDefaultsDisableLineNumbersKey)
		}
	}

	@objc func validateMenuItem(_ aMenuItem: NSMenuItem) -> Bool {
		if aMenuItem.action == #selector(toggleLineNumbers(_:)) {
			aMenuItem.title = gutterView.visibilityForColumn(withIdentifier: GVLineNumbersColumnIdentifier) ? "Hide Line Numbers" : "Show Line Numbers"
		}
		else if aMenuItem.action == #selector(takeTabSizeFrom(_:)) {
			aMenuItem.state = textView.tabSize == aMenuItem.tag ? .on : .off
		}
		else if aMenuItem.action == #selector(showTabSizeSelectorPanel(_:)) {
			let predefined: [Int] = [ 2, 3, 4, 8 ]
			if predefined.contains(Int(textView.tabSize)) {
				aMenuItem.title = "Other…"
				aMenuItem.state = .off
			}
			else {
				aMenuItem.setDynamicTitle("Other (\(textView.tabSize))…")
				aMenuItem.state = .on
			}
		}
		else if aMenuItem.action == #selector(setIndentWithTabs(_:)) {
			aMenuItem.state = textView.softTabs ? .off : .on
		}
		else if aMenuItem.action == #selector(setIndentWithSpaces(_:)) {
			aMenuItem.state = textView.softTabs ? .on : .off
		}
		else if aMenuItem.action == #selector(takeGrammarUUIDFrom(_:)) {
			let uuidString = aMenuItem.representedObject as? String
			// nil covers both "no such item" and "declares no grammar scope"; the
			// ObjC++ left the state untouched in the first case and compared against
			// NULL_STR in the second, which no file type equals.
			if let scope = OakDocumentViewSupport.grammarScopeForBundleItem(withUUIDString: uuidString) {
				aMenuItem.state = document?.fileType == scope ? .on : .off
			}
		}
		return true
	}

	// ===================
	// = Auxiliary Views =
	// ===================

	@objc func addAuxiliaryView(_ aView: NSView, atEdge anEdge: NSRectEdge) {
		if anEdge == .minY {
			bottomAuxiliaryViews.append(aView)
		}
		else {
			topAuxiliaryViews.append(aView)
		}
		OakAddAutoLayoutViewsToSuperview([ aView ], self)
		needsUpdateConstraints = true
	}

	@objc func removeAuxiliaryView(_ aView: NSView) {
		if let index = topAuxiliaryViews.firstIndex(of: aView) {
			topAuxiliaryViews.remove(at: index)
		}
		else if let index = bottomAuxiliaryViews.firstIndex(of: aView) {
			bottomAuxiliaryViews.remove(at: index)
		}
		else {
			// The early return matters: without it a view belonging to somebody else
			// would be pulled out of its own superview.
			return
		}
		aView.removeFromSuperview()
		needsUpdateConstraints = true
	}

	// ======================
	// = Pasteboard History =
	// ======================

	@objc func showClipboardHistory(_ sender: Any?) {
		let chooser = OakPasteboardChooser.sharedChooser(for: OakPasteboard.general)!
		chooser.action = NSSelectorFromString("paste:")
		chooser.showWindowRelative(toFrame: window!.convertToScreen(textView.convert(textView.visibleRect, to: nil)))
	}

	@objc func showFindHistory(_ sender: Any?) {
		let chooser = OakPasteboardChooser.sharedChooser(for: OakPasteboard.find)!
		chooser.action          = NSSelectorFromString("findNext:")
		chooser.alternateAction = NSSelectorFromString("orderFrontFindPanelForProject:")
		chooser.showWindowRelative(toFrame: window!.convertToScreen(textView.convert(textView.visibleRect, to: nil)))
	}

	// ==================
	// = Symbol Chooser =
	// ==================

	@objc func selectAndCenter(_ aSelectionString: String?) {
		textView.selectionString = aSelectionString
		textView.centerSelectionInVisibleArea(self)
	}

	private var _symbolChooser: SymbolChooser?
	@objc var symbolChooser: SymbolChooser? {
		get { _symbolChooser }
		set {
			guard _symbolChooser !== newValue else {
				return
			}

			if let symbolChooser = _symbolChooser {
				NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: symbolChooser.window)
				symbolChooser.target     = nil
				symbolChooser.tmDocument = nil
			}

			_symbolChooser = newValue
			if let symbolChooser = _symbolChooser {
				symbolChooser.target          = self
				symbolChooser.action          = #selector(symbolChooserDidSelectItems(_:))
				symbolChooser.filterString    = ""
				symbolChooser.tmDocument      = document
				symbolChooser.selectionString = textView.selectionString

				NotificationCenter.default.addObserver(self, selector: #selector(symbolChooserWillClose(_:)), name: NSWindow.willCloseNotification, object: symbolChooser.window)
			}
		}
	}

	@objc func symbolChooserWillClose(_ aNotification: Notification?) {
		symbolChooser = nil
	}

	@objc func showSymbolChooser(_ sender: Any?) {
		symbolChooser = SymbolChooser.sharedInstance
		symbolChooser?.showWindowRelative(toFrame: window!.convertToScreen(textView.convert(textView.visibleRect, to: nil)))
	}

	@objc func symbolChooserDidSelectItems(_ sender: Any?) {
		guard let items = (sender as? OakChooser)?.selectedItems as? [AnyObject] else {
			return
		}
		for item in items {
			selectAndCenter(item.selectionString)
		}
	}

	// =======================
	// = Status bar delegate =
	// =======================

	@objc func takeGrammarUUIDFrom(_ sender: Any?) {
		OakDocumentViewSupport.performBundleItem(withUUIDString: (sender as AnyObject).representedObject as? String, in: textView)
	}

	@objc func goToSymbol(_ sender: Any?) {
		selectAndCenter((sender as AnyObject).representedObject as? String)
	}

	@objc func showSymbolSelector(_ symbolPopUp: NSPopUpButton) {
		guard let symbolMenu = symbolPopUp.menu else {
			return
		}
		symbolMenu.removeAllItems()

		var index = 0
		for entry in OakDocumentViewSupport.symbols(in: document, relativeToSelection: textView.selectionString) {
			let symbol = entry.symbol
			if symbol == "-" {
				symbolMenu.addItem(.separator())
			}
			else {
				var indent = 0
				let chars = Array(symbol.utf16)
				while indent < chars.count && chars[indent] == 0x2003 { // Em-space
					indent += 1
				}

				let item = symbolMenu.addItem(withTitle: String(decoding: chars[indent...], as: UTF16.self), action: #selector(goToSymbol(_:)), keyEquivalent: "")
				item.indentationLevel = indent
				item.target = self
				item.representedObject = entry.positionString
			}

			// Counted for *every* symbol including separators, which is why the
			// selection below is index-1 rather than index.
			if entry.atOrBeforeCaret {
				index += 1
			}
		}

		if symbolMenu.numberOfItems == 0 {
			symbolMenu.addItem(withTitle: "No symbols to show for current document.", action: Self.nop, keyEquivalent: "")
		}

		symbolPopUp.selectItem(at: index != 0 ? index-1 : 0)
	}

	@objc func showBundlesMenu(_ sender: Any?) {
		guard let statusBar else {
			NSSound.beep()
			return
		}
		NSApp.sendAction(#selector(showBundlesMenu(_:)), to: statusBar, from: self)
	}

	@objc func showBundleItemSelector(_ bundleItemsPopUp: NSPopUpButton) {
		guard let bundleItemsMenu = bundleItemsPopUp.menu else {
			return
		}
		bundleItemsMenu.removeAllItems()

		let bundles = OakDocumentViewSupport.bundlesForMenu(withFileType: document?.fileType)

		var selectedItem: NSMenuItem? = nil
		for bundle in bundles {
			// Precedence kept as written: (!selected && hidden) || !hasMenu.
			if !bundle.selectedGrammar && bundle.hiddenFromUser || !bundle.hasMenu {
				continue
			}

			let menuItem = bundleItemsMenu.addItem(withTitle: bundle.name, action: nil, keyEquivalent: "")
			let submenu = NSMenu(title: bundle.uuidString)
			submenu.delegate = BundleMenuDelegate.sharedInstance
			menuItem.submenu = submenu

			if bundle.selectedGrammar {
				menuItem.state = .on
				selectedItem = menuItem
			}
		}

		// On the *built menu*, not on the list the rows came from.
		//
		// The ObjC++ tested `ordered.empty()` — every bundle in the index — while the
		// rows are only the ones surviving the filter above. A bundle that is hidden
		// or carries no menu therefore produced a silently blank pop-up: the map was
		// non-empty, so the explanatory row was skipped, and nothing was drawn.
		// Changed deliberately, after the port rather than inside it, so the
		// translation stayed behaviour-preserving and this is the only commit that
		// moves behaviour.
		if bundleItemsMenu.numberOfItems == 0 {
			bundleItemsMenu.addItem(withTitle: "No Bundles Loaded", action: Self.nop, keyEquivalent: "")
		}

		if let selectedItem {
			bundleItemsPopUp.select(selectedItem)
		}
	}

	@objc var tabSize: UInt {
		get { textView.tabSize }
		set {
			textView.tabSize = newValue
			OakDocumentViewSupport.setTabSize(newValue, forFileType: document?.fileType)
		}
	}

	@objc func takeTabSizeFrom(_ sender: Any?) {
		guard let sender = sender as? NSMenuItem else {
			return
		}
		if sender.tag > 0 {
			tabSize = UInt(sender.tag)
		}
	}

	@objc func setIndentWithSpaces(_ sender: Any?) {
		textView.softTabs = true
		OakDocumentViewSupport.setSoftTabs(true, forFileType: document?.fileType)
	}

	@objc func setIndentWithTabs(_ sender: Any?) {
		textView.softTabs = false
		OakDocumentViewSupport.setSoftTabs(false, forFileType: document?.fileType)
	}

	@objc func showTabSizeSelectorPanel(_ sender: Any?) {
		if tabSizeSelectorPanel == nil {
			Bundle(for: Self.self).loadNibNamed("TabSizeSetting", owner: self, topLevelObjects: nil)
		}
		tabSizeSelectorPanel?.makeKeyAndOrderFront(self)
	}

	@objc func toggleMacroRecording(_ sender: Any?) {
		textView.toggleMacroRecording(sender)
	}

	// =============================
	// = GutterView Delegate Proxy =
	// =============================

	func lineRecord(forPosition yPos: CGFloat) -> GVLineRecord {
		textView.lineRecord(forPosition: yPos)
	}

	func lineFragment(forLine aLine: UInt, column aColumn: UInt) -> GVLineRecord {
		textView.lineFragment(forLine: aLine, column: aColumn)
	}

	// =========================
	// = GutterView DataSource =
	// =========================

	@objc func widthForColumn(withIdentifier columnIdentifier: Any?) -> CGFloat {
		// Deliberately odd, so a centred icon lands on a whole pixel.
		floor((lineHeight-1) / 2) * 2 + 1
	}

	@objc func image(forLine lineNumber: UInt, inColumnWithIdentifier columnIdentifier: Any?, state rowState: GutterViewRowState) -> NSImage? {
		if let identifier = columnIdentifier as? String, identifier == kBookmarksColumnIdentifier {
			// A std::map<size_t, NSString*> in the ObjC++, used for two properties a
			// dictionary does not have: emplace keeps the *first* value for a key, and
			// begin() is the *lowest* key. Both are load-bearing — together they make a
			// diagnostic outrank a bookmark on the same line — so both are explicit.
			var gutterImageName: [Int: String] = [:]
			func emplace(_ priority: Int, _ name: String?) {
				guard let name, gutterImageName[priority] == nil else {
					return
				}
				gutterImageName[priority] = name
			}

			for mark in OakDocumentViewSupport.marks(in: document, atLine: lineNumber) {
				if (mark.payload?.count ?? 0) != 0 {
					emplace(0, mark.type)
				}
				else if mark.type == OakDocumentBookmarkIdentifier {
					emplace(1, rowState != GutterViewRowState.regular ? "Bookmark Hover Remove Template" : "Bookmark Template")
				}
				else if rowState == GutterViewRowState.regular {
					emplace(2, mark.type)
				}
			}

			if rowState != GutterViewRowState.regular {
				emplace(3, "Bookmark Hover Add Template")
			}

			if let lowest = gutterImageName.keys.min() {
				return gutterImage(gutterImageName[lowest]!)
			}
		}
		else if let identifier = columnIdentifier as? String, identifier == kFoldingsColumnIdentifier {
			let state = textView.foldingState(forLine: lineNumber)
			if state == kFoldingTop {
				return gutterImage(rowState == GutterViewRowState.regular ? "Folding Top Template" : "Folding Top Hover Template")
			}
			else if state == kFoldingCollapsed {
				return gutterImage(rowState == GutterViewRowState.regular ? "Folding Collapsed Template" : "Folding Collapsed Hover Template")
			}
			else if state == kFoldingBottom {
				return gutterImage(rowState == GutterViewRowState.regular ? "Folding Bottom Template" : "Folding Bottom Hover Template")
			}
		}
		return nil
	}

	// =============================
	// = Bookmark Submenu Delegate =
	// =============================

	@objc func takeBookmarkFrom(_ sender: Any?) {
		if let sender = sender as? NSMenuItem {
			selectAndCenter(sender.representedObject as? String)
		}
	}

	@objc func updateBookmarksMenu(_ aMenu: NSMenu) {
		for bookmark in OakDocumentViewSupport.bookmarks(in: document) {
			let item = aMenu.addItem(withTitle: bookmark.paddedLinePrefix + bookmark.excerpt, action: #selector(takeBookmarkFrom(_:)), keyEquivalent: "")
			item.representedObject = bookmark.positionString
		}

		let hasBookmarks = aMenu.numberOfItems != 0
		if hasBookmarks {
			aMenu.addItem(.separator())
		}
		aMenu.addItem(withTitle: "Clear Bookmarks", action: hasBookmarks ? #selector(clearAllBookmarks(_:)) : Self.nop, keyEquivalent: "")
	}

	// =======================
	// = GutterView Delegate =
	// =======================

	@objc func userDidClickColumn(withIdentifier columnIdentifier: Any?, atLine lineNumber: UInt) {
		guard let identifier = columnIdentifier as? String else {
			return
		}

		if identifier == kBookmarksColumnIdentifier {
			var bookmarks: [String] = []
			var content: [String] = []

			for mark in OakDocumentViewSupport.marks(in: document, atLine: lineNumber) {
				if (mark.payload?.count ?? 0) != 0 {
					content.append(mark.payload!)
				}
				else if mark.type == OakDocumentBookmarkIdentifier {
					bookmarks.append(mark.positionString)
				}
			}

			if content.count == 0 {
				if bookmarks.count == 0 {
					OakDocumentViewSupport.setBookmarkOfType(OakDocumentBookmarkIdentifier, in: document, atLine: lineNumber)
				}
				else {
					OakDocumentViewSupport.removeMark(ofType: OakDocumentBookmarkIdentifier, in: document, atPositionString: bookmarks[0])
				}
			}
			else {
				let popoverContainerView = NSView(frame: .zero)

				let textField = OakCreateLabel(content.joined(separator: "\n"), nil, .left, .byTruncatingMiddle)!
				OakAddAutoLayoutViewsToSuperview([ textField ], popoverContainerView)

				let views: [String: NSView] = [ "textField": textField ]
				popoverContainerView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(5)-[textField]-(5)-|", options: [], metrics: nil, views: views))
				popoverContainerView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-(10)-[textField]-(10)-|", options: [], metrics: nil, views: views))

				let viewController = NSViewController()
				viewController.view = popoverContainerView

				let popover = NSPopover()
				popover.behavior = .transient
				popover.contentViewController = viewController

				let record = lineFragment(forLine: lineNumber, column: 0)
				let rect = NSRect(x: 0, y: record.firstY, width: widthForColumn(withIdentifier: columnIdentifier), height: record.lastY - record.firstY)
				popover.show(relativeTo: rect, of: gutterView, preferredEdge: .maxX)
			}
		}
		else if identifier == kFoldingsColumnIdentifier {
			textView.toggleFolding(atLine: lineNumber, recursive: OakIsAlternateKeyOrMouseEvent(NSEvent.ModifierFlags.option.rawValue, NSApp.currentEvent))
			NotificationCenter.default.post(name: NSNotification.Name(GVColumnDataSourceDidChange), object: self)
		}
	}

	@objc func clearAllBookmarks(_ sender: Any?) {
		document?.removeAllMarks(ofType: OakDocumentBookmarkIdentifier)
	}

	@objc func documentMarksDidChange(_ aNotification: Notification?) {
		NotificationCenter.default.post(name: NSNotification.Name(GVColumnDataSourceDidChange), object: self)
	}

	// ============
	// = Printing =
	// ============

	@objc func printDocument(_ sender: Any?) {
		document?.runPrintOperationModal(for: window, fontName: textView.font?.fontName)
	}
}
