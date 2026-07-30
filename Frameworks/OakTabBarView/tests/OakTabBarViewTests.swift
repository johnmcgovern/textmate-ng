// Tests for the Swift OakTabBarView (Phase 4).
//
// The framework had no coverage at all when it was ported — 1234 lines of
// layout, KVO and drag logic rewritten with nothing but a manual pass in the
// running app underneath it. These drive the tab bar through its *public* ObjC
// surface, which is deliberate: that surface is a hand-written header
// (OakTabBarView.h) with no build-time check against the Swift implementation,
// and DocumentWindowController is the only other thing that would notice a
// drift — at runtime, as an unrecognized selector.
//
// Everything here is headless. The tab bar needs no window: reloadData drives
// the layout, and the resulting tab views are ordinary subviews with frames.
import XCTest

// MARK: - Test doubles

/// Feeds the bar a fixed list of documents, the way DocumentWindowController does.
final class StubTabDataSource: NSObject, OakTabBarViewDataSource {
	struct Row {
		var title: String
		var path: String?
		var uuid = UUID()
		var edited = false
	}

	var rows: [Row]

	init(titles: [String]) {
		self.rows = titles.map { Row(title: $0, path: "/tmp/\($0)") }
	}

	func numberOfRows(in aTabBarView: OakTabBarView) -> UInt {
		UInt(rows.count)
	}

	func tabBarView(_ aTabBarView: OakTabBarView, titleFor anIndex: UInt) -> String {
		rows[Int(anIndex)].title
	}

	func tabBarView(_ aTabBarView: OakTabBarView, pathFor anIndex: UInt) -> String {
		rows[Int(anIndex)].path ?? ""
	}

	func tabBarView(_ aTabBarView: OakTabBarView, uuidFor anIndex: UInt) -> UUID {
		rows[Int(anIndex)].uuid
	}

	func tabBarView(_ aTabBarView: OakTabBarView, isEditedAt anIndex: UInt) -> Bool {
		rows[Int(anIndex)].edited
	}
}

/// Records what the bar asks of its delegate. `closedTags` captures `[sender tag]`
/// at call time because that is exactly how DocumentWindowController learns which
/// tab to close — the tag is transient state on the sender, not an argument.
final class SpyTabDelegate: NSObject, OakTabBarViewDelegate {
	var closedTags: [Int] = []
	var closedOtherTags: [Int] = []
	var shouldSelectCalls: [UInt] = []
	var doubleClickedIndexes: [UInt] = []
	var didRequestNewTab = false

	func performCloseTab(_ sender: OakTabBarView) {
		closedTags.append(sender.tag)
	}

	func performCloseOtherTabsXYZ(_ sender: OakTabBarView) {
		closedOtherTags.append(sender.tag)
	}

	func tabBarView(_ aTabBarView: OakTabBarView, shouldSelect anIndex: UInt) -> Bool {
		shouldSelectCalls.append(anIndex)
		return true
	}

	func tabBarView(_ aTabBarView: OakTabBarView, didDoubleClick anIndex: UInt) {
		doubleClickedIndexes.append(anIndex)
	}

	func tabBarViewDidDoubleClick(_ aTabBarView: OakTabBarView) {
		didRequestNewTab = true
	}
}

// MARK: - Tests

final class OakTabBarViewTests: XCTestCase {

	/// 1400pt is wide enough for several tabs at the 250pt maximum.
	@MainActor private func makeBar(width: CGFloat = 1400, titles: [String]) -> (OakTabBarView, StubTabDataSource, SpyTabDelegate) {
		let bar = OakTabBarView(frame: NSMakeRect(0, 0, width, 23))
		let dataSource = StubTabDataSource(titles: titles)
		let delegate = SpyTabDelegate()
		bar.dataSource = dataSource
		bar.delegate = delegate
		bar.reloadData()
		return (bar, dataSource, delegate)
	}

	/// The tab views the bar created. The trailing filler view is also an
	/// OakTabView but carries no tab item, so it is not an accessibility element.
	@MainActor private func tabViews(of bar: OakTabBarView) -> [NSView] {
		bar.subviews.filter { $0.accessibilityRole() == .radioButton && $0.accessibilityLabel() != nil }
	}

