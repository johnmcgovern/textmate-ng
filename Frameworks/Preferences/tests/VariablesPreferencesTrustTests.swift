import XCTest

// Settings ▸ Variables ▸ Project Folders: every folder the user has answered the
// folder-trust question for, so a mistaken answer can be seen and changed.
//
// Driven the way AppKit drives it — the pane created by name through -init, the
// table and button found by identifier, rows read and edited through the table's
// own data source — because the pane is internal to the Preferences module and a
// test that reached past that would be testing a different path from the one a
// click takes. Like FolderTrustTests these write real preferences, so each one
// records what was there and puts it back.
final class VariablesPreferencesTrustTests: XCTestCase {
	private var savedTrusted: [String]?
	private var savedRefused: [String]?

	override func setUp() {
		savedTrusted = UserDefaults.standard.stringArray(forKey: "TrustedProjectFolders")
		savedRefused = UserDefaults.standard.stringArray(forKey: "RefusedProjectFolders")
		UserDefaults.standard.removeObject(forKey: "TrustedProjectFolders")
		UserDefaults.standard.removeObject(forKey: "RefusedProjectFolders")
	}

	override func tearDown() {
		if let savedTrusted { UserDefaults.standard.set(savedTrusted, forKey: "TrustedProjectFolders") }
		else { UserDefaults.standard.removeObject(forKey: "TrustedProjectFolders") }
		if let savedRefused { UserDefaults.standard.set(savedRefused, forKey: "RefusedProjectFolders") }
		else { UserDefaults.standard.removeObject(forKey: "RefusedProjectFolders") }
	}

	// Hosted in a window, not left bare: a table with no window does not deliver
	// its selection-changed callback, so the minus button's enabled state never
	// followed the selection and the forget test failed for a reason no user
	// could ever hit. Kept alive for the test's duration.
	private var window: NSWindow?

	@MainActor private func pane() -> NSViewController {
		let type = NSClassFromString("VariablesPreferences") as! NSViewController.Type
		let pane = type.init()
		let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 622, height: 454), styleMask: [.titled], backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
		window.contentViewController = pane
		self.window = window
		return pane
	}

	@MainActor private func find<T: NSView>(_ identifier: String, in view: NSView, as type: T.Type) -> T? {
		if view.identifier?.rawValue == identifier, let match = view as? T { return match }
		for sub in view.subviews { if let hit = find(identifier, in: sub, as: type) { return hit } }
		return nil
	}

	@MainActor private func rows(_ table: NSTableView) -> [(allowed: Bool, folder: String)] {
		let source = table.dataSource!
		let allowed = table.tableColumns.first { $0.identifier.rawValue == "allowed" }!
		let folder  = table.tableColumns.first { $0.identifier.rawValue == "folder" }!
		return (0..<source.numberOfRows!(in: table)).map { row in
			((source.tableView!(table, objectValueFor: allowed, row: row) as! NSNumber).boolValue,
			 source.tableView!(table, objectValueFor: folder, row: row) as! String)
		}
	}

	// The control: nothing answered, nothing listed — so the rows below come from
	// the answers and not from somewhere else.
	@MainActor func testNoAnswersNoRows() {
		let table = find("answeredFolders", in: pane().view, as: NSTableView.self)!
		XCTAssertEqual(rows(table).count, 0)
	}

	@MainActor func testBothAnswersAreListedWithTheirState() {
		TMFolderTrust.shared.trust("/tmp/allowed-checkout")
		TMFolderTrust.shared.refuse("/tmp/refused-checkout")
		let table = find("answeredFolders", in: pane().view, as: NSTableView.self)!
		let listed = rows(table)
		XCTAssertEqual(listed.count, 2)
		XCTAssertEqual(listed.first { $0.folder == "/tmp/allowed-checkout" }?.allowed, true)
		XCTAssertEqual(listed.first { $0.folder == "/tmp/refused-checkout" }?.allowed, false)
	}

	// Unticking a folder is a refusal, not a deletion: it stays listed, and the
	// store says it is no longer trusted. Ticking it again trusts it.
	@MainActor func testTheCheckboxChangesTheAnswer() {
		TMFolderTrust.shared.trust("/tmp/checkout")
		let table = find("answeredFolders", in: pane().view, as: NSTableView.self)!
		let allowed = table.tableColumns.first { $0.identifier.rawValue == "allowed" }!

		table.dataSource!.tableView!(table, setObjectValue: NSNumber(value: false), for: allowed, row: 0)
		XCTAssertFalse(TMFolderTrust.shared.isTrusted("/tmp/checkout/.tm_properties"))
		XCTAssertTrue(TMFolderTrust.shared.hasBeenAskedAbout("/tmp/checkout"))
		XCTAssertEqual(rows(table).first?.allowed, false)

		table.dataSource!.tableView!(table, setObjectValue: NSNumber(value: true), for: allowed, row: 0)
		XCTAssertTrue(TMFolderTrust.shared.isTrusted("/tmp/checkout/.tm_properties"))
	}

	// Forgetting removes the row and the answer, so the folder is asked again.
	@MainActor func testForgettingRemovesTheAnswer() {
		TMFolderTrust.shared.trust("/tmp/checkout")
		let view = pane().view
		let table  = find("answeredFolders", in: view, as: NSTableView.self)!
		let forget = find("forgetFolder", in: view, as: NSButton.self)!

		XCTAssertFalse(forget.isEnabled, "nothing selected, nothing to forget")
		table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
		XCTAssertTrue(forget.isEnabled)
		forget.performClick(nil)
		XCTAssertEqual(rows(table).count, 0)
		XCTAssertFalse(TMFolderTrust.shared.hasBeenAskedAbout("/tmp/checkout"))
	}
}
