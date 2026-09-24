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

	// Settings lists both answers, so each list has to hold exactly its own.
	func testRefusedFoldersAreListedForSettingsSeparately() {
		TMFolderTrust.shared.trust("/tmp/yes")
		TMFolderTrust.shared.refuse("/tmp/no")
		XCTAssertEqual(TMFolderTrust.shared.trustedFolders, ["/tmp/yes"])
		XCTAssertEqual(TMFolderTrust.shared.refusedFolders, ["/tmp/no"])
		TMFolderTrust.shared.trust("/tmp/no")
		XCTAssertEqual(TMFolderTrust.shared.refusedFolders, [])
	}

	// What decides whether to ask at all. Approximate by design and in the safe
	// direction: a false yes costs a prompt, a false no costs the point of having
	// one.
	private func folder(containing properties: String) -> String {
		let dir = NSTemporaryDirectory() + "trust-\(UUID().uuidString)"
		try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
		try? properties.write(toFile: (dir as NSString).appendingPathComponent(".tm_properties"), atomically: true, encoding: .utf8)
		return dir
	}

	func testAFolderWithNoPropertiesFileIsNotAskedAbout() {
		let dir = NSTemporaryDirectory() + "trust-empty-\(UUID().uuidString)"
		try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
		XCTAssertFalse(TMFolderTrust.shared.wouldSetEnvironment(inFolder: dir))
	}

	// Settings only. Nothing here can select a program, so there is nothing to
	// ask about and the user is not interrupted.
	func testSettingsOnlyDoesNotNeedAsking() {
		let dir = folder(containing: "fontName = \"Menlo\"\nsoftTabs = true\ntabSize = 3\n")
		XCTAssertFalse(TMFolderTrust.shared.wouldSetEnvironment(inFolder: dir))
	}

	func testAnEnvironmentVariableNeedsAsking() {
		XCTAssertTrue(TMFolderTrust.shared.wouldSetEnvironment(inFolder: folder(containing: "TM_GIT = \"/x/git\"\n")))
		XCTAssertTrue(TMFolderTrust.shared.wouldSetEnvironment(inFolder: folder(containing: "softTabs = true\nPATH = \"/x:$PATH\"\n")))
	}

	// The walk upward. `tree` builds a checkout with an inner folder, each with or
	// without its own file, so the tests say which folder *should* be asked about.
	private func tree(outer: String?, inner: String?) -> (outer: String, inner: String) {
		let outerDir = NSTemporaryDirectory() + "trust-walk-\(UUID().uuidString)"
		let innerDir = (outerDir as NSString).appendingPathComponent("src")
		try? FileManager.default.createDirectory(atPath: innerDir, withIntermediateDirectories: true)
		if let outer { try? outer.write(toFile: (outerDir as NSString).appendingPathComponent(".tm_properties"), atomically: true, encoding: .utf8) }
		if let inner { try? inner.write(toFile: (innerDir as NSString).appendingPathComponent(".tm_properties"), atomically: true, encoding: .utf8) }
		return ((outerDir as NSString).standardizingPath, (innerDir as NSString).standardizingPath)
	}

	// The case the smoke pass found: a project opened one level inside the
	// checkout that carries the file. The checkout is what needs an answer.
	func testAProjectInsideACheckoutAsksAboutTheCheckout() {
		let t = tree(outer: "TM_GIT = \"/x/git\"\n", inner: nil)
		XCTAssertEqual(TMFolderTrust.shared.folderToAskAbout(startingAt: t.inner), t.outer)
	}

	func testTheNearestUnansweredFolderIsAskedFirst() {
		let t = tree(outer: "TM_GIT = \"/x/git\"\n", inner: "TM_RUBY = \"/x/ruby\"\n")
		XCTAssertEqual(TMFolderTrust.shared.folderToAskAbout(startingAt: t.inner), t.inner)
		// Once that is answered, the next one up is the question.
		TMFolderTrust.shared.refuse(t.inner)
		XCTAssertEqual(TMFolderTrust.shared.folderToAskAbout(startingAt: t.inner), t.outer)
	}

	// Trust is a prefix, so vouching for the checkout answers for everything in it,
	// including an inner folder with a file of its own.
	func testATrustedCheckoutAnswersForWhatIsInsideIt() {
		let t = tree(outer: "TM_GIT = \"/x/git\"\n", inner: "TM_RUBY = \"/x/ruby\"\n")
		TMFolderTrust.shared.trust(t.outer)
		XCTAssertNil(TMFolderTrust.shared.folderToAskAbout(startingAt: t.inner))
	}

	// The control: with nothing that sets a variable anywhere on the way up there
	// is nothing to ask, so the tests above are about the walk and not a default.
	func testNothingToAskWhenNoFileSetsAVariable() {
		let t = tree(outer: "tabSize = 3\n", inner: nil)
		XCTAssertNil(TMFolderTrust.shared.folderToAskAbout(startingAt: t.inner))
	}

	// Comments and section headers are not assignments. Treating `[ *.cc ]` as one
	// would ask about every project file that uses a section, which is most of
	// them, and a prompt nobody can act on teaches people to dismiss it.
	func testCommentsAndSectionsAreNotAssignments() {
		let dir = folder(containing: "# TM_GIT = \"/x/git\"\n[ *.cc ]\ntabSize = 3\n")
		XCTAssertFalse(TMFolderTrust.shared.wouldSetEnvironment(inFolder: dir))
	}
}
