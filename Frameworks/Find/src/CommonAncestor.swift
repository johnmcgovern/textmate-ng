import Foundation

// Ported from CommonAncestor.mm — the directory a folder search's results are
// displayed relative to. Find.swift hands it to -resultNodeWithMatch:
// baseDirectory: and FFRelativePath, and FFDocumentSearch.swift to the glob
// options.
//
// The scan is deliberately the original's: character-wise over the raw strings
// with a running index of the last "/" seen, over UTF-16 units so that
// -characterAtIndex: and NSString.character(at:) agree exactly. The obvious
// Swift rewrite — pathComponents and a common-prefix reduce — is a different
// function, and t_common_ancestor.mm is what tells the two apart, including the
// one case the original gets wrong and the pin records rather than endorses (a
// path that prefixes another yields the grandparent).
//
// No header. Swift cannot export a free function (rule 19), and both callers are
// in this module, so the Swift spelling stays a free function and the four call
// sites are untouched. The test bundle reaches it through +[Find
// commonAncestorOfPaths:], declared in FindTesting.h beside the other class
// methods the tests pin.

func CommonAncestor(_ paths: [String]) -> String? {
	guard let path = longestCommonDirectory(paths) else {
		return nil
	}

	// So that searching a single file shows results relative to its folder
	// rather than to the file. A stat, so it only fires for paths that exist.
	var isDirectory: ObjCBool = false
	if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue {
		return (path as NSString).deletingLastPathComponent
	}
	return path
}

private func longestCommonDirectory(_ paths: [String]) -> String? {
	if paths.count < 2 {
		return paths.first
	}

	let strings = paths.map { $0 as NSString }
	let first = strings[0]

	var maxLength = Int.max
	for path in strings {
		maxLength = min(path.length, maxLength)
	}

	var pathSeparatorIndex = 0
	for i in 0..<maxLength {
		let ch = first.character(at: i)
		for j in 1..<strings.count {
			if ch != strings[j].character(at: i) {
				return pathSeparatorIndex != 0 ? first.substring(to: pathSeparatorIndex) : "/"
			}
		}

		if ch == unichar(UInt8(ascii: "/")) {
			pathSeparatorIndex = i
		}
	}

	return pathSeparatorIndex != 0 ? first.substring(to: pathSeparatorIndex) : "/"
}

extension Find {
	// The ObjC face, for t_common_ancestor.mm only. nonisolated because the
	// function is pure and the class is @MainActor; the tests run on the main
	// thread either way.
	@objc(commonAncestorOfPaths:)
	nonisolated static func commonAncestor(ofPaths paths: [String]) -> String? {
		return CommonAncestor(paths)
	}
}