	// MARK: Public header contract

	// OakTabBarView.h is hand-written and the class is Swift; nothing checks the
	// two against each other at build time. Every member declared there is
	// exercised somewhere in this file, but the plain existence check is kept
	// separate so a rename fails with an obvious message rather than a crash.
	@MainActor func testPublicHeaderContractIsSatisfiedByTheSwiftImplementation() {
		let bar = OakTabBarView(frame: .zero)
		for selector in ["delegate", "setDelegate:", "dataSource", "setDataSource:",
		                 "countOfVisibleTabs", "selectedTabIndex", "setSelectedTabIndex:",
		                 "reloadData", "performClose:",
		                 "neverHideLeftBorder", "setNeverHideLeftBorder:",
		                 "tag"] {
			XCTAssertTrue(bar.responds(to: NSSelectorFromString(selector)),
			              "OakTabBarView.h declares ‘\(selector)’ but the Swift class does not implement it — this is an unrecognized selector in the running app")
		}
	}

	@MainActor func testIntrinsicHeightIsTheTabBarHeight() {
		let bar = OakTabBarView(frame: .zero)
		XCTAssertEqual(bar.intrinsicContentSize.height, 23)
		XCTAssertEqual(bar.intrinsicContentSize.width, NSView.noIntrinsicMetric)
	}

	// MARK: Data source

	@MainActor func testReloadDataCreatesOneTabPerRow() {
		let (bar, _, _) = makeBar(titles: ["alpha.txt", "beta.txt", "gamma.txt"])
		XCTAssertEqual(tabViews(of: bar).count, 3)
	}

	@MainActor func testTitlesComeFromTheDataSource() {
		let (bar, _, _) = makeBar(titles: ["alpha.txt", "beta.txt", "gamma.txt"])
		XCTAssertEqual(tabViews(of: bar).compactMap { $0.accessibilityLabel() },
		               ["alpha.txt", "beta.txt", "gamma.txt"])
	}

	// The label reads through to the tab item, so it reflects the edited state
	// whether or not anything observed it. Kept as a label test only — the KVO
	// chain is covered by testEditedStateSwapsTheCloseButtonImage below.
	@MainActor func testEditedStateShowsInTheTabAccessibilityLabel() {
		let (bar, dataSource, _) = makeBar(titles: ["alpha.txt", "beta.txt"])
		XCTAssertEqual(tabViews(of: bar).first?.accessibilityLabel(), "alpha.txt")

		dataSource.rows[0].edited = true
		bar.reloadData()

		XCTAssertEqual(tabViews(of: bar).first?.accessibilityLabel(), "alpha.txt (modified)")
	}

	/// The tab's close button, reached without needing OakRolloverButton's type:
	/// `regularImage` is the image it draws when idle.
	@MainActor private func closeButtonImage(of tabView: NSView) -> NSImage? {
		for subview in tabView.subviews where subview is NSButton {
			if let image = subview.value(forKey: "regularImage") as? NSImage,
			   subview.accessibilityLabel() == "Close tab" {
				return image
			}
		}
		return nil
	}

	// THE KVO CHAIN. `modified` on the tab *view* is set only from the
	// observation of the tab *item*, and its one visible effect is swapping the
	// close button between the X and the modified-document dot. Nothing else
	// reads it, so this is the assertion that fails if OakTabItem.modified loses
	// its `dynamic` — a plain `@objc` property stores straight to the backing
	// field and the observation never fires. Verified by mutation: dropping
	// `dynamic` makes this test, and only this test, fail.
	@MainActor func testEditedStateSwapsTheCloseButtonImageThroughKVO() throws {
		let (bar, dataSource, _) = makeBar(titles: ["alpha.txt", "beta.txt"])
		let tab = try XCTUnwrap(tabViews(of: bar).first)
		let cleanImage = try XCTUnwrap(closeButtonImage(of: tab), "the tab has no close button")

		dataSource.rows[0].edited = true
		bar.reloadData()

		let dirtyImage = try XCTUnwrap(closeButtonImage(of: tab))
		XCTAssertFalse(cleanImage === dirtyImage,
		               "the close button still shows the unmodified image — the modified observation did not fire, so OakTabItem.modified is no longer `@objc dynamic`")
	}

