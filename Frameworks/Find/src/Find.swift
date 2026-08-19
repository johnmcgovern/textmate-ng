import AppKit

// The Find window: the controller everything else in this framework hangs off.
// Ported last, so every class it talks to — FFResultNode, FFDocumentSearch,
// FFResultsViewController — was already Swift and already tested.
//
// Find.h stays hand-written, so no consumer changed: AppController,
// DocumentWindowController and OakTextView all still see the same ObjC
// interface. It is deliberately absent from Find-Bridging-Header.h — it declares
// this class, and importing it would give the class two declarations.
//
// **There is no C++ in this file.** All of it — FindMatch's text::range_t
// properties, the std::multimap the replace path hands to
// -performReplacements:checksum:, format_string::expand, the path:: helpers, and
// the two C++-typed members of OakFindServerProtocol — lives in FindSupport.mm,
// including an ObjC++ category that carries the protocol conformance. Probes
// (f9bb0414) showed Swift *can* name those types under this project's interop
// mode, so the split is a choice: one declared boundary per framework, with the
// enum conversions sitting next to the static_asserts that pin them, beats C++
// spelling scattered through a 900-line window controller.
//
// The KVO rule this framework learned twice applies throughout: **anything ObjC
// observes must be `@objc dynamic`, not `@objc`.** Nearly every property below
// is bound through _objectController or bound *to* by -folderSearchDidFinish:,
// so `dynamic` here is load-bearing rather than decorative.

private let kUserDefaultsFolderOptionsKey               = "Folder Search Options"
private let kUserDefaultsFindResultsHeightKey           = "findResultsHeight"
private let kUserDefaultsDefaultFindGlobsKey            = "defaultFindInFolderGlobs"
private let kUserDefaultsKeepSearchResultsOnDoubleClick = "keepSearchResultsOnDoubleClick"
private let kSearchMarkIdentifier                       = "search"

@MainActor private func OakCreateHistoryButton(_ toolTip: String) -> NSButton {
	let res = NSButton(frame: .zero)
	res.bezelStyle = .roundedDisclosure
	res.setButtonType(.momentaryLight)
	res.title      = ""
	res.toolTip    = toolTip
	res.setAccessibilityLabel(toolTip)
	res.setContentCompressionResistancePriority(.required, for: .horizontal)
	return res
}

// A mutable reference the self-unregistering notification block in
// -folderSearchDidFinish: reads back after it has been handed its own token.
private final class ObserverToken: @unchecked Sendable {
	var value: NSObjectProtocol?
}

@objc(Find)
// @preconcurrency on the OakUserDefaultsObserver conformance only: NSWindowController
// is @MainActor, so this class is too, and that protocol is a plain ObjC one whose
// requirement is therefore nonisolated. The isolation is real rather than assumed —
// OakObserveUserDefaults registers its observer with `queue:NSOperationQueue.mainQueue`,
// so -userDefaultsDidChange: only ever arrives on the main thread. The three AppKit
// protocols beside it are already @MainActor in the SDK and need nothing.
class Find: NSWindowController, NSWindowDelegate, NSMenuDelegate, NSMenuItemValidation, @preconcurrency OakUserDefaultsObserver {

	// ==========================================
	// = Views, all built in code — there is no =
	// = nib despite the nib name below         =
	// ==========================================

	private var objectController: NSObjectController!

	private let findTextFieldViewController: FFTextFieldViewController
	private let replaceTextFieldViewController: FFTextFieldViewController

	// Optionals, not implicitly-unwrapped ones. The ObjC++ held these in plain
	// ivars, so every use before -loadWindow was a message to nil — harmless,
	// answering nil/0/NO — and several are genuinely reachable that early:
	// -setSearchTarget: arrives from DocumentWindowController before the window
	// is shown, and -copyReplacements: is a menu action. Swift would trap on `!`
	// instead. This is the FFResultsViewController lesson applied up front rather
	// than after a crash.
	private var wherePopUpButton: NSPopUpButton?
	private var findAllButton: NSButton?
	private var findNextButton: NSButton?
	private var transitionViewController: OakTransitionViewController?
	private var statusBarViewController: FFStatusBarViewController?
	private var storedGridView: NSGridView?
	private var storedActionButtonsStackView: NSStackView?
	private var resultsViewController: FFResultsViewController?

	// ==========================================
	// = Public surface (declared in Find.h)    =
	// ==========================================

	@objc weak var delegate: FindDelegate?
	@objc var fileBrowserItems: [String]?
	@objc var documentIdentifier: UUID?
	@objc var findMatches: [FindMatch]?

	private var searchTargetStorage: FFSearchTarget = .document

	@objc var searchTarget: FFSearchTarget {
		get { searchTargetStorage }
		set {
			searchTargetStorage = newValue

			canEditGlob          = newValue != .document && newValue != .selection
			canReplaceInDocument = newValue == .document || newValue == .selection

			updateSearchInPopUpMenu()
			updateWindowTitle()

			let isFolderSearch = newValue != .document && newValue != .selection
			showsResultsOutlineView = isFolderSearch
		}
	}

	private var projectFolderStorage: String

	@objc var projectFolder: String? {
		get { projectFolderStorage }
		set {
			guard projectFolderStorage != newValue else { return }
			projectFolderStorage = newValue ?? ""
			globHistoryList = OakHistoryList(name: "Find in Folder Globs.\(projectFolderStorage)", stackSize: 10, fallbackUserDefaultsKey: kUserDefaultsDefaultFindGlobsKey)
			updateSearchInPopUpMenu()
		}
	}

	@objc(isVisible) var visible: Bool {
		isWindowLoaded && (window?.isVisible ?? false)
	}

	// ==========================================
	// = Class-extension surface                =
	// ==========================================

	@objc dynamic var showsResultsOutlineView: Bool = false {
		didSet {
			guard showsResultsOutlineView != oldValue else { return }

			if showsResultsOutlineView {
				if let resultsView = resultsViewController?.view, let transitionView = transitionViewController?.view {
					resultsView.frame = NSRect(origin: .zero, size: NSSize(width: NSWidth(transitionView.frame), height: max(50, findResultsHeight)))
					NotificationCenter.default.addObserver(self, selector: #selector(resultsFrameDidChange(_:)), name: NSView.frameDidChangeNotification, object: resultsView)
				}
			} else if let resultsView = resultsViewController?.view {
				NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: resultsView)
			}

			transitionViewController?.subview = showsResultsOutlineView ? resultsViewController?.view : nil
			window?.defaultButtonCell = (showsResultsOutlineView ? findAllButton?.cell : findNextButton?.cell) as? NSButtonCell
		}
	}

	@objc dynamic var otherFolder: String?

	@objc dynamic var canEditGlob: Bool = false
	@objc dynamic var canReplaceInDocument: Bool = false

	@objc dynamic var globHistoryList: OakHistoryList<NSString>?
	@objc dynamic var recentFolders: OakHistoryList<NSString>?

	@objc dynamic var documentSearch: FFDocumentSearch? {
		get { documentSearchStorage }
		set { setDocumentSearch(newValue) }
	}
	private var documentSearchStorage: FFDocumentSearch?

	@objc var results: FFResultNode?

	// Bound *to* in -folderSearchDidFinish:, which is what makes `dynamic`
	// mandatory here rather than merely correct: a binding writes through the
	// runtime and reads back the same way.
	@objc dynamic var countOfMatches: UInt = 0
	@objc dynamic var countOfExcludedMatches: UInt = 0
	@objc dynamic var countOfReadOnlyMatches: UInt = 0
	@objc dynamic var countOfExcludedReadOnlyMatches: UInt = 0

	@objc dynamic var closeWindowOnSuccess: Bool = false
	@objc dynamic var performingFolderSearch: Bool = false

	// The two OakFindServerProtocol members that are C++ on the wire. Find's
	// conformance is declared by the ObjC++ category in FindSupport.mm, which maps
	// each of these to its find:: counterpart; the protocol's other three
	// requirements are pure ObjC and are implemented below.
	@objc var findOperationTag: FFFindOperation = .count
	@objc var findOptionsMask: FFFindOptions = []

	// ==========================================
	// = Option check boxes                     =
	// ==========================================

	@objc class func keyPathsForValuesAffectingCanIgnoreWhitespace() -> Set<String> { [ "regularExpression" ] }
	@objc class func keyPathsForValuesAffectingIgnoreWhitespace() -> Set<String>    { [ "regularExpression" ] }

	private var ignoreCaseStorage: Bool = false
	private var wrapAroundStorage: Bool = false
	private var ignoreWhitespaceStorage: Bool = false
	private var regularExpressionStorage: Bool = false

	@objc dynamic var ignoreCase: Bool {
		get { ignoreCaseStorage }
		set {
			guard ignoreCaseStorage != newValue else { return }
			ignoreCaseStorage = newValue
			UserDefaults.standard.set(newValue, forKey: kUserDefaultsFindIgnoreCase)
		}
	}

