// Pure logic extracted from the window controller so it is testable headlessly.
//
// IMPORTANT: keep this file free of classes and @objc — it is compiled into
// both libCommitWindow.a and the CommitWindowTests bundle (the tests glob in
// default.rave lists it). The test bundle also links the archive, and the -ObjC
// linker flag force-loads any archive member containing ObjC metadata; as long
// as this file emits none, the archive's copy is never pulled and the two
// copies cannot collide.
import Foundation

enum CWCommitLogic {
	struct ActionSpec: Equatable {
		let name: String
		let command: [String]
		let targetStatuses: Set<String>

		// "M,A:Revert,/usr/bin/svn,revert" → statuses {M,A}, name "Revert",
		// command [/usr/bin/svn, revert]
		init?(string: String) {
			guard let colon = string.firstIndex(of: ":") else { return nil }
			let statuses = String(string[string.startIndex ..< colon])
			let commandComponents = String(string[string.index(after: colon)...]).components(separatedBy: ",")
			guard !commandComponents.isEmpty else { return nil }
			self.name = commandComponents[0]
			self.command = Array(commandComponents.dropFirst())
			self.targetStatuses = Set(statuses.components(separatedBy: ","))
		}
	}

	struct Options {
		var options: [String: String] = [:]   // --log, --diff-cmd, --status
		var actions: [ActionSpec] = []        // --action-cmd, may repeat
		var parameters: [String] = []         // positional: the file paths
		var commitButtonPrefix = "Commit"
		var showContinueButton = false
		// The original sent a failure reply mid-parse (via cancel:) on malformed
		// input but carried on parsing; the flag preserves that contract.
		var shouldCancel = false
	}

	// Port of -[OakCommitWindow parseArguments:]. `arguments` is the full argv
	// including the tool name at index 0.
	static func parse(arguments: [String]) -> Options {
		var result = Options()
		let optionKeys = ["--log", "--diff-cmd", "--action-cmd", "--status"]
		let args = Array(arguments.dropFirst())

		if args.count < 2 {
			result.shouldCancel = true
		}

		var iterator = args.makeIterator()
		while let arg = iterator.next() {
			if arg == "--show-continue-button" {
				result.showContinueButton = true
			} else if arg == "--commit-button-title" {
				result.commitButtonPrefix = iterator.next() ?? result.commitButtonPrefix
			} else if optionKeys.contains(arg) {
				if let value = iterator.next() {
					if arg == "--action-cmd" {
						if let action = ActionSpec(string: value) {
							result.actions.append(action)
						}
					} else {
						result.options[arg] = value
					}
				} else {
					result.shouldCancel = true
				}
			} else {
				result.parameters.append(arg)
			}
		}
		return result
	}

	static func commitButtonTitle(prefix: String, count: Int, showsContinue: Bool) -> String {
		"\(prefix) \(count) Item\(count == 1 ? "" : "s")\(showsContinue ? " & Continue" : "")"
	}

	// The ` -m '…' path…` line the tool prints to stdout for the bundle script.
	// Single quotes in the message use the '"'"' shell idiom; paths must already
	// be shell-escaped by the caller.
	static func commitOutput(message: String, escapedPaths: [String]) -> String {
		let quoted = message.replacingOccurrences(of: "'", with: "'\"'\"'")
		return ([" -m '\(quoted)' "] + escapedPaths + ["\n"]).joined(separator: " ")
	}

	static let messageHistoryLimit = 5
	static let messageTitleLength = 30

	// nil ⇒ nothing to save (blank message) — history is unchanged.
	static func updatedMessageHistory(_ messages: [String]?, adding message: String) -> [String]? {
		guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
		guard var messages else { return [message] }
		if let index = messages.firstIndex(of: message) {
			messages.remove(at: index)
		}
		messages.append(message)
		if messages.count > messageHistoryLimit {
			messages.removeFirst()
		}
		return messages
	}

	static func menuTitle(forMessage message: String) -> String {
		message.count > messageTitleLength
			? String(message.prefix(messageTitleLength)) + "…"
			: message
	}

	// Port of absolute_path_for_tool: resolve a bare tool name against PATH.
	// `isExecutable` is injected so tests need no filesystem.
	static func absolutePath(forTool tool: String, environment: [String: String], isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String {
		guard !isExecutable(tool), let pathList = environment["PATH"] else { return tool }
		for dir in pathList.components(separatedBy: ":") {
			let candidate = (dir as NSString).appendingPathComponent(tool)
			if isExecutable(candidate) {
				return candidate
			}
		}
		return tool
	}
}