	@MainActor func testRenamingADocumentUpdatesTheExistingTab() {
		let (bar, dataSource, _) = makeBar(titles: ["alpha.txt", "beta.txt"])
		dataSource.rows[1].title = "renamed.txt"
		bar.reloadData()

		XCTAssertEqual(tabViews(of: bar).compactMap { $0.accessibilityLabel() },
		               ["alpha.txt", "renamed.txt"])
	}

	@MainActor func testRemovingRowsRemovesTabs() {
		let (bar, dataSource, _) = makeBar(titles: ["alpha.txt", "beta.txt", "gamma.txt"])
		dataSource.rows.removeLast()
		bar.reloadData()

		XCTAssertEqual(tabViews(of: bar).count, 2)
	}

	// MARK: Selection

	@MainActor func testSelectedTabIndexRoundTrips() {
		let (bar, _, _) = makeBar(titles: ["alpha.txt", "beta.txt", "gamma.txt"])
		bar.selectedTabIndex = 1
		XCTAssertEqual(bar.selectedTabIndex, 1)
	}

	@MainActor func testSelectedTabIndexIsNotFoundWhenNothingIsSelected() {
		let (bar, _, _) = makeBar(titles: ["alpha.txt", "beta.txt"])
		XCTAssertEqual(bar.selectedTabIndex, UInt(NSNotFound))
	}

	@MainActor func testSelectingATabDeselectsTheOthers() {
		let (bar, _, _) = makeBar(titles: ["alpha.txt", "beta.txt", "gamma.txt"])
		bar.selectedTabIndex = 2
		bar.selectedTabIndex = 0
		XCTAssertEqual(bar.selectedTabIndex, 0)

		// Exactly one tab reports itself selected (AXValue is the selected flag).
		let selected = tabViews(of: bar).filter { ($0.accessibilityValue() as? NSNumber)?.boolValue == true }
		XCTAssertEqual(selected.count, 1)
		XCTAssertEqual(selected.first?.accessibilityLabel(), "alpha.txt")
	}

	// REGRESSION, and the reason selectedTabIndex is UInt rather than Int:
	// DocumentWindowController passes `MIN(_selectedTabIndex, _documents.count-1)`,
	// which is NSUIntegerMax when the document list is empty. Unsigned, that
	// fails the `< count` guard harmlessly — what the ObjC++ original did. Typed
	// Int on the Swift side it arrives as -1, *passes* the guard, and indexes the
	// array out of bounds.
	//
	// Note what each half of this guards. The typed assignment below pins the
	// declared type at compile time (reverting to Int stops the build). The KVC
	// assignment is the runtime half: it dispatches through the property's ObjC
	// type encoding, exactly as an ObjC caller does, so it would still deliver
	// -1 into a signed property and crash. Verified by mutation.
	@MainActor func testOutOfRangeSelectedTabIndexIsIgnoredRatherThanCrashing() {
		let (bar, _, _) = makeBar(titles: ["alpha.txt", "beta.txt"])

		bar.selectedTabIndex = UInt.max
		XCTAssertEqual(bar.selectedTabIndex, UInt(NSNotFound), "no tab should be selected")

		bar.selectedTabIndex = 99
		XCTAssertEqual(bar.selectedTabIndex, UInt(NSNotFound))
	}

	@MainActor func testOutOfRangeSelectedTabIndexFromAnObjCCallerIsIgnored() {
		let (bar, _, _) = makeBar(titles: ["alpha.txt", "beta.txt"])

		// NSUIntegerMax the way DocumentWindowController's `count-1` produces it.
		bar.setValue(NSNumber(value: UInt.max), forKey: "selectedTabIndex")
		XCTAssertEqual(bar.selectedTabIndex, UInt(NSNotFound),
		               "an out-of-range index from an ObjC caller must select nothing, not index out of bounds")
	}

