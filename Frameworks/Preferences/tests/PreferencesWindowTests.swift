// Constructing the Settings window — which is to say, the crash that shipped in
// alpha.10 and alpha.11.
//
// `-[AppController showPreferences:]` does nothing but read
// `Preferences.sharedInstance`, and that read built the window, so opening
// Settings segfaulted every time on every machine. Two separate causes, both the
// same mistake:
//
//   1. `OakTransitionViewController` was a Swift `final class` exported to ObjC
//      through a hand-written header (rule 23), and PreferencesViewController
//      subclasses it — legal, because across that boundary ObjC cannot see
//      `final`. Swift had compiled the initialisers assuming no subclass could
//      exist, and `init(nibName:bundle:)` recursed into its own @objc thunk
//      58,000 times until the stack guard page.
//
//   2. `PreferencesViewController` was `final` too, and here the subclasser is
//      **KVO**: NSPanel(contentViewController:) binds the window's title to the
//      controller, so KVO builds an NSKVONotifying_ subclass at run time. That
//      trapped inside swift_objc_classCopyFixupHandler.
//
// Neither is visible to the compiler and neither had a test — the whole suite was
// green through both releases. This is the cheapest possible guard: build the
// thing and see that the process survives.
import XCTest

final class PreferencesWindowTests: XCTestCase {

	/// The one call -[AppController showPreferences:] makes. If either class in
	/// the chain goes `final` again this does not fail, it *crashes the test
	/// runner* — a stack overflow or a runtime trap, not an assertion. That is
	/// still the signal: a bundle that dies here is a Settings menu that dies.
	@MainActor
	func testSharedInstanceConstructsWithoutCrashing() {
		// `Preferences?` because the hand-written header is unannotated; the
		// unwrap is the assertion.
		let controller = Preferences.sharedInstance
		XCTAssertNotNil(controller)

		// The window is built inside init, by NSPanel(contentViewController:) —
		// which is the call that triggers the KVO subclassing.
		XCTAssertNotNil(controller?.window)
	}

	// **No test loads a pane's view, and that is a known gap rather than an
	// oversight.** Attempted 2026-08-18 and reverted: touching `pane.view` runs
	// loadView, whose `bind(…, to: self, …)` calls make AppKit read the value
	// straight back, which routes through PreferencesPane.value(forUndefinedKey:)
	// into settings_t::raw_get — and that asserts on default_settings_path() in a
	// process that never called settings_t::set_default_settings_path. The test
	// bundle cannot: that is a C++ API, this bundle compiles Swift only
	// (`tests tests/*.swift`), so reaching it needs an ObjC++ shim and a glob
	// change. Worth doing, because loadView is where the alpha.12 crash lived and
	// nothing covers it; not worth doing as a side quest.
	//
	// A test that crashes the runner is worse than no test: xctest reports
	// "Restarting after unexpected exit" and then counts the *remaining* tests as
	// the total, so the suite goes green while silently running fewer.

	/// `sharedInstance` is a `static let`, so a second read must hand back the
	/// same object rather than building a second window.
	@MainActor
	func testSharedInstanceIsShared() {
		XCTAssertTrue(Preferences.sharedInstance === Preferences.sharedInstance)
	}
}