	@objc dynamic var wrapAround: Bool {
		get { wrapAroundStorage }
		set {
			guard wrapAroundStorage != newValue else { return }
			wrapAroundStorage = newValue
			UserDefaults.standard.set(newValue, forKey: kUserDefaultsFindWrapAround)
		}
	}

	// Derived on read, stored on write. The check box remembers what you asked
	// for; the getter answers NO while a regexp search is configured, because
	// ignore-whitespace and regular-expression are mutually exclusive and the box
	// is disabled in that state. Pinned by t_find_option_assembly.mm — a port that
	// returns the ivar here silently changes what every regexp search matches.
	@objc dynamic var ignoreWhitespace: Bool {
		get { ignoreWhitespaceStorage && canIgnoreWhitespace }
		set { ignoreWhitespaceStorage = newValue }
	}

	@objc dynamic var canIgnoreWhitespace: Bool { regularExpressionStorage == false }

	@objc dynamic var regularExpression: Bool {
		get { regularExpressionStorage }
		set {
			guard regularExpressionStorage != newValue else { return }

			regularExpressionStorage = newValue
			findTextFieldViewController.showPopover(with: nil)

			findTextFieldViewController.syntaxHighlightEnabled    = newValue
			replaceTextFieldViewController.syntaxHighlightEnabled = newValue
		}
	}

	@objc dynamic var fullWords: Bool = false // not implemented

	@objc dynamic var searchHiddenFolders: Bool = false { didSet { if searchHiddenFolders != oldValue { updateFolderSearchUserDefaults() } } }
	@objc dynamic var searchFolderLinks: Bool = false   { didSet { if searchFolderLinks != oldValue   { updateFolderSearchUserDefaults() } } }
	@objc dynamic var searchFileLinks: Bool = false     { didSet { if searchFileLinks != oldValue     { updateFolderSearchUserDefaults() } } }
	@objc dynamic var searchBinaryFiles: Bool = false   { didSet { if searchBinaryFiles != oldValue   { updateFolderSearchUserDefaults() } } }

	// ==========================================
	// = Construction                           =
	// ==========================================

	@objc static let sharedInstance = Find()

	// +initialize has no Swift spelling. Registering on first construction is
	// equivalent here because nothing outside this class reads the key, and the
	// list it seeds is consumed by -globHistoryList two lines into -init.
	private static let registerDefaults: Void = {
		UserDefaults.standard.register(defaults: [
			kUserDefaultsDefaultFindGlobsKey: [ "*", "*.txt", "*.{c,h}" ]
		])
	}()

	// Spelled out, and `@objc`, because ObjC callers use +new and the tests use
	// -init: Swift stops inheriting -init the moment another initializer exists,
	// and every search would then die at "unimplemented initializer". Not
	// `override` — NSWindowController's designated initializers are init(window:)
	// and init(coder:), so this is a new one rather than a redeclaration.
	//
	// The ObjC++ called -initWithWindowNibName:@"UNUSED" — a placeholder, since
	// -loadWindow builds the window in code and never consults a nib. That is a
	// *convenience* initializer in Swift's AppKit overlay and so cannot be called
	// with `super.init`, hence init(window: nil) plus the windowNibName override,
	// which together reproduce both halves of what it did.
	@objc init() {
		_ = Find.registerDefaults

		projectFolderStorage           = NSHomeDirectory()
		findTextFieldViewController    = FFTextFieldViewController(pasteboard: OakPasteboard.find, grammarName: "source.regexp.oniguruma")
		replaceTextFieldViewController = FFTextFieldViewController(pasteboard: OakPasteboard.replace, grammarName: "textmate.format-string")

		super.init(window: nil)

		objectController = NSObjectController(content: self)

		globHistoryList = OakHistoryList(name: "Find in Folder Globs.default", stackSize: 10, fallbackUserDefaultsKey: kUserDefaultsDefaultFindGlobsKey)
		recentFolders   = OakHistoryList(name: "findRecentPlaces", stackSize: 21)
	}

	required init?(coder: NSCoder) {
		fatalError("Find is not restorable from a coder — it is built in code and reached through +sharedInstance")
	}

	override var windowNibName: NSNib.Name? { "UNUSED" }