	@MainActor func testSelectionSurvivesAReload() {
		let (bar, _, _) = makeBar(titles: ["alpha.txt", "beta.txt", "gamma.txt"])
		bar.selectedTabIndex = 1
		bar.reloadData()
		XCTAssertEqual(bar.selectedTabIndex, 1, "reloadData must reuse the existing tab items, preserving their selected flag")
	}

	// MARK: Delegate

	// performClose: sets `tag` to the closing tab's index before messaging the
	// delegate, because DocumentWindowController reads `[sender tag]` to decide
	// what to close. Losing that ordering closes the wrong document.
	@MainActor func testPerformCloseTellsTheDelegateWhichTabViaTag() {
		let (bar, _, delegate) = makeBar(titles: ["alpha.txt", "beta.txt", "gamma.txt"])
		bar.selectedTabIndex = 2
		bar.performClose(nil)

		XCTAssertEqual(delegate.closedTags, [2])
	}

	@MainActor func testPerformCloseWithNoSelectionClosesNothing() {
		let (bar, _, delegate) = makeBar(titles: ["alpha.txt", "beta.txt"])
		bar.performClose(nil)
		XCTAssertTrue(delegate.closedTags.isEmpty)
	}

	// MARK: Layout

	// With room to spare every tab gets the maximum width (250) rather than
	// stretching to fill the bar.
	@MainActor func testTabsTakeTheMaximumWidthWhenThereIsRoom() {
		let (bar, _, _) = makeBar(width: 1400, titles: ["alpha.txt", "beta.txt", "gamma.txt"])
		let widths = tabViews(of: bar).map { NSWidth($0.frame) }

		XCTAssertEqual(widths.count, 3)
		for width in widths {
			XCTAssertEqual(width, 250, accuracy: 0.5, "a tab should stop growing at tabItemMaxWidth")
		}
	}

	// Past that point the supply/demand pass shares the bar out among the tabs.
	// The invariant that matters is that they tile it: no gaps, no overlap, and
	// no tab collapsing to nothing.
	@MainActor func testTabsShareTheBarWhenSpaceIsTight() {
		let width: CGFloat = 700
		let (bar, _, _) = makeBar(width: width, titles: ["a.txt", "b.txt", "c.txt", "d.txt", "e.txt"])
		let frames = tabViews(of: bar).map { $0.frame }.sorted { NSMinX($0) < NSMinX($1) }

		XCTAssertFalse(frames.isEmpty)
		for frame in frames {
			XCTAssertGreaterThan(NSWidth(frame), 0, "no tab may collapse to zero width")
			XCTAssertLessThan(NSWidth(frame), 250, "tabs must shrink below the maximum once the bar is full")
		}

		// Tabs are laid out edge to edge, starting one point off the left edge.
		XCTAssertEqual(NSMinX(frames[0]), -1, accuracy: 0.5)
		for (lhs, rhs) in zip(frames, frames.dropFirst()) {
			XCTAssertEqual(NSMaxX(lhs), NSMinX(rhs), accuracy: 0.5, "tabs must tile without gaps or overlap")
		}
	}

	// Once the documents outnumber the tabs that fit, the bar stops making tabs.
	@MainActor func testTabCountIsCappedByTheAvailableWidth() {
		let titles = (1...20).map { "file\($0).txt" }
		let (bar, _, _) = makeBar(width: 700, titles: titles)

		let count = tabViews(of: bar).count
		XCTAssertLessThan(count, titles.count, "20 documents cannot fit in a 700pt bar")
		XCTAssertGreaterThan(count, 0)
	}

	// The selected document is always given one of the visible slots, even when
	// it sorts far past the cut-off — this is makeLayout's `didIncludeSelected`
	// branch, and it is the reason a tab bar never hides the document you are
	// looking at.
	@MainActor func testTheSelectedTabIsAlwaysVisibleEvenWhenItWouldOverflow() {
		let titles = (1...20).map { "file\($0).txt" }
		let (bar, _, _) = makeBar(width: 700, titles: titles)

		bar.selectedTabIndex = 19 // the last document, far beyond the cut-off
		let labels = tabViews(of: bar).compactMap { $0.accessibilityLabel() }

		XCTAssertTrue(labels.contains("file20.txt"),
		              "the selected document must keep a visible tab; got \(labels)")
	}

