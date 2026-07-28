// Nib-contract tests for the 8 Bundle Editor property xibs (Phase 4).
//
// These exist because nib wiring fails *silently*: renaming the Swift class, an
// @IBOutlet, or a bound key path produces no build error and no crash — just an
// empty pane, discovered whenever a user next opens that inspector. Before this
// suite the only check was launching the app and looking, and for BundleEditor
// even that was not possible (NSBrowser would not take a synthetic selection).
//
// One test method per nib, deliberately: a loop over all eight would let a single
// bad nib abort the whole bundle and hide which one it was.
//
// What the assertions pin down:
//   * view loads       -> the xib exists and its File's Owner custom class still
//                         resolves to PropertiesViewController
//   * objectController -> the outlet name matches; every field in these xibs
//                         binds through it, so nil here means an empty pane
//   * labelWidth       -> derived from the `alignmentView` outlet, so it tells
//                         "connected" apart from "silently nil" (the getter falls
//                         back to 20 when the outlet is nil)
import XCTest

final class PropertiesNibTests: XCTestCase {

	/// Loads the nib and asserts the contracts shared by all 8 xibs.
	/// - Parameter hasAlignmentView: 5 of the 8 xibs carry one; the other 3 lay
	///   out without it, so the expectation is part of the contract being pinned.
	@MainActor private func assertNibContract(_ name: String, hasAlignmentView: Bool,
	                                          file: StaticString = #filePath, line: UInt = #line) throws {
		let controller = try XCTUnwrap(PropertiesViewController(name: name),
		                               "\(name): controller could not be created", file: file, line: line)

		let view = controller.view
		XCTAssertFalse(view.subviews.isEmpty,
		               "\(name): nib loaded but produced an empty view", file: file, line: line)

		XCTAssertNotNil(controller.value(forKey: "objectController"),
		                "\(name): objectController outlet is nil — every field in this xib binds through it",
		                file: file, line: line)

		if hasAlignmentView {
			XCTAssertNotNil(controller.value(forKey: "alignmentView"),
			                "\(name): alignmentView outlet is nil", file: file, line: line)
			XCTAssertGreaterThan(controller.labelWidth, 20,
			                     "\(name): labelWidth fell back to 20, so alignmentView did not connect",
			                     file: file, line: line)
		} else {
			XCTAssertEqual(controller.labelWidth, 20, accuracy: 0.001,
			               "\(name): unexpectedly has an alignmentView — update this test if the xib changed",
			               file: file, line: line)
		}
	}

	@MainActor func testBundlePropertiesNib()   throws { try assertNibContract("BundleProperties",   hasAlignmentView: true) }
	@MainActor func testCommandPropertiesNib()  throws { try assertNibContract("CommandProperties",  hasAlignmentView: true) }
	@MainActor func testGrammarPropertiesNib()  throws { try assertNibContract("GrammarProperties",  hasAlignmentView: true) }
	@MainActor func testSharedPropertiesNib()   throws { try assertNibContract("SharedProperties",   hasAlignmentView: true) }
	@MainActor func testThemePropertiesNib()    throws { try assertNibContract("ThemeProperties",    hasAlignmentView: true) }
	@MainActor func testFileDropPropertiesNib() throws { try assertNibContract("FileDropProperties", hasAlignmentView: false) }
	@MainActor func testMacroPropertiesNib()    throws { try assertNibContract("MacroProperties",    hasAlignmentView: false) }
	@MainActor func testSnippetPropertiesNib()  throws { try assertNibContract("SnippetProperties",  hasAlignmentView: false) }

	// The `properties` key path is what the xibs' object controllers take as
	// content, and the getter commits editing before returning it.
	@MainActor func testPropertiesDictionaryIsKVCReachable() throws {
		let controller = try XCTUnwrap(PropertiesViewController(name: "SharedProperties"))
		_ = controller.view
		XCTAssertNotNil(controller.value(forKey: "properties"), "`properties` is not KVC-reachable")

		controller.properties = ["name": "test"]
		XCTAssertEqual(controller.properties["name"] as? String, "test")
	}

	// SharedProperties is the only xib carrying an OakKeyEquivalentView, which
	// PropertiesViewController.loadView binds to selection.keyEquivalent.
	@MainActor func testSharedPropertiesHasKeyEquivalentView() throws {
		let controller = try XCTUnwrap(PropertiesViewController(name: "SharedProperties"))
		_ = controller.view
		XCTAssertNotNil(controller.value(forKey: "keyEquivalentView"),
		                "SharedProperties: keyEquivalentView outlet is nil — loadView binds it to selection.keyEquivalent")
	}
}
