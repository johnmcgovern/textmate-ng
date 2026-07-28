// Nib-contract test for TerminalPreferences.xib — the only nib-backed
// preferences pane (Phase 4).
//
// The xib stores five outlet names, a File's Owner class name, and four bound key
// paths, one of which (`installIndicaitorImage`) carries an original misspelling
// that must be preserved. None of that is checked by the compiler; all of it
// fails silently at runtime.
//
// IMPORTANT — this test deliberately does NOT go through
// `-[NSViewController view]`. TerminalPreferences.loadView() calls
// LSSetDefaultHandlerForURLScheme("txmt", …), which would register the *test
// runner* as the system-wide handler for txmt:// URLs on whatever machine ran the
// suite. Instantiating the nib directly with the controller as File's Owner
// exercises exactly the contracts under test (class lookup, outlet connection,
// binding key paths) without invoking loadView's side effects.
import XCTest

final class TerminalPreferencesNibTests: XCTestCase {

	/// The outlets the xib connects on File's Owner. `@IBOutlet` implies `@objc`,
	/// so these are reachable by KVC even though they are `private` in Swift.
	private static let outletNames = [
		"installStatusText",
		"installSummaryText",
		"installPathPopUp",
		"installButton",
		"rmateSummaryText",
	]

	@MainActor private func loadNib() throws -> TerminalPreferences {
		let controller = TerminalPreferences()
		let bundle = Bundle(for: TerminalPreferences.self)
		let nib = try XCTUnwrap(NSNib(nibNamed: "TerminalPreferences", bundle: bundle),
		                        "TerminalPreferences.xib not found in \(bundle.bundlePath)")
		XCTAssertTrue(nib.instantiate(withOwner: controller, topLevelObjects: nil),
		              "nib failed to instantiate — check File's Owner is still TerminalPreferences")
		return controller
	}

	@MainActor func testNibInstantiatesWithTheSwiftControllerAsOwner() throws {
		_ = try loadNib()
	}

	@MainActor func testEveryOutletIsConnected() throws {
		let controller = try loadNib()
		for name in Self.outletNames {
			XCTAssertNotNil(controller.value(forKey: name),
			                "outlet ‘\(name)’ is nil — the xib's outlet name and the @IBOutlet must match")
		}
	}

	// The xib binds `installIndicaitorImage` (sic). Fixing the spelling in Swift
	// without editing the xib silently breaks the status indicator, so pin it.
	@MainActor func testMisspelledInstallIndicatorKeyPathIsIntact() throws {
		let controller = TerminalPreferences()
		XCTAssertNoThrow(controller.value(forKey: "installIndicaitorImage"),
		                 "the xib binds ‘installIndicaitorImage’ — the misspelling is load-bearing")
		XCTAssertFalse(controller.responds(to: NSSelectorFromString("installIndicatorImage")),
		               "a correctly-spelled property appeared; the xib binding must be updated in the same change")
	}

	// disableRMate / interface / port are bound by the xib but are not properties:
	// PreferencesPane routes them through value(forUndefinedKey:) to NSUserDefaults.
	// If that routing regresses, these key paths raise instead of returning a value.
	@MainActor func testDefaultsBackedKeyPathsResolveThroughKVCRouting() throws {
		let controller = TerminalPreferences()
		for key in ["disableRMate", "interface", "port"] {
			XCTAssertNoThrow(controller.value(forKey: key),
			                 "‘\(key)’ did not resolve — PreferencesPane's undefined-key routing regressed")
		}
	}
}