	override func loadWindow() {
		let r = NSScreen.main?.visibleFrame ?? .zero
		let window = NSPanel(contentRect: NSRect(x: NSMidX(r) - 100, y: NSMidY(r) + 100, width: 200, height: 200), styleMask: [ .titled, .closable, .resizable, .miniaturizable ], backing: .buffered, defer: false)

		window.collectionBehavior = [ .moveToActiveSpace, .fullScreenAuxiliary ]
		window.delegate           = self
		window.setFrameAutosaveName("Find")
		window.hidesOnDeactivate  = false

		let resultsViewController = FFResultsViewController()
		self.resultsViewController                     = resultsViewController
		resultsViewController.selectResultAction      = #selector(didSelectResult(_:))
		resultsViewController.removeResultAction      = #selector(didRemoveResult(_:))
		resultsViewController.doubleClickResultAction = #selector(didDoubleClickResult(_:))
		resultsViewController.target                  = self

		resultsViewController.bind(NSBindingName("replaceString"), to: replaceTextFieldViewController, withKeyPath: "stringValue", options: nil)
		resultsViewController.bind(NSBindingName("showReplacementPreviews"), to: replaceTextFieldViewController, withKeyPath: "hasFocus", options: nil)

		let transitionViewController = OakTransitionViewController()
		self.transitionViewController = transitionViewController

		let statusBarViewController = FFStatusBarViewController()
		self.statusBarViewController = statusBarViewController
		statusBarViewController.stopAction = #selector(stopSearch(_:))
		statusBarViewController.stopTarget = self

		let views: [String: NSView] = [
			"options": gridView,
			"results": transitionViewController.view,
			"status":  statusBarViewController.view,
			"buttons": actionButtonsStackView,
		]

		let contentView = NSView(frame: .zero)

		OakAddAutoLayoutViewsToSuperview(Array(views.values), contentView)
		OakSetupKeyViewLoop([ gridView, transitionViewController.view, actionButtonsStackView ])

		NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: "H:|[options]|", options: [], metrics: nil, views: views))
		NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: "V:|[options]-[results]-[status]-[buttons]-|", options: [ .alignAllLeading, .alignAllTrailing ], metrics: nil, views: views))

		window.contentView = contentView
		window.initialFirstResponder = findTextFieldViewController.view
		window.defaultButtonCell = findNextButton?.cell as? NSButtonCell

		// setup find/replace strings/options
		userDefaultsDidChange(nil)
		findClipboardDidChange(nil)
		replaceClipboardDidChange(nil)

		OakObserveUserDefaults(self)
		NotificationCenter.default.addObserver(self, selector: #selector(findClipboardDidChange(_:)), name: NSNotification.Name.OakPasteboardDidChange, object: OakPasteboard.find)
		NotificationCenter.default.addObserver(self, selector: #selector(replaceClipboardDidChange(_:)), name: NSNotification.Name.OakPasteboardDidChange, object: OakPasteboard.replace)
		NotificationCenter.default.addObserver(self, selector: #selector(textViewWillPerformFindOperation(_:)), name: NSNotification.Name(rawValue: "OakTextViewWillPerformFindOperation"), object: nil)

		window.layoutIfNeeded() // Incase autosaved window frame includes results, we want to shrink the frame
		self.window = window
		updateWindowTitle()
	}

	func menuNeedsUpdate(_ aMenu: NSMenu) {
		aMenu.removeAllItems()
		NSApp.sendAction(#selector(updateShowTabMenu(_:)), to: nil, from: aMenu)
	}

	// ==========================================
	// = The options grid                       =
	// ==========================================

	private var gridView: NSGridView {
		if let storedGridView { return storedGridView }

		let findLabel              = OakCreateLabel("Find:", nil, .left, .byTruncatingMiddle)!
		let findHistoryButton      = OakCreateHistoryButton("Show Find History")

		let countButton            = OakCreateButton("Σ", .smallSquare)!
		countButton.toolTip        = "Show Results Count"
		countButton.setAccessibilityLabel(countButton.toolTip)

		let replaceLabel           = OakCreateLabel("Replace:", nil, .left, .byTruncatingMiddle)!
		let replaceHistoryButton   = OakCreateHistoryButton("Show Replace History")

		let optionsLabel           = OakCreateLabel("Options:", nil, .left, .byTruncatingMiddle)!

		let ignoreCaseCheckBox        = OakCreateCheckBox("Ignore Case")!
		let ignoreWhitespaceCheckBox  = OakCreateCheckBox("Ignore Whitespace")!
		let regularExpressionCheckBox = OakCreateCheckBox("Regular Expression")!
		let wrapAroundCheckBox        = OakCreateCheckBox("Wrap Around")!

		let whereLabel             = OakCreateLabel("In:", nil, .left, .byTruncatingMiddle)!
		let wherePopUpButton       = OakCreatePopUpButton(false, nil, whereLabel)!
		self.wherePopUpButton      = wherePopUpButton
		let matchingLabel          = OakCreateLabel("matching", nil, .left, .byTruncatingMiddle)!
		let globTextField          = OakCreateComboBox(matchingLabel)!
		let actionsPopUpButton     = OakCreateActionPopUpButton(true /* bordered */)!

		let optionsGridView = NSGridView(views: [
			[ regularExpressionCheckBox, ignoreWhitespaceCheckBox ],
			[ ignoreCaseCheckBox,        wrapAroundCheckBox       ],
		])

		optionsGridView.rowSpacing    = 8
		optionsGridView.columnSpacing = 20
		optionsGridView.rowAlignment  = .firstBaseline
		optionsGridView.row(at: 1).bottomPadding = 12

		let whereStackView = NSStackView(views: [ wherePopUpButton, matchingLabel, globTextField ])
		whereStackView.alignment = .lastBaseline
		whereStackView.setHuggingPriority(NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.defaultHigh.rawValue - 1), for: .vertical)

		let gridView = NSGridView(views: [
			[ findLabel,    findTextFieldViewController.view,    findHistoryButton,   countButton ],
			[ replaceLabel, replaceTextFieldViewController.view, replaceHistoryButton             ],
			[ optionsLabel, optionsGridView                                                       ],
			[ whereLabel,   whereStackView,                      actionsPopUpButton               ],
		])
		storedGridView = gridView

		gridView.rowSpacing    = 8
		gridView.columnSpacing = 4
		gridView.yPlacement    = .top

		gridView.row(at: 0).topPadding        = 20
		gridView.column(at: 0).xPlacement     = .trailing
		gridView.column(at: 0).leadingPadding = 20
		gridView.column(at: 1).leadingPadding = 4
		gridView.column(at: 3).leadingPadding = 4
		gridView.column(at: gridView.numberOfColumns - 1).trailingPadding = 20

		gridView.mergeCells(inHorizontalRange: NSRange(location: 2, length: 2), verticalRange: NSRange(location: 3, length: 1))
		gridView.cell(atColumnIndex: 2, rowIndex: 3).xPlacement = .fill

		for row in 0..<gridView.numberOfRows {
			gridView.cell(atColumnIndex: 0, rowIndex: row).yPlacement = .none
		}

		for row in 0..<2 {
			gridView.cell(atColumnIndex: 0, rowIndex: row).rowAlignment = .firstBaseline
			gridView.cell(atColumnIndex: 1, rowIndex: row).rowAlignment = .firstBaseline
		}

		gridView.cell(atColumnIndex: 0, rowIndex: 2).customPlacementConstraints = [ optionsLabel.firstBaselineAnchor.constraint(equalTo: regularExpressionCheckBox.firstBaselineAnchor, constant: 0) ]
		gridView.cell(atColumnIndex: 0, rowIndex: 3).customPlacementConstraints = [ whereLabel.firstBaselineAnchor.constraint(equalTo: matchingLabel.firstBaselineAnchor, constant: 0) ]

		gridView.setContentHuggingPriority(NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.windowSizeStayPut.rawValue), for: .vertical)

		findTextFieldViewController.view.setAccessibilityTitleUIElement(findLabel)
		replaceTextFieldViewController.view.setAccessibilityTitleUIElement(replaceLabel)

		countButton.widthAnchor.constraint(equalTo: findHistoryButton.widthAnchor).isActive = true
		countButton.heightAnchor.constraint(equalTo: findHistoryButton.heightAnchor).isActive = true
		wherePopUpButton.widthAnchor.constraint(lessThanOrEqualToConstant: 150).isActive = true

		updateSearchInPopUpMenu()

		actionsPopUpButton.menu = createActionMenu()

		findHistoryButton.action    = #selector(FFTextFieldViewController.showHistory(_:))
		findHistoryButton.target    = findTextFieldViewController
		replaceHistoryButton.action = #selector(FFTextFieldViewController.showHistory(_:))
		replaceHistoryButton.target = replaceTextFieldViewController
		countButton.action          = #selector(countOccurrences(_:))

		globTextField.bind(.value,         to: objectController!,                withKeyPath: "content.globHistoryList.head", options: nil)
		globTextField.bind(.contentValues, to: objectController!,                withKeyPath: "content.globHistoryList.list", options: nil)
		globTextField.bind(.enabled,       to: objectController!,                withKeyPath: "content.canEditGlob",          options: nil)
		ignoreCaseCheckBox.bind(.value,    to: objectController!,                withKeyPath: "content.ignoreCase",           options: nil)
		ignoreWhitespaceCheckBox.bind(.value, to: objectController!,             withKeyPath: "content.ignoreWhitespace",     options: nil)
		regularExpressionCheckBox.bind(.value, to: objectController!,            withKeyPath: "content.regularExpression",    options: nil)
		wrapAroundCheckBox.bind(.value,    to: objectController!,                withKeyPath: "content.wrapAround",           options: nil)
		ignoreWhitespaceCheckBox.bind(.enabled, to: objectController!,           withKeyPath: "content.canIgnoreWhitespace",  options: nil)
		countButton.bind(.enabled,         to: findTextFieldViewController,      withKeyPath: "stringValue.length",           options: nil)

		OakSetupKeyViewLoop([ gridView, findTextFieldViewController.view, replaceTextFieldViewController.view, countButton, regularExpressionCheckBox, ignoreWhitespaceCheckBox, ignoreCaseCheckBox, wrapAroundCheckBox, wherePopUpButton, globTextField, actionsPopUpButton ])

		return gridView
	}

	// The first of the two menus MenuBuilder used to build. Its MBMenu is a C++
	// designated-initializer aggregate that Swift cannot construct, so this is
	// hand-rolled — the route CommitWindow and Preferences already took, and the
	// reason MenuBuilder itself is scheduled last rather than first.
	//
	// MBCreateMenuItem's defaults are reproduced here rather than assumed: an item
	// with a nil title becomes a **separator**, which is what `{ /* Placeholder */ }`
	// was — a pop-up button never shows item 0, so the original used an empty
	// item to hold the slot. Every item also got keyEquivalentModifierMask =
	// NSEventModifierFlagCommand whether or not it had a key equivalent, which is
	// AppKit's default anyway for items created with a key equivalent.
	private func createActionMenu() -> NSMenu {
		let menu = NSMenu(title: "AMainMenu")

		menu.addItem(NSMenuItem.separator()) // Placeholder — a pop-up button never draws item 0.

		menu.addItem(withTitle: "Search", action: Selector(("nop:")), keyEquivalent: "")

		for (title, action) in [
			("Binary Files",              #selector(toggleSearchBinaryFiles(_:))),
			("Hidden Folders",            #selector(toggleSearchHiddenFolders(_:))),
			("Symbolic Links to Folders", #selector(toggleSearchFolderLinks(_:))),
			("Symbolic Links to Files",   #selector(toggleSearchFileLinks(_:))),
		] {
			menu.addItem(withTitle: title, action: action, keyEquivalent: "").indentationLevel = 1
		}

		menu.addItem(NSMenuItem.separator())

		let collapseItem = menu.addItem(withTitle: "Collapse Results", action: #selector(FFResultsViewController.toggleCollapsedState(_:)), keyEquivalent: "1")
		collapseItem.keyEquivalentModifierMask = [ .command, .option ]
		collapseItem.target                    = resultsViewController

		// A submenu with this object as its delegate, filled on demand by
		// -menuNeedsUpdate: → -updateShowTabMenu:. MBMenuItem's `.delegate` did
		// exactly this: a non-nil delegate is enough to make it build a submenu.
		let selectResultItem = menu.addItem(withTitle: "Select Result", action: nil, keyEquivalent: "")
		let selectResultMenu = NSMenu(title: "Select Result")
		selectResultMenu.delegate = self
		selectResultItem.submenu  = selectResultMenu

		menu.addItem(NSMenuItem.separator())

		menu.addItem(withTitle: "Copy Matching Parts",                action: #selector(copyMatchingParts(_:)),             keyEquivalent: "")
		menu.addItem(withTitle: "Copy Matching Parts With Filenames", action: #selector(copyMatchingPartsWithFilename(_:)),  keyEquivalent: "")
		menu.addItem(withTitle: "Copy Entire Lines",                  action: #selector(copyEntireLines(_:)),               keyEquivalent: "")
		menu.addItem(withTitle: "Copy Entire Lines With Filenames",   action: #selector(copyEntireLinesWithFilename(_:)),   keyEquivalent: "")
		menu.addItem(withTitle: "Copy Replacements",                  action: #selector(copyReplacements(_:)),              keyEquivalent: "")

		menu.addItem(NSMenuItem.separator())

		menu.addItem(withTitle: "Check All",   action: #selector(checkAll(_:)),   keyEquivalent: "")
		menu.addItem(withTitle: "Uncheck All", action: #selector(uncheckAll(_:)), keyEquivalent: "")

		return menu
	}

	private var actionButtonsStackView: NSStackView {
		if let storedActionButtonsStackView { return storedActionButtonsStackView }

		let findAllButton        = OakCreateButton("Find All", .rounded)!
		let replaceAllButton     = OakCreateButton("Replace All", .rounded)!
		let replaceButton        = OakCreateButton("Replace", .rounded)!
		let replaceAndFindButton = OakCreateButton("Replace & Find", .rounded)!
		let findPreviousButton   = OakCreateButton("Previous", .rounded)!
		let findNextButton       = OakCreateButton("Next", .rounded)!

		self.findAllButton  = findAllButton
		self.findNextButton = findNextButton

		findAllButton.action        = #selector(self.findAll(_:))
		replaceAllButton.action     = #selector(replaceAll(_:))
		replaceButton.action        = #selector(replace(_:))
		replaceAndFindButton.action = #selector(replaceAndFind(_:))
		findPreviousButton.action   = #selector(findPrevious(_:))
		findNextButton.action       = #selector(self.findNext(_:))

		replaceButton.bind(.enabled,        to: objectController!,           withKeyPath: "content.canReplaceInDocument",  options: nil)
		replaceAndFindButton.bind(.enabled, to: objectController!,           withKeyPath: "content.canReplaceInDocument",  options: nil)
		replaceAndFindButton.bind(NSBindingName("enabled2"), to: findTextFieldViewController, withKeyPath: "stringValue.length", options: nil)
		findAllButton.bind(.enabled,        to: findTextFieldViewController, withKeyPath: "stringValue.length",            options: nil)
		replaceAllButton.bind(.title,       to: objectController!,           withKeyPath: "content.replaceAllButtonTitle", options: nil)
		replaceAllButton.bind(.enabled,     to: findTextFieldViewController, withKeyPath: "stringValue.length",            options: nil)
		replaceAllButton.bind(NSBindingName("enabled2"), to: objectController!, withKeyPath: "content.canReplaceAll",      options: nil)
		findPreviousButton.bind(.enabled,   to: findTextFieldViewController, withKeyPath: "stringValue.length",            options: nil)
		findNextButton.bind(.enabled,       to: findTextFieldViewController, withKeyPath: "stringValue.length",            options: nil)

		let stackView = NSStackView(views: [ findAllButton, replaceAllButton ])
		storedActionButtonsStackView = stackView
		stackView.setViews([ replaceButton, replaceAndFindButton, findPreviousButton, findNextButton ], in: .trailing)
		stackView.setHuggingPriority(NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.defaultHigh.rawValue - 1), for: .vertical)
		stackView.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)

		OakSetupKeyViewLoop([ stackView, findAllButton, replaceAllButton, replaceButton, replaceAndFindButton, findPreviousButton, findNextButton ])

		return stackView
	}

	// ==========================================
	// = Defaults & pasteboards                 =
	// ==========================================

	@objc func userDefaultsDidChange(_ aNotification: Notification!) {
		ignoreCase = UserDefaults.standard.bool(forKey: kUserDefaultsFindIgnoreCase)
		wrapAround = UserDefaults.standard.bool(forKey: kUserDefaultsFindWrapAround)

		let options = UserDefaults.standard.dictionary(forKey: kUserDefaultsFolderOptionsKey)
		searchHiddenFolders = (options?["searchHiddenFolders"] as? NSNumber)?.boolValue ?? false
		searchFolderLinks   = (options?["searchFolderLinks"] as? NSNumber)?.boolValue ?? false
		searchFileLinks     = !((options?["skipFileLinks"] as? NSNumber)?.boolValue ?? false)
		searchBinaryFiles   = (options?["searchBinaryFiles"] as? NSNumber)?.boolValue ?? false
	}

	@objc func findClipboardDidChange(_ aNotification: Notification!) {
		let entry = OakPasteboard.find.current()
		findTextFieldViewController.stringValue = entry?.string
		regularExpression = entry?.regularExpression ?? false
		ignoreWhitespace  = entry?.ignoreWhitespace ?? false
		fullWords         = entry?.fullWordMatch ?? false
	}

	@objc func replaceClipboardDidChange(_ aNotification: Notification!) {
		replaceTextFieldViewController.stringValue = OakPasteboard.replace.current()?.string
	}

	@objc var findString: String? { findTextFieldViewController.stringValue }
	@objc var replaceString: String { replaceTextFieldViewController.stringValue ?? "" }

	private func updateWindowTitle() {
		if let folder = searchFolder {
			window?.title = String.localizedStringWithFormat("Find — %@", (folder as NSString).abbreviatingWithTildeInPath)
		} else if searchTargetStorage == .openFiles {
			window?.title = "Find — Open Files"
		} else {
			window?.title = "Find"
		}
	}

	override func showWindow(_ sender: Any?) {
		let isVisibleAndKey = visible && (window?.isKeyWindow ?? false)
		super.showWindow(sender)
		if !isVisibleAndKey || !((window?.firstResponder) is NSTextView) {
			window?.makeFirstResponder(findTextFieldViewController.view)
		}
	}

	@objc @discardableResult func commitEditing() -> Bool {
		let currentResponder = window?.firstResponder
		let view = (currentResponder as? NSTextView)?.delegate as? NSResponder ?? currentResponder
		let res = objectController?.commitEditing() ?? true
		if window?.firstResponder != currentResponder, let view {
			window?.makeFirstResponder(view)
		}

		// =====================
		// = Update Pasteboard =
		// =====================

		if OakNotEmptyString(findString) {
			let entry = OakPasteboard.find.current()
			let newFindString        = findString != entry?.string
			let newRegularExpression = (entry?.regularExpression ?? false) != regularExpression
			let newIgnoreWhitespace  = (entry?.ignoreWhitespace ?? false)  != ignoreWhitespace
			let newFullWords         = (entry?.fullWordMatch ?? false)     != fullWords

			if newFindString || newRegularExpression || newIgnoreWhitespace || newFullWords {
				let newOptions: [String: Any] = [
					OakFindRegularExpressionOption: NSNumber(value: regularExpression),
					OakFindIgnoreWhitespaceOption:  NSNumber(value: ignoreWhitespace),
					OakFindFullWordsOption:         NSNumber(value: fullWords),
				]
				OakPasteboard.find.addEntry(with: findString, options: newOptions)
			}
		}

		if replaceString != OakPasteboard.find.current()?.string {
			OakPasteboard.replace.addEntry(with: replaceString)
		}

		return res
	}

	@objc private func resultsFrameDidChange(_ aNotification: Notification) {
		if showsResultsOutlineView, let view = resultsViewController?.view {
			findResultsHeight = NSHeight(view.frame)
		}
	}

	func windowDidResignKey(_ notification: Notification) {
		commitEditing()
	}

	func windowWillClose(_ notification: Notification) {
		stopSearch(self)
		commitEditing()
	}

	@objc private func textViewWillPerformFindOperation(_ aNotification: Notification) {
		if isWindowLoaded, window?.isVisible == true, window?.isKeyWindow == true {
			commitEditing()
		}
	}

	// ==========================================
	// = The “where” pop-up menu                =
	// ==========================================

	private func displayName(forFolder path: String) -> String {
		// The candidate list the name is disambiguated against, in the ObjC++'s
		// order: every recent folder, then the current search folder, then the
		// project folder.
		var paths: [String] = []
		if let recentFolders {
			for i in 0..<recentFolders.count() {
				if let folder = recentFolders.object(at: i) as String? { paths.append(folder) }
			}
		}
		if let folder = searchFolder { paths.append(folder) }
		paths.append(projectFolderStorage)

		return FFDisplayNameForFolder(path, paths)
	}

	// Rebuilt from scratch every time the search target or project folder moves.
	//
	// The ObjC++ ran this whole method against a nil _wherePopUpButton whenever it
	// arrived before -gridView had built one — which -setSearchTarget: routinely
	// does, since DocumentWindowController sets the target before showing the
	// window. Messaging nil meant MBCreateMenu built a menu nobody kept and every
	// subsequent line no-oped, so nothing it did survived. Returning early is the
	// same outcome without building and discarding a menu, and without the disk
	// I/O of fetching folder icons for it.
	private func updateSearchInPopUpMenu() {
		guard let wherePopUpButton, let whereMenu = wherePopUpButton.menu else { return }

		whereMenu.removeAllItems()

		let orderFront = #selector(orderFrontFindPanel(_:))

		let documentItem = whereMenu.addItem(withTitle: "Document", action: orderFront, keyEquivalent: "f")
		documentItem.tag = FFSearchTarget.document.rawValue
		whereMenu.addItem(withTitle: "Selection", action: orderFront, keyEquivalent: "").tag = FFSearchTarget.selection.rawValue

		whereMenu.addItem(NSMenuItem.separator())

		whereMenu.addItem(withTitle: "Open Files", action: orderFront, keyEquivalent: "").tag = FFSearchTarget.openFiles.rawValue
		whereMenu.addItem(withTitle: "Project Folder", action: orderFront, keyEquivalent: "F").tag = FFSearchTarget.project.rawValue
		whereMenu.addItem(withTitle: "File Browser Items", action: orderFront, keyEquivalent: "").tag = FFSearchTarget.fileBrowserItems.rawValue
		whereMenu.addItem(withTitle: "Other Folder…", action: #selector(showFolderSelectionPanel(_:)), keyEquivalent: "").tag = FFSearchTarget.other.rawValue

		whereMenu.addItem(NSMenuItem.separator())

		let folderItem = whereMenu.addItem(withTitle: "«Last Folder»", action: orderFront, keyEquivalent: "")

		whereMenu.addItem(NSMenuItem.separator())

		whereMenu.addItem(withTitle: "Recent Places", action: Selector(("nop:")), keyEquivalent: "")

		if let lastFolder = searchFolder ?? projectFolder {
			folderItem.title = displayName(forFolder: lastFolder)
			folderItem.setIconForFile(lastFolder)
			FFFolderMenu.addSubmenuForDirectory(atPath: lastFolder, to: folderItem)
		}

		if searchTargetStorage == .project || searchTargetStorage == .other || (searchTargetStorage == .fileBrowserItems && fileBrowserItems?.count == 1) {
			wherePopUpButton.select(folderItem)
		} else {
			wherePopUpButton.selectItem(withTag: searchTargetStorage.rawValue)
		}

		// =================
		// = Recent Places =
		// =================

		var selectedIndex = -1
		var recentPaths: [String] = []
		if let recentFolders {
			for i in 0..<recentFolders.count() {
				guard let path = recentFolders.object(at: i) as String? else { continue }
				if path == projectFolderStorage || !FileManager.default.fileExists(atPath: path) {
					continue
				}

				if searchTargetStorage == .other && path == otherFolder {
					selectedIndex = recentPaths.count
				}
				recentPaths.append(path)
			}
		}

		for i in 0..<recentPaths.count {
			if i == selectedIndex { continue }

			let path = recentPaths[i]

			let recentItem = whereMenu.addItem(withTitle: displayName(forFolder: path), action: orderFront, keyEquivalent: "")
			recentItem.setIconForFile(path)
			recentItem.representedObject = path

			if selectedIndex + 1 == i {
				recentItem.action                   = #selector(goBack(_:))
				recentItem.target                   = self
				recentItem.keyEquivalent            = "["
				recentItem.keyEquivalentModifierMask = .command
			} else if i + 1 == selectedIndex {
				recentItem.action                   = #selector(goForward(_:))
				recentItem.target                   = self
				recentItem.keyEquivalent            = "]"
				recentItem.keyEquivalentModifierMask = .command
			}
		}
	}

	@objc func orderFrontFindPanel(_ sender: Any?) {
		if let folder = (sender as? NSMenuItem)?.representedObject as? String {
			otherFolder = folder
			searchTarget = .other
			return
		}

		if let tag = (sender as? NSMenuItem)?.tag, let target = FFSearchTarget(rawValue: tag) {
			searchTarget = target
		}
	}

	// The ObjC++ had -setStatusString:/-setAlternateStatusString: as bare setters
	// with no getter, forwarding to the status bar. As properties here they gain a
	// getter that reads back through the same view controller, which is what the
	// ObjC++ would have answered had anyone asked.
	@objc var statusString: String? {
		get { statusBarViewController?.statusText }
		set { statusBarViewController?.statusText = newValue }
	}

	@objc var alternateStatusString: String? {
		get { statusBarViewController?.alternateStatusText }
		set { statusBarViewController?.alternateStatusText = newValue }
	}

	@objc var searchFolder: String? {
		if searchTargetStorage == .project {
			return projectFolder
		} else if searchTargetStorage == .fileBrowserItems && fileBrowserItems?.count == 1 {
			return fileBrowserItems?.first
		} else if searchTargetStorage == .other {
			return otherFolder
		}
		return nil
	}

	@objc func goToParentFolder(_ sender: Any?) {
		if searchTargetStorage == .fileBrowserItems, let items = fileBrowserItems, items.count > 1 {
			otherFolder  = CommonAncestor(items)
			searchTarget = .other
		} else if let parent = (searchFolder as NSString?)?.deletingLastPathComponent {
			otherFolder  = parent
			searchTarget = .other
		}
	}

	@objc var findResultsHeight: CGFloat {
		get {
			let stored = UserDefaults.standard.integer(forKey: kUserDefaultsFindResultsHeightKey)
			return CGFloat(stored != 0 ? stored : 200)
		}
		set { UserDefaults.standard.set(Int(newValue), forKey: kUserDefaultsFindResultsHeightKey) }
	}

	@objc var globString: String? {
		get { commitEditing(); return globHistoryList?.head as String? }
		set { if let newValue { globHistoryList?.add(newValue as NSString) } }
	}

	private func updateFolderSearchUserDefaults() {
		var options: [String: Any] = [:]

		if searchHiddenFolders { options["searchHiddenFolders"] = true }
		if searchFolderLinks   { options["searchFolderLinks"]   = true }
		if !searchFileLinks    { options["skipFileLinks"]       = true }
		if searchBinaryFiles   { options["searchBinaryFiles"]   = true }

		if !options.isEmpty {
			UserDefaults.standard.set(options, forKey: kUserDefaultsFolderOptionsKey)
		} else {
			UserDefaults.standard.removeObject(forKey: kUserDefaultsFolderOptionsKey)
		}
	}

	@objc func toggleSearchHiddenFolders(_ sender: Any?) { searchHiddenFolders = !searchHiddenFolders }
	@objc func toggleSearchFolderLinks(_ sender: Any?)   { searchFolderLinks   = !searchFolderLinks   }
	@objc func toggleSearchFileLinks(_ sender: Any?)     { searchFileLinks     = !searchFileLinks     }
	@objc func toggleSearchBinaryFiles(_ sender: Any?)   { searchBinaryFiles   = !searchBinaryFiles   }

	@objc func takeLevelToFoldFrom(_ sender: Any?)  { resultsViewController?.toggleCollapsedState(sender) }
	@objc func selectNextResult(_ sender: Any?)     { resultsViewController?.selectNextResult(wrapAround: wrapAround) }
	@objc func selectPreviousResult(_ sender: Any?) { resultsViewController?.selectPreviousResult(wrapAround: wrapAround) }
	@objc func selectNextTab(_ sender: Any?)        { resultsViewController?.selectNextDocument(sender) }
	@objc func selectPreviousTab(_ sender: Any?)    { resultsViewController?.selectPreviousDocument(sender) }

	// ========
	// = Find =
	// ========

	@objc func showFolderSelectionPanel(_ sender: Any?) {
		let openPanel = NSOpenPanel()
		openPanel.title = "Find in Folder"
		openPanel.canChooseFiles = false
		openPanel.canChooseDirectories = true
		if let folder = searchFolder {
			openPanel.directoryURL = URL(fileURLWithPath: folder)
		}
		if isWindowLoaded, let window, window.isVisible {
			openPanel.beginSheetModal(for: window) { result in
				if result == .OK {
					self.otherFolder  = openPanel.urls.last?.standardizedFileURL.path
					self.searchTarget = .other
				} else if window.isVisible { // Reset selected item in pop-up button
					self.searchTarget = self.searchTarget
				}
			}
		} else {
			openPanel.begin { result in
				if result == .OK {
					self.otherFolder  = openPanel.urls.last?.standardizedFileURL.path
					self.searchTarget = .other
					self.showWindow(self)
				}
			}
		}
	}

	@objc func goBack(_ sender: Any?) {
		guard let menu = wherePopUpButton?.menu else { return }
		let index = menu.indexOfItem(withTarget: self, andAction: #selector(goBack(_:)))
		if index != -1 {
			orderFrontFindPanel(menu.items[index])
		}
	}

	@objc func goForward(_ sender: Any?) {
		let index = wherePopUpButton?.menu?.indexOfItem(withTarget: self, andAction: #selector(goForward(_:))) ?? -1
		if index != -1, let menu = wherePopUpButton?.menu {
			orderFrontFindPanel(menu.items[index])
		} else if searchTargetStorage == .other && otherFolder != nil {
			searchTarget = .project
		}
	}

	// ================
	// = Find actions =
	// ================

	@objc class func keyPathsForValuesAffectingCanReplaceAll() -> Set<String>         { [ "countOfMatches", "countOfExcludedMatches", "countOfReadOnlyMatches", "countOfExcludedReadOnlyMatches", "showsResultsOutlineView" ] }
	@objc class func keyPathsForValuesAffectingReplaceAllButtonTitle() -> Set<String> { [ "countOfMatches", "countOfExcludedMatches", "countOfReadOnlyMatches", "countOfExcludedReadOnlyMatches", "showsResultsOutlineView" ] }

	// `&-` rather than `-`: these are NSUInteger differences in the ObjC++, and
	// while the invariants say neither can go negative today, Swift's `-` traps
	// where C wrapped. Rule 3 of this port, and the reason FFResultNode's counters
	// are spelled the same way.
	@objc dynamic var canReplaceAll: Bool {
		showsResultsOutlineView ? (countOfExcludedMatches &- countOfExcludedReadOnlyMatches < countOfMatches &- countOfReadOnlyMatches) : true
	}

	// Note the C precedence the original relied on: `&&` binds tighter than `||`,
	// so this is `excluded != 0 || (readOnly != 0 && readOnly != matches)`.
	@objc dynamic var replaceAllButtonTitle: String {
		showsResultsOutlineView && (countOfExcludedMatches != 0 || (countOfReadOnlyMatches != 0 && countOfReadOnlyMatches != countOfMatches)) ? "Replace Selected" : "Replace All"
	}

	@objc func countOccurrences(_ sender: Any?)   { performFindAction(.countMatches)   }
	@objc func findAll(_ sender: Any?)            { performFindAction(.findAll)        }
	@objc func findAllInSelection(_ sender: Any?) { performFindAction(.findAll)        }
	@objc func findNext(_ sender: Any?)           { performFindAction(.findNext)       }
	@objc func findPrevious(_ sender: Any?)       { performFindAction(.findPrevious)   }
	@objc func replaceAll(_ sender: Any?)         { performFindAction(.replaceAll)     }
	@objc func replaceAndFind(_ sender: Any?)     { performFindAction(.replaceAndFind) }
	@objc func replace(_ sender: Any?)            { performFindAction(.replace)        }

	@objc func stopSearch(_ sender: Any?) {
		if performingFolderSearch {
			documentSearchStorage?.stop()
			folderSearchDidFinish(nil)
			statusString = "Stopped."
		}
	}

	// The five option check boxes, plus the two bits the action itself implies.
	//
	// Spelled in FFFindOptions rather than find::options_t so it is assertable
	// from a test that speaks no C++, and so this port has one spelling to
	// reproduce rather than a choice of two. Pinned by t_find_option_assembly.mm,
	// which was written against the ObjC++ before any of this existed.
	@objc(findOptionsForAction:)
	func findOptions(for action: FindActionTag) -> FFFindOptions {
		var res: FFFindOptions = []
		if regularExpression { res.insert(.regularExpression) }
		if ignoreWhitespace  { res.insert(.ignoreWhitespace)  }
		if fullWords         { res.insert(.fullWords)         }
		if ignoreCase        { res.insert(.ignoreCase)        }
		if wrapAround        { res.insert(.wrapAround)        }

		if action == .findPrevious {
			res.insert(.backwards)
		} else if action == .countMatches || action == .findAll || action == .replaceAll {
			res.insert(.allMatches)
		}

		return res
	}

	private func performFindAction(_ action: FindActionTag) {
		if regularExpression {
			if let message = FFInvalidRegularExpressionMessage(findString) {
				findTextFieldViewController.showPopover(with: message)
				return
			}
		}

		findOptionsMask = findOptions(for: action)

		let searchTarget = self.searchTarget
		if searchTarget != .selection && (searchTarget != .document || (action == .findAll && documentIdentifier != nil)) {
			switch action {
			case .findAll:
				if searchTarget == .document, let identifier = documentIdentifier {
					if let document = OakDocumentController.sharedInstance.findDocument(withIdentifier: identifier) {
						documentSearch = nil
						showsResultsOutlineView = true
						resultsViewController?.hideCheckBoxes = true
						acceptMatches(FFMatchesInDocument(document, findString, findOptionsMask, nil) as? [OakDocumentMatch] ?? [])
						folderSearchDidFinish(nil)
					}
				} else if searchTarget == .openFiles {
					documentSearch = nil
					showsResultsOutlineView = true
					resultsViewController?.hideCheckBoxes = false
					for document in OakDocumentController.sharedInstance.openDocuments() {
						acceptMatches(FFMatchesInDocument(document, findString, findOptionsMask, nil) as? [OakDocumentMatch] ?? [])
					}
					folderSearchDidFinish(nil)
				} else {
					var paths: [String]
					if searchTarget == .project {
						paths = [ projectFolderStorage ]
					} else if searchTarget == .fileBrowserItems {
						paths = fileBrowserItems ?? []
					} else { // searchTarget == .other
						paths = [ otherFolder ].compactMap { $0 }
					}

					var isDirectory: ObjCBool = false
					if (searchTarget == .other || searchTarget == .fileBrowserItems), paths.count == 1, FileManager.default.fileExists(atPath: paths[0], isDirectory: &isDirectory), isDirectory.boolValue {
						recentFolders?.add(paths[0] as NSString)
					}

					let folderSearch = FFDocumentSearch()
					folderSearch.searchBinaryFiles   = true
					folderSearch.searchString        = findString
					folderSearch.options             = findOptionsMask
					folderSearch.paths               = paths
					folderSearch.glob                = globString
					folderSearch.searchFolderLinks   = searchFolderLinks
					folderSearch.searchFileLinks     = searchFileLinks
					folderSearch.searchHiddenFolders = searchHiddenFolders
					folderSearch.searchBinaryFiles   = searchBinaryFiles

					documentSearch = folderSearch
				}

			case .replaceAll, .replaceSelected:
				performReplacements()

			case .findNext:     selectNextResult(self)
			case .findPrevious: selectPreviousResult(self)

			default: break
			}
		} else {
			let onlySelection = searchTarget == .selection
			switch action {
			case .findNext, .findPrevious, .findAll: findOperationTag = onlySelection ? .findInSelection       : .find
			case .countMatches:                      findOperationTag = onlySelection ? .countInSelection      : .count
			case .replaceAll:                        findOperationTag = onlySelection ? .replaceAllInSelection : .replaceAll
			case .replaceAndFind:                    findOperationTag = .replaceAndFind
			case .replace:                           findOperationTag = .replace
			default: break
			}

			closeWindowOnSuccess = action == .findNext && FFCurrentEventIsReturnKeyDown()
			findMatches = nil
			NSApp.sendAction(Selector(("performFindOperation:")), to: nil, from: self)
		}
	}

	// The replace path, and the one place a Swift caller has to hand C++ a
	// container: -performReplacements:checksum: takes a
	// std::multimap<std::pair<size_t,size_t>, std::string>. It is assembled on the
	// other side of FindSupport.h from an array of FFReplacement, so the ordering
	// and duplicate-key behaviour of the multimap are preserved while the decision
	// of *what* to replace stays here.
	private func performReplacements() {
		var replaceCount: UInt = 0
		var fileCount: UInt = 0

		for case let parent as FFResultNode in (results?.children ?? []) {
			if parent.countOfExcluded == parent.countOfLeafs {
				continue
			}

			var replacements: [FFReplacement] = []
			for case let child as FFResultNode in (parent.children ?? []) {
				if child.excluded { continue }
				child.replaceString = replaceString
				guard let match = child.match else { continue }
				let expanded = regularExpression ? FFExpandFormatString(replaceString, match) : replaceString
				replacements.append(FFReplacement(first: match.first, last: match.last, replacement: expanded))
			}

			guard let doc = parent.document, let parentMatch = parent.match else { continue }

			if doc.isLoaded {
				FFPerformReplacements(doc, replacements, parentMatch.checksum)
			} else {
				if !FFPerformReplacements(doc, replacements, parentMatch.checksum) {
					// KVC on an array, which fans out to every element — it works
					// against the Swift FFResultNode because `replaceString` is
					// `dynamic` there. Do not remove that keyword.
					(parent.children as NSArray?)?.setValue(nil, forKey: "replaceString")
					continue
				}

				FFSaveDocumentModalForWindow(doc, window)
			}

			parent.readOnly = true
			replaceCount += UInt(replacements.count)
			fileCount += 1
		}

		statusString = Find.replacementStatusString(forReplacementCount: replaceCount, fileCount: fileCount)
	}

	// Called by the ObjC++ category in FindSupport.mm once it has built the
	// sentence, which is the only part of -didFind:…atPosition: that needed C++.
	@objc(didFindNumber:statusString:)
	func didFind(number aNumber: UInt, statusString: String?) {
		self.statusString = statusString

		// -isAccessibilityElement is reached by name rather than through a protocol,
		// as the ObjC++ did: the responder may be any object at all, and a control
		// answers for its cell. KVC, not -performSelector:, because the getter
		// returns BOOL and performSelector would read it as an object pointer.
		let keyView = NSApp.keyWindow?.firstResponder
		let element: Any? = keyView?.responds(to: Selector(("cell"))) == true ? keyView?.value(forKey: "cell") : keyView
		let isAccessibilityElementSelector = #selector(NSView.isAccessibilityElement)
		if let element = element as? NSObject, element.responds(to: isAccessibilityElementSelector),
		   (element.value(forKey: "accessibilityElement") as? NSNumber)?.boolValue == true {
			NSAccessibility.post(element: element, notification: .announcementRequested, userInfo: [ .announcement: statusString ?? "" ])
		}

		if closeWindowOnSuccess && aNumber != 0 {
			close()
		}
	}

	@objc func didReplace(_ aNumber: UInt, occurrencesOf aFindString: String?, with aReplacementString: String?) {
		statusString = Find.replacedStatusString(forCount: aNumber, findString: aFindString, regularExpression: findOptionsMask.contains(.regularExpression))
	}

	// ===================================================
	// = Status strings — pure, and the pluralisation of =
	// = each one is a thing a port gets quietly wrong   =
	// ===================================================
	//
	// Every count goes through -localizedStringFromNumber: because these are read
	// by people, so a four-digit count carries a group separator. All five are
	// pinned by t_find_status_strings.mm, written against the ObjC++ before the
	// port.

	@objc(replacedStatusStringForCount:findString:regularExpression:)
	class func replacedStatusString(forCount count: UInt, findString: String?, regularExpression: Bool) -> String {
		let formatStrings = [
			[ "Nothing replaced (no occurrences of “%@”).", "Replaced one occurrence of “%@”.", "Replaced %2$@ occurrences of “%@”." ],
			[ "Nothing replaced (no matches for “%@”).",    "Replaced one match of “%@”.",      "Replaced %2$@ matches of “%@”."     ],
		]
		// The clamp is `> 2`, not `> 1`: a count of exactly 2 already takes the
		// plural row. It reads like an off-by-one and is not one.
		let format = formatStrings[regularExpression ? 1 : 0][count > 2 ? 2 : Int(count)]
		return String(format: format, findString ?? "", NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal))
	}

	@objc(replacementStatusStringForReplacementCount:fileCount:)
	class func replacementStatusString(forReplacementCount replaceCount: UInt, fileCount: UInt) -> String {
		String(format: "%@ replacement%@ made across %@ file%@.", NumberFormatter.localizedString(from: NSNumber(value: replaceCount), number: .decimal), replaceCount == 1 ? "" : "s", NumberFormatter.localizedString(from: NSNumber(value: fileCount), number: .decimal), fileCount == 1 ? "" : "s")
	}

	@objc(resultCountStringForCount:searchString:)
	class func resultCountString(forCount count: UInt, searchString: String?) -> String {
		let fmt: String
		switch count {
			case 0:  fmt = "No results found for “%@”."
			case 1:  fmt = "Found one result for “%@”."
			default: fmt = "Found %2$@ results for “%1$@”."
		}
		return String(format: fmt, searchString ?? "", NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal))
	}

	@objc(shownResultCountStringForCount:searchString:)
	class func shownResultCountString(forCount count: UInt, searchString: String?) -> String {
		let fmt: String
		switch count {
			case 0:  fmt = "No results for “%@”."
			case 1:  fmt = "Showing one result for “%@”."
			default: fmt = "Showing %2$@ results for “%1$@”."
		}
		return String(format: fmt, searchString ?? "", NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal))
	}

	@objc(searchedFilesSuffixForFileCount:seconds:)
	class func searchedFilesSuffix(forFileCount fileCount: UInt, seconds: String?) -> String {
		let fmt = fileCount == 1 ? " (searched one file in %@ seconds)" : " (searched %2$@ files in %1$@ seconds)"
		return String(format: fmt, seconds ?? "", NumberFormatter.localizedString(from: NSNumber(value: fileCount), number: .decimal))
	}

	// ===========
	// = Options =
	// ===========

	// The menu item tags are find::options_t values, which are FFFindOptions
	// values — the two are pinned by static_assert in FindSupport.mm and
	// FFDocumentSearchSupport.mm and by t_find_options.mm at runtime, so reading
	// the tag straight into an FFFindOptions is safe rather than a coincidence.
	@objc func takeFindOptionToToggleFrom(_ sender: Any?) {
		guard let tag = (sender as? NSMenuItem)?.tag else {
			assertionFailure("-takeFindOptionToToggleFrom: expects a sender with a tag")
			return
		}

		switch FFFindOptions(rawValue: UInt(bitPattern: tag)) {
			case .fullWords:         fullWords         = !fullWords
			case .ignoreCase:        ignoreCase        = !ignoreCase
			case .ignoreWhitespace:  ignoreWhitespace  = !ignoreWhitespace
			case .regularExpression: regularExpression = !regularExpression
			case .wrapAround:        wrapAround        = !wrapAround
			default:
				assertionFailure("Unknown find option tag \(tag)")
		}

		if OakPasteboard.find.current()?.string == findString {
			commitEditing() // update the options on the pasteboard immediately if the find string has not been changed
		}
	}

	// ====================
	// = Search in Folder =
	// ====================

	private func clearMatches() {
		if let results {
			for case let parent as FFResultNode in (results.children ?? []) {
				parent.document?.removeAllMarks(ofType: kSearchMarkIdentifier)
			}

			unbind(NSBindingName("countOfMatches"))
			unbind(NSBindingName("countOfExcludedMatches"))
			unbind(NSBindingName("countOfReadOnlyMatches"))
			unbind(NSBindingName("countOfExcludedReadOnlyMatches"))

			// Update UI dependent on “count of matches”
			countOfMatches = 0
			countOfExcludedMatches = 0
			countOfReadOnlyMatches = 0
			countOfExcludedReadOnlyMatches = 0
		}

		let fresh = FFResultNode()
		results = fresh
		resultsViewController?.results = fresh
	}

	private func setDocumentSearch(_ newSearcher: FFDocumentSearch?) {
		clearMatches()

		if let existing = documentSearchStorage {
			existing.removeObserver(self, forKeyPath: "currentPath")
			NotificationCenter.default.removeObserver(self, name: NSNotification.Name.FFDocumentSearchDidReceiveResults, object: existing)
			NotificationCenter.default.removeObserver(self, name: NSNotification.Name.FFDocumentSearchDidFinish, object: existing)
			existing.stop()
		}

		documentSearchStorage = newSearcher

		if let newSearcher {
			statusBarViewController?.progressIndicatorVisible = true
			statusString            = "Searching…"
			showsResultsOutlineView = true
			resultsViewController?.hideCheckBoxes = false

			NotificationCenter.default.addObserver(self, selector: #selector(folderSearchDidReceiveResults(_:)), name: NSNotification.Name.FFDocumentSearchDidReceiveResults, object: newSearcher)
			NotificationCenter.default.addObserver(self, selector: #selector(folderSearchDidFinish(_:)), name: NSNotification.Name.FFDocumentSearchDidFinish, object: newSearcher)
			newSearcher.addObserver(self, forKeyPath: "currentPath", options: [ .new, .old ], context: nil)
			performingFolderSearch = true
			newSearcher.start()
		}
	}

	@objc(acceptMatches:)
	func acceptMatches(_ matches: [OakDocumentMatch]) {
		let countOfExistingItems = results?.children?.count ?? 0

		var parent: FFResultNode?
		for match in matches {
			FFSetMarkForMatch(match, kSearchMarkIdentifier)

			let node = FFResultNode.resultNode(with: match)
			if parent == nil || !(parent?.document?.isEqual(node.document) ?? false) {
				let branch = FFResultNode.resultNode(with: match, baseDirectory: CommonAncestor(documentSearchStorage?.paths as? [String] ?? []))
				parent = branch
				results?.addResultNode(branch)
			}
			parent?.addResultNode(node)
		}

		let countAfter = results?.children?.count ?? 0
		resultsViewController?.insertItems(at: IndexSet(integersIn: countOfExistingItems..<max(countOfExistingItems, countAfter)))
	}

	@objc private func folderSearchDidReceiveResults(_ aNotification: Notification) {
		acceptMatches(aNotification.userInfo?["matches"] as? [OakDocumentMatch] ?? [])
	}

	@objc func setUpFindMatches(_ sender: Any?) {
		var findMatches: [FindMatch] = []
		for case let parent as FFResultNode in (results?.children ?? []) {
			guard let identifier = parent.firstResultNode?.document?.identifier,
			      let firstMatch = parent.firstResultNode?.match,
			      let lastMatch  = parent.lastResultNode?.match else { continue }
			findMatches.append(FFFindMatchForRange(identifier, firstMatch, lastMatch))
		}
		self.findMatches = findMatches
	}

	@objc func folderSearchDidFinish(_ aNotification: Notification?) {
		performingFolderSearch = false
		statusBarViewController?.progressIndicatorVisible = false
		guard let results else { return }

		bind(NSBindingName("countOfMatches"), to: results, withKeyPath: "countOfLeafs", options: nil)
		bind(NSBindingName("countOfExcludedMatches"), to: results, withKeyPath: "countOfExcluded", options: nil)
		bind(NSBindingName("countOfReadOnlyMatches"), to: results, withKeyPath: "countOfReadOnly", options: nil)
		bind(NSBindingName("countOfExcludedReadOnlyMatches"), to: results, withKeyPath: "countOfExcludedReadOnly", options: nil)

		setUpFindMatches(self)

		let searchString = documentSearchStorage?.searchString ?? findString
		let msg = Find.resultCountString(forCount: countOfMatches, searchString: searchString)
		if let documentSearch = documentSearchStorage {
			let formatter = NumberFormatter()
			formatter.numberStyle = .decimal
			formatter.maximumFractionDigits = 1
			let seconds = formatter.string(from: NSNumber(value: documentSearch.searchDuration))

			statusString          = msg + Find.searchedFilesSuffix(forFileCount: documentSearch.scannedFileCount, seconds: seconds)
			alternateStatusString = msg + String(format: " (searched %2$@ in %1$@ seconds)", seconds ?? "", ByteCountFormatter.string(fromByteCount: Int64(documentSearch.scannedByteCount), countStyle: .file))
		} else {
			statusString = msg
		}

		// The ObjC++ used `__weak __block id token` so the block could unregister
		// itself on first delivery. A captured Swift `var` is copied into the
		// closure, so assigning it afterwards would not be visible from inside —
		// hence the reference box. `queue: nil` is kept rather than `.main`: it
		// delivers synchronously on the posting thread, which is the main one
		// (OakPasteboard is UI state), and assumeIsolated states that rather than
		// leaving it to be rediscovered.
		let token = ObserverToken()
		token.value = NotificationCenter.default.addObserver(forName: NSNotification.Name.OakPasteboardDidChange, object: OakPasteboard.find, queue: nil) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self else { return }
				self.findMatches = nil
				for case let parent as FFResultNode in (self.results?.children ?? []) {
					parent.document?.removeAllMarks(ofType: kSearchMarkIdentifier)
				}
			}
			if let value = token.value { NotificationCenter.default.removeObserver(value) }
		}
	}

	// nonisolated because NSObject's is, with the body hopping back — the
	// CommitWindow arrangement. The hop is sound rather than hopeful:
	// FFDocumentSearch writes `currentPath` from -updateMatches:, a Timer
	// callback, and a Timer fires on the thread that scheduled it, the main one.
	override nonisolated func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		guard keyPath == "currentPath" else { return }

		// Read the two values out here rather than inside the hop: the change
		// dictionary is `[NSKeyValueChangeKey: Any]` and so not Sendable, while the
		// two Strings are.
		let newValue = change?[.newKey] as? String
		let oldValue = change?[.oldKey] as? String

		MainActor.assumeIsolated {
			let relative = FFSearchProgressRelativePath(newValue, oldValue, searchFolder)
			statusString = String.localizedStringWithFormat("Searching \u{201C}%@\u{201D}\u{2026}", relative ?? "")
		}
	}

	// =============================
	// = Selecting Results Actions =
	// =============================

	@objc func didSelectResult(_ item: FFResultNode) {
		guard let doc = item.document, let match = item.match else { return }
		if !doc.isOpen {
			doc.isRecentTrackingDisabled = true
		}

		doc.matchCaptures = FFCapturesForMatch(match)

		FFSelectMatch(delegate, match, doc)
	}

	@objc func didDoubleClickResult(_ item: FFResultNode) {
		if (UserDefaults.standard.object(forKey: kUserDefaultsKeepSearchResultsOnDoubleClick) as? NSNumber)?.boolValue == true {
			return
		}
		delegate?.bringToFront()
		close()
	}

	@objc func didRemoveResult(_ item: FFResultNode) {
		if OakIsAlternateKeyOrMouseEvent(NSEvent.ModifierFlags.option.rawValue, NSApp.currentEvent) {
			if let path = item.document?.path {
				let relative = FFRelativePath(path, CommonAncestor(documentSearchStorage?.paths as? [String] ?? []))
				globString = (globString ?? "") + "~\(relative ?? "")"
			}
		}

		item.document?.removeAllMarks(ofType: kSearchMarkIdentifier)
		setUpFindMatches(self)

		statusString = Find.shownResultCountString(forCount: countOfMatches, searchString: documentSearchStorage?.searchString)
	}

	// =====================
	// = Show Tab… Submenu =
	// =====================

	@objc func takeSelectedPathFrom(_ sender: Any?) {
		if let item = (sender as? NSMenuItem)?.representedObject as? FFResultNode, let first = item.firstResultNode {
			resultsViewController?.showResultNode(first)
		}
	}

	@objc func updateShowTabMenu(_ aMenu: NSMenu) {
		if countOfMatches == 0 {
			aMenu.addItem(withTitle: "No Results", action: Selector(("nop:")), keyEquivalent: "").isEnabled = false
		} else {
			var key: Int = 0
			for case let parent as FFResultNode in (results?.children ?? []) {
				guard let doc = parent.document else { continue }

				let title: String
				if let path = doc.path {
					title = FFRelativePath(path, searchFolder) ?? doc.displayName
				} else {
					title = doc.displayName
				}

				let keyEquivalent: String
				if key < 9 {
					key += 1
					keyEquivalent = String(UnicodeScalar(UInt8(48 + (key % 10))))
				} else {
					keyEquivalent = ""
				}

				let item = aMenu.addItem(withTitle: title, action: #selector(takeSelectedPathFrom(_:)), keyEquivalent: keyEquivalent)
				if aMenu.propertiesToUpdate.contains(.propertyItemImage) {
					item.image = parent.document?.icon
				}
				item.representedObject = parent
			}
		}
	}

	// =====================
	// = Copy Find Results =
	// =====================

	@objc func copyReplacements(_ sender: Any?) {
		var array: [String] = []

		for item in (resultsViewController?.selectedResults ?? []) {
			guard let match = item.match else { continue }
			let captures = FFCapturesForMatch(match)
			array.append((captures?.isEmpty ?? true) ? replaceString : (FFExpandFormatString(replaceString, match) ?? replaceString))
		}

		NSPasteboard.general.clearContents()
		NSPasteboard.general.writeObjects([ array.joined(separator: "\n") as NSString ])
	}

	private func copyLines(entireLines: Bool, withFilename: Bool) {
		var array: [String] = []

		for item in (resultsViewController?.selectedResults ?? []) {
			guard let m = item.match else { continue }
			if let str = FFCopyStringForMatch(m, item.path, entireLines, withFilename) {
				array.append(str)
			}
		}

		NSPasteboard.general.clearContents()
		NSPasteboard.general.writeObjects([ array.joined(separator: "\n") as NSString ])
	}

	@objc func copy(_ sender: Any?)                          { copyLines(entireLines: true,  withFilename: false) }
	@objc func copyMatchingParts(_ sender: Any?)             { copyLines(entireLines: false, withFilename: false) }
	@objc func copyMatchingPartsWithFilename(_ sender: Any?) { copyLines(entireLines: false, withFilename: true)  }
	@objc func copyEntireLines(_ sender: Any?)               { copyLines(entireLines: true,  withFilename: false) }
	@objc func copyEntireLinesWithFilename(_ sender: Any?)   { copyLines(entireLines: true,  withFilename: true)  }

	// =====================
	// = Check/Uncheck All =
	// =====================

	private func allMatchesSetExclude(_ exclude: Bool) {
		results?.excluded = exclude
	}

	@objc func checkAll(_ sender: Any?)   { allMatchesSetExclude(false) }
	@objc func uncheckAll(_ sender: Any?) { allMatchesSetExclude(true)  }

	func validateMenuItem(_ aMenuItem: NSMenuItem) -> Bool {
		var res = true
		let copyActions: Set<Selector> = [ #selector(copy(_:)), #selector(copyReplacements(_:)), #selector(copyMatchingParts(_:)), #selector(copyMatchingPartsWithFilename(_:)), #selector(copyEntireLines(_:)), #selector(copyEntireLinesWithFilename(_:)) ]

		if let action = aMenuItem.action, copyActions.contains(action) {
			res = results?.countOfLeafs != 0
		} else if aMenuItem.action == #selector(checkAll(_:)) {
			res = countOfExcludedMatches > countOfExcludedReadOnlyMatches
		} else if aMenuItem.action == #selector(uncheckAll(_:)) {
			res = countOfExcludedMatches &- countOfExcludedReadOnlyMatches < countOfMatches &- countOfReadOnlyMatches
		} else if aMenuItem.action == #selector(toggleSearchHiddenFolders(_:)) {
			aMenuItem.state = searchHiddenFolders ? .on : .off
		} else if aMenuItem.action == #selector(toggleSearchFolderLinks(_:)) {
			aMenuItem.state = searchFolderLinks ? .on : .off
		} else if aMenuItem.action == #selector(toggleSearchFileLinks(_:)) {
			aMenuItem.state = searchFileLinks ? .on : .off
		} else if aMenuItem.action == #selector(toggleSearchBinaryFiles(_:)) {
			aMenuItem.state = searchBinaryFiles ? .on : .off
		} else if aMenuItem.action == #selector(goToParentFolder(_:)) {
			res = searchFolder != nil || (searchTargetStorage == .fileBrowserItems && CommonAncestor(fileBrowserItems ?? []) != nil)
		} else if aMenuItem.action == #selector(goBack(_:)) {
			res = (wherePopUpButton?.menu?.indexOfItem(withTarget: self, andAction: aMenuItem.action) ?? -1) != -1
		} else if aMenuItem.action == #selector(goForward(_:)) {
			res = (wherePopUpButton?.menu?.indexOfItem(withTarget: self, andAction: aMenuItem.action) ?? -1) != -1 || (searchTargetStorage == .other && otherFolder != nil)
		}
		return res
	}
}
