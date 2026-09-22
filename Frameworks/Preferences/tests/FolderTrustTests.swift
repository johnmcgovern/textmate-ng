import XCTest

// Which folders may set environment variables through their own
// `.tm_properties`. The rule this store answers for lives in Frameworks/settings
// and is tested there; this is the bookkeeping underneath it.
//
// **These write real preferences**, because that is the whole of what the type
// does — it has no stored properties, every accessor goes to UserDefaults, and a
// test that substituted a fake store would be testing the fake. Each one records
// what was there and puts it back, so a developer's own trusted folders survive
// a test run.
final class FolderTrustTests: XCTestCase {
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

	// The default, and the one that matters most: an answer nobody has given is
	// not a yes.
	func testNothingIsTrustedUntilItIsSaid() {
		XCTAssertFalse(TMFolderTrust.shared.isTrusted("/tmp/some/checkout/.tm_properties"))
		XCTAssertFalse(TMFolderTrust.shared.hasBeenAskedAbout("/tmp/some/checkout"))
	}

	func testTrustingAFolderTrustsWhatIsInsideIt() {
		TMFolderTrust.shared.trust("/tmp/checkout")
		XCTAssertTrue(TMFolderTrust.shared.isTrusted("/tmp/checkout"))
		XCTAssertTrue(TMFolderTrust.shared.isTrusted("/tmp/checkout/.tm_properties"))
		XCTAssertTrue(TMFolderTrust.shared.isTrusted("/tmp/checkout/deep/inside/.tm_properties"))
	}

	// A string prefix would make `/tmp/checkoutXYZ` trusted by `/tmp/checkout`,
	// which is a real way to get this wrong and is why the comparison is by
	// component boundary.
	func testASiblingWithALongerNameIsNotTrusted() {
		TMFolderTrust.shared.trust("/tmp/checkout")
		XCTAssertFalse(TMFolderTrust.shared.isTrusted("/tmp/checkoutXYZ/.tm_properties"))
		XCTAssertFalse(TMFolderTrust.shared.isTrusted("/tmp/checkout-other/.tm_properties"))
	}

	func testRefusingIsAlsoAnAnswer() {
		TMFolderTrust.shared.refuse("/tmp/checkout")
		XCTAssertFalse(TMFolderTrust.shared.isTrusted("/tmp/checkout/.tm_properties"))
		// The point of recording it: the folder does not ask again every time it
		// is opened.
		XCTAssertTrue(TMFolderTrust.shared.hasBeenAskedAbout("/tmp/checkout"))
	}

	func testAnAnswerCanBeChanged() {
		TMFolderTrust.shared.refuse("/tmp/checkout")
		TMFolderTrust.shared.trust("/tmp/checkout")
		XCTAssertTrue(TMFolderTrust.shared.isTrusted("/tmp/checkout/.tm_properties"))

		TMFolderTrust.shared.refuse("/tmp/checkout")
		XCTAssertFalse(TMFolderTrust.shared.isTrusted("/tmp/checkout/.tm_properties"))
	}

	// Forgetting is not refusing. The folder is asked about again, which is what
	// someone wants after trusting one by mistake.
	func testForgettingMakesTheQuestionAskableAgain() {
		TMFolderTrust.shared.trust("/tmp/checkout")
		TMFolderTrust.shared.forget("/tmp/checkout")
		XCTAssertFalse(TMFolderTrust.shared.isTrusted("/tmp/checkout/.tm_properties"))
		XCTAssertFalse(TMFolderTrust.shared.hasBeenAskedAbout("/tmp/checkout"))
	}

	// Paths are standardised, so the same folder written two ways is one answer
	// rather than two.
	func testAPathIsTheSameFolderHoweverItIsSpelled() {
		TMFolderTrust.shared.trust("/tmp/checkout/")
		XCTAssertTrue(TMFolderTrust.shared.isTrusted("/tmp/checkout/.tm_properties"))
		XCTAssertTrue(TMFolderTrust.shared.isTrusted("/tmp/other/../checkout/.tm_properties"))
	}

	func testTrustedFoldersAreListedForSettings() {
		TMFolderTrust.shared.trust("/tmp/b")
		TMFolderTrust.shared.trust("/tmp/a")
		XCTAssertEqual(TMFolderTrust.shared.trustedFolders, ["/tmp/a", "/tmp/b"])
	}
}