	// MARK: countOfVisibleTabs

	// Was an auto-synthesized readonly property nothing ever assigned — it
	// reported 0 in the ObjC++ original and in the first Swift port. Fixed
	// 2026-07-29 to report what the layout actually admits.
	@MainActor func testCountOfVisibleTabsReportsTheTabsOnScreen() {
		let (bar, _, _) = makeBar(width: 1400, titles: ["alpha.txt", "beta.txt", "gamma.txt"])
		XCTAssertEqual(bar.countOfVisibleTabs, 3)
		XCTAssertEqual(bar.countOfVisibleTabs, tabViews(of: bar).count,
		               "the reported count must match the tabs actually laid out")
	}

	@MainActor func testCountOfVisibleTabsIsCappedWhenTabsOverflow() {
		let titles = (1...20).map { "file\($0).txt" }
		let (bar, _, _) = makeBar(width: 700, titles: titles)

		XCTAssertGreaterThan(bar.countOfVisibleTabs, 0)
		XCTAssertLessThan(bar.countOfVisibleTabs, titles.count,
		                  "20 documents cannot fit in a 700pt bar")
		XCTAssertEqual(bar.countOfVisibleTabs, tabViews(of: bar).count)
	}

	@MainActor func testCountOfVisibleTabsIsZeroWithNoDocuments() {
		let (bar, _, _) = makeBar(titles: [])
		XCTAssertEqual(bar.countOfVisibleTabs, 0)
	}

	// A data source's row count is an NSUInteger crossing a protocol boundary, so
	// reloadData converts it with Int(exactly:) — a checked Int() would trap on a
	// value above Int.max, where the ObjC++ original kept it unsigned and carried
	// on. Nothing legitimate produces such a count; the point is that a bad one
	// cannot take the app down as the tab bar reloads.
	@MainActor func testAbsurdRowCountFromTheDataSourceDoesNotTrap() {
		final class AbsurdDataSource: NSObject, OakTabBarViewDataSource {
			func numberOfRows(in aTabBarView: OakTabBarView) -> UInt { UInt.max }
			func tabBarView(_ v: OakTabBarView, titleFor i: UInt) -> String { "x" }
			func tabBarView(_ v: OakTabBarView, pathFor i: UInt) -> String { "" }
			func tabBarView(_ v: OakTabBarView, uuidFor i: UInt) -> UUID { UUID() }
			func tabBarView(_ v: OakTabBarView, isEditedAt i: UInt) -> Bool { false }
		}

		let bar = OakTabBarView(frame: NSMakeRect(0, 0, 1400, 23))
		let dataSource = AbsurdDataSource() // held strongly — dataSource is weak
		bar.dataSource = dataSource
		bar.reloadData() // must not trap
		XCTAssertEqual(bar.countOfVisibleTabs, 0, "an unrepresentable row count should yield no tabs, not a crash")
	}

	// REGRESSION. tabItemMinWidth is a user default, so 0 is reachable
	// (`defaults write … tabItemMinWidth 0`). That makes the slots-available
	// division ±infinity or NaN, and the first Swift port fed it straight into a
	// checked Int() conversion, which traps — the ObjC++ original clamped first
	// and survived. A trap here kills the app as the tab bar lays out.
	//
	// The override goes through the *argument* domain, which is volatile: it has
	// the highest precedence in the defaults search order and is never written to
	// disk, so a crash mid-test cannot leave the value behind. Writing it with
	// `defaults.set` instead persists into the test runner's own domain, and a
	// trapping run then skips the restore and poisons every later run — which is
	// exactly what happened while this fix was being mutation-tested, and is why
	// it is written this way.
	@MainActor func testDegenerateMinimumTabWidthDoesNotTrap() {
		let defaults = UserDefaults.standard
		let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
		defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }

