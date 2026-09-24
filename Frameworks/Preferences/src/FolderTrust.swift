import Foundation
import os.log

private let log = Logger(subsystem: "com.j23software.TextMate-NG", category: "folder-trust")

// Which folders may set environment variables through their own `.tm_properties`.
//
// **Why this exists.** A `.tm_properties` travels with a checkout, so its
// contents are whatever the code's author put there — and until 2026-09-22 one
// of them could set `PATH`, which meant cloning a repository and opening a
// single file was enough to run code it shipped. Proved end to end, not
// reasoned about. `TM_GIT`, `TM_RUBY` and nine more are the same hole through
// one bundle each, and they cannot be enumerated, because which variables a
// bundle treats as a program is decided by the bundle.
//
// So the question is not "which variables are dangerous" but "is this folder
// one the user vouched for". Settings — the lowercase ones like `fontName` —
// are never in question and always apply; see Frameworks/settings for the rule.
//
// **Trust is a prefix.** Vouching for a checkout vouches for what is inside it,
// because that is what a person means when they say they trust a project, and
// asking again for every subdirectory that happens to carry its own file would
// train them to say yes without reading.
// @unchecked Sendable, and the contract is that there is nothing to protect:
// this type has **no stored properties at all**. Every accessor below reads and
// writes UserDefaults, which is thread-safe, so two callers on different queues
// race only in the way two writes to a preference always have. The "unchecked"
// is because NSObject is not Sendable, not because anything here is unsafe
// (rule 26).
@objc(TMFolderTrust)
final class FolderTrust: NSObject, @unchecked Sendable {
	@objc static let shared = FolderTrust()

	private static let defaultsKey = "TrustedProjectFolders"

	// Paths, not bookmarks. A bookmark follows a folder when it moves, which
	// sounds better and is worse here: the thing being trusted is a location the
	// user recognised, and a checkout that moved is one they should be asked
	// about again.
	private var trusted: Set<String> {
		get { Set(UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []) }
		set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: Self.defaultsKey) }
	}

	// Is `path` inside a folder the user has vouched for?
	//
	// Compared as path components rather than as a string prefix: `/a/b` must not
	// make `/a/bcd` trusted, which a `hasPrefix` would.
	@objc func isTrusted(_ path: String) -> Bool {
		let candidate = (path as NSString).standardizingPath
		for root in trusted {
			let rootPath = (root as NSString).standardizingPath
			if candidate == rootPath || candidate.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") {
				return true
			}
		}
		return false
	}

	// Has the user already answered for this folder, either way? Distinct from
	// `isTrusted`, which a subfolder of a trusted root also answers yes to — this
	// is what decides whether to ask.
	// Named so the Swift spelling and the @objc selector are the same string.
	// `hasBeenAsked(about:)` generates the selector `hasBeenAskedAbout:`, which
	// reads fine from ObjC and is a different name in Swift — and this type is
	// reached both ways, from AppControllerSupport.mm through the hand-written
	// header and from this framework's own Swift tests. Two names for one method
	// across a boundary is how a call compiles and then does not dispatch.
	@objc func hasBeenAskedAbout(_ folder: String) -> Bool {
		return isTrusted(folder) || refused.contains((folder as NSString).standardizingPath)
	}

	private static let refusedKey = "RefusedProjectFolders"

	// Remembered as well as the yes list, so that declining is also an answer and
	// the same folder does not ask again every time it is opened.
	private var refused: Set<String> {
		get { Set(UserDefaults.standard.stringArray(forKey: Self.refusedKey) ?? []) }
		set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: Self.refusedKey) }
	}

	@objc func trust(_ folder: String) {
		let path = (folder as NSString).standardizingPath
		var t = trusted; t.insert(path); trusted = t
		var r = refused; r.remove(path); refused = r
		log.log("Trusting project folder \(path, privacy: .public)")
	}

	@objc func refuse(_ folder: String) {
		let path = (folder as NSString).standardizingPath
		var r = refused; r.insert(path); refused = r
		var t = trusted; t.remove(path); trusted = t
		log.log("Not trusting project folder \(path, privacy: .public)")
	}

	// For Settings, and for undoing a mistake. Forgetting is not the same as
	// refusing: the folder is asked about again next time.
	@objc func forget(_ folder: String) {
		let path = (folder as NSString).standardizingPath
		var t = trusted; t.remove(path); trusted = t
		var r = refused; r.remove(path); refused = r
	}

	@objc var trustedFolders: [String] { Array(trusted).sorted() }

	// The nearest folder, from `folder` upward, whose own `.tm_properties` would
	// set environment variables and that nobody has answered for — or nil.
	//
	// **Upward, because the settings layer reads upward.** A file's settings come
	// from every `.tm_properties` between its directory and home, so a project
	// opened one level inside a checkout is still configured by the checkout's
	// file. Until 2026-09-23 only the project folder itself was looked at, on the
	// theory that a parent's file was either the user's own or one they had
	// already been asked about. The alpha.34 smoke pass showed that was wrong:
	// opening a single file from `src/` made `src` the project, the checkout's
	// variables were withheld — the safe direction — and the user was never asked.
	//
	// Stops where the settings walk stops: at home, whose own `.tm_properties` is
	// the user's and exempt; and for anything outside home, at `/`. That includes
	// shared places like /tmp, where a file left by another account would
	// otherwise configure this one's commands.
	// The selector is spelled out because Swift would otherwise generate
	// `folderToAskAboutWithStartingAt:` — "startingAt" is not a preposition, so it
	// inserts "With" — while Preferences.h declares `folderToAskAboutStartingAt:`.
	// Found by the tests below crashing on doesNotRecognizeSelector (rule 23).
	@objc(folderToAskAboutStartingAt:) func folderToAskAbout(startingAt folder: String) -> String? {
		let home = (NSHomeDirectory() as NSString).standardizingPath
		var current = (folder as NSString).standardizingPath
		while current != home {
			if !hasBeenAskedAbout(current) && wouldSetEnvironment(inFolder: current) {
				return current
			}
			let parent = (current as NSString).deletingLastPathComponent
			if parent.isEmpty || parent == current {
				break
			}
			current = parent
		}
		return nil
	}

	// Does this folder's own `.tm_properties` try to set environment variables —
	// the uppercase ones a bundle command can treat as the program it runs?
	// `folderToAskAbout(startingAt:)` is what walks upward; this looks at one file.
	//
	// Deliberately approximate, and in the safe direction. It looks for an
	// assignment whose name starts with an uppercase letter and does not attempt
	// to parse sections, continuations or quoting — the settings layer does that
	// properly and refuses whatever it finds. Being wrong here means asking when
	// nothing would have been set, which costs a prompt. The opposite error would
	// cost the whole point.
	@objc func wouldSetEnvironment(inFolder folder: String) -> Bool {
		let file = (folder as NSString).appendingPathComponent(".tm_properties")
		guard let contents = try? String(contentsOfFile: file, encoding: .utf8) else {
			return false
		}
		for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("[") {
				continue
			}
			guard let equals = trimmed.firstIndex(of: "=") else { continue }
			let name = trimmed[trimmed.startIndex..<equals].trimmingCharacters(in: .whitespaces)
			if let first = name.first, first.isUppercase {
				return true
			}
		}
		return false
	}
}
