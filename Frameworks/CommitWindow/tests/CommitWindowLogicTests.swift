// First Swift test file in the tree (Phase 4 pilot). Compiled directly into the
// CommitWindowTests bundle alongside src/CommitWindowLogic.swift — both are
// listed in the framework's `tests` glob; see Pass 4 in ide/seed_xcodeproj.rb.
import XCTest

final class CommitWindowLogicTests: XCTestCase {

	// ====================
	// = Argument parsing =
	// ====================

	func testParseTypicalGitCommit() {
		let parsed = CWCommitLogic.parse(arguments: [
			"CommitWindowTool",
			"--status", "M:A:?",
			"--log", "initial message",
			"--diff-cmd", "git,diff",
			"file1.txt", "file2.txt", "file3.txt",
		])
		XCTAssertEqual(parsed.options["--status"], "M:A:?")
		XCTAssertEqual(parsed.options["--log"], "initial message")
		XCTAssertEqual(parsed.options["--diff-cmd"], "git,diff")
		XCTAssertEqual(parsed.parameters, ["file1.txt", "file2.txt", "file3.txt"])
		XCTAssertFalse(parsed.shouldCancel)
		XCTAssertFalse(parsed.showContinueButton)
		XCTAssertEqual(parsed.commitButtonPrefix, "Commit")
	}

	func testParseFlagsAndButtonTitle() {
		let parsed = CWCommitLogic.parse(arguments: [
			"tool", "--show-continue-button", "--commit-button-title", "Check In", "--status", "M", "f",
		])
		XCTAssertTrue(parsed.showContinueButton)
		XCTAssertEqual(parsed.commitButtonPrefix, "Check In")
	}

	func testParseActionCommands() {
		let parsed = CWCommitLogic.parse(arguments: [
			"tool", "--status", "M", "f",
			"--action-cmd", "M,A:Revert,/usr/bin/svn,revert",
			"--action-cmd", "?:Add,/usr/bin/svn,add",
		])
		XCTAssertEqual(parsed.actions.count, 2)
		XCTAssertEqual(parsed.actions[0].name, "Revert")
		XCTAssertEqual(parsed.actions[0].command, ["/usr/bin/svn", "revert"])
		XCTAssertEqual(parsed.actions[0].targetStatuses, ["M", "A"])
		XCTAssertEqual(parsed.actions[1].targetStatuses, ["?"])
	}

	func testParseTooFewArgumentsRequestsCancel() {
		XCTAssertTrue(CWCommitLogic.parse(arguments: ["tool"]).shouldCancel)
		XCTAssertTrue(CWCommitLogic.parse(arguments: ["tool", "only-one"]).shouldCancel)
	}

	func testParseMissingOptionValueRequestsCancel() {
		let parsed = CWCommitLogic.parse(arguments: ["tool", "file", "--log"])
		XCTAssertTrue(parsed.shouldCancel)
	}

	// =====================
	// = Commit output line =
	// =====================

	func testCommitOutputEscapesSingleQuotes() {
		// the leading element ends in a space and join adds another — two spaces
		// before the first path, exactly as the ObjC++ original emitted
		let out = CWCommitLogic.commitOutput(message: "fix bob's bug", escapedPaths: ["a.txt", "dir/b\\ c.txt"])
		XCTAssertEqual(out, " -m 'fix bob'\"'\"'s bug'  a.txt dir/b\\ c.txt \n")
	}

	// ================
	// = Button title =
	// ================

	func testCommitButtonTitle() {
		XCTAssertEqual(CWCommitLogic.commitButtonTitle(prefix: "Commit", count: 1, showsContinue: false), "Commit 1 Item")
		XCTAssertEqual(CWCommitLogic.commitButtonTitle(prefix: "Commit", count: 3, showsContinue: false), "Commit 3 Items")
		XCTAssertEqual(CWCommitLogic.commitButtonTitle(prefix: "Check In", count: 0, showsContinue: true), "Check In 0 Items & Continue")
	}

	// ===================
	// = Message history =
	// ===================

	func testMessageHistoryIgnoresBlankMessages() {
		XCTAssertNil(CWCommitLogic.updatedMessageHistory(["old"], adding: "  \n\t "))
	}

	func testMessageHistoryStartsFresh() {
		XCTAssertEqual(CWCommitLogic.updatedMessageHistory(nil, adding: "first"), ["first"])
	}

	func testMessageHistoryDeduplicatesAndCaps() {
		var history: [String]? = []
		for message in ["a", "b", "c", "d", "e", "b", "f"] {
			history = CWCommitLogic.updatedMessageHistory(history, adding: message) ?? history
		}
		// "b" moved to the end when re-committed; "a" fell off the 5-item cap
		XCTAssertEqual(history, ["c", "d", "e", "b", "f"])
	}

	func testMenuTitleTruncation() {
		XCTAssertEqual(CWCommitLogic.menuTitle(forMessage: "short"), "short")
		let long = String(repeating: "x", count: 40)
		let title = CWCommitLogic.menuTitle(forMessage: long)
		XCTAssertEqual(title, String(repeating: "x", count: 30) + "…")
	}

	// ==================
	// = Tool resolution =
	// ==================

	func testAbsolutePathForToolWalksPATH() {
		let env = ["PATH": "/nowhere:/somewhere/bin"]
		let resolved = CWCommitLogic.absolutePath(forTool: "svn", environment: env, isExecutable: { $0 == "/somewhere/bin/svn" })
		XCTAssertEqual(resolved, "/somewhere/bin/svn")
	}

	func testAbsolutePathForToolKeepsAbsoluteExecutables() {
		let resolved = CWCommitLogic.absolutePath(forTool: "/usr/bin/git", environment: ["PATH": "/x"], isExecutable: { $0 == "/usr/bin/git" })
		XCTAssertEqual(resolved, "/usr/bin/git")
	}

	func testAbsolutePathForToolFallsBackToBareName() {
		let resolved = CWCommitLogic.absolutePath(forTool: "missing", environment: [:], isExecutable: { _ in false })
		XCTAssertEqual(resolved, "missing")
	}
}