		// Expected counts match what the ObjC++ original produced for the same
		// inputs, which is the bar the port has to clear:
		//   0  → the division is +infinity, so there is effectively no width limit
		//        and every tab fits (MIN(inf, count) == count).
		//   -1 → the slot count is negative and clamps to none (MAX(0, -1374) == 0).
		for (degenerate, expectedVisible) in [(0, 2), (-1, 0)] {
			var domain = original
			domain["tabItemMinWidth"] = degenerate
			defaults.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)

			// Guard against a vacuous pass: if the override did not take effect the
			// bar would just use the normal 120 and prove nothing.
			XCTAssertEqual(defaults.integer(forKey: "tabItemMinWidth"), degenerate,
			               "the argument-domain override did not take effect")

			let bar = OakTabBarView(frame: NSMakeRect(0, 0, 1400, 23))
			// `dataSource` is a weak property: assigning a freshly constructed stub
			// inline lets it deallocate immediately, reloadData() then returns at its
			// `guard let dataSource`, and makeLayout — the code under test — never
			// runs. Hold it strongly. (This test was vacuous until that was fixed.)
			let dataSource = StubTabDataSource(titles: ["alpha.txt", "beta.txt"])
			bar.dataSource = dataSource
			bar.reloadData() // must not trap
			XCTAssertEqual(bar.countOfVisibleTabs, expectedVisible,
			               "tabItemMinWidth=\(degenerate) should behave as the ObjC++ original did")
		}
	}
}

// MARK: - OakTabItem

final class OakTabItemTests: XCTestCase {

	// The pasteboard type is a wire format shared with the drop handler, and it
	// crosses application versions: a tab dragged from an older build into a
	// newer one is matched on this string.
	func testPasteboardTypeIsTheDocumentedWireFormat() {
		XCTAssertEqual(OakTabItem.pasteboardType.rawValue, "com.j23software.TextMate.tabItem")
	}

	func testTabItemRoundTripsThroughThePasteboard() throws {
		let original = OakTabItem(title: "alpha.txt", path: "/tmp/alpha.txt", identifier: UUID().uuidString, modified: true)

		let item = NSPasteboardItem()
		let plist = try XCTUnwrap(original.pasteboardPropertyList(forType: OakTabItem.pasteboardType))
		item.setPropertyList(plist, forType: OakTabItem.pasteboardType)

		// +tabItemFromPasteboardItem: is imported as an initializer: a class method
		// whose name echoes the class becomes init(…) regardless of return type.
		let restored = try XCTUnwrap(OakTabItem(from: item))
		XCTAssertEqual(restored.title, original.title)
		XCTAssertEqual(restored.path, original.path)
		XCTAssertEqual(restored.identifier, original.identifier)
		XCTAssertTrue(restored.isModified)
	}

	// An unmodified, never-saved tab omits both keys rather than writing nulls;
	// the reader treats a missing "modified" as false and a missing "path" as an
	// untitled document.
	func testUntitledUnmodifiedTabOmitsOptionalKeys() throws {
		let original = OakTabItem(title: "untitled", path: nil, identifier: UUID().uuidString, modified: false)
		let plist = try XCTUnwrap(original.pasteboardPropertyList(forType: OakTabItem.pasteboardType) as? [String: Any])

		XCTAssertNil(plist["path"])
		XCTAssertNil(plist["modified"])
		XCTAssertEqual(plist["title"] as? String, "untitled")
	}

	// A tab with a file on disk also offers a file URL, so it can be dropped on
	// Finder; one without a path is draggable only inside the app.
	func testWritableTypesDependOnWhetherTheDocumentExistsOnDisk() {
		let pasteboard = NSPasteboard.general

		let saved = OakTabItem(title: "alpha.txt", path: "/tmp/alpha.txt", identifier: UUID().uuidString, modified: false)
		XCTAssertEqual(saved.writableTypes(for: pasteboard).count, 2)

		let untitled = OakTabItem(title: "untitled", path: nil, identifier: UUID().uuidString, modified: false)
		XCTAssertEqual(untitled.writableTypes(for: pasteboard), [OakTabItem.pasteboardType])
	}
}
