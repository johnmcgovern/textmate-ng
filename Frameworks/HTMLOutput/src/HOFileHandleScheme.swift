import AppKit
import WebKit
import os

// Ported from HOFileHandleScheme.mm — the WKURLSchemeHandler that streams a
// bundle command's output into the page, serves the sub-resources that stream
// references, and answers the synchronous half of TextMate.system().
//
// The rewriter this file depends on was extracted and pinned first (768e4bfc);
// the constants and one C++ call live in HOFileHandleSchemeSupport (rule 19 and
// rule 17 respectively). What is left is AppKit, Dispatch and read(2).
//
// ==========================================================================
// = The isolation contract, which is the whole difficulty of this file     =
// ==========================================================================
//
// WKURLSchemeTask raises an ObjC exception — not an error return — if any of its
// callbacks run after -stopURLSchemeTask:, or after didFinish. So there is a rule,
// and it is the same rule the ObjC++ followed:
//
//   * `stopped`, `task` and `completionHandler` are touched **only on the main
//     queue**;
//   * the read loop runs on a global queue and reaches them **only** inside
//     `DispatchQueue.main.sync`, re-checking `stopped` there before every
//     delivery;
//   * that same `main.sync` is the barrier that publishes `keepRunning` back to
//     the loop.
//
// HOFileHandleTask is therefore `@unchecked Sendable`: the guarantee is real but
// it is upheld by this contract rather than by the type system, and saying so
// with the annotation is more honest than hiding the hop behind an actor whose
// re-entrancy would change when the checks happen relative to the deliveries.
//
// The classes' ObjC face is the hand declaration in HOFileHandleScheme.h
// (rule 23).

private let log = Logger(subsystem: "com.j23software.TextMate-NG", category: "html-output")

// Same scheme *and* same host as the job URL (x-txmt-filehandle://job/…), so the
// rewritten sub-resources are same-origin with the page rather than merely
// same-scheme.
private func MimeTypeForPath(_ path: String) -> String {
	let types: [String: String] = [
		"css": "text/css",    "js":    "text/javascript", "json": "application/json",
		"png": "image/png",   "jpg":   "image/jpeg",      "jpeg": "image/jpeg",
		"gif": "image/gif",   "svg":   "image/svg+xml",   "webp": "image/webp",
		"html": "text/html",  "htm":   "text/html",       "txt":  "text/plain",
		"woff": "font/woff",  "woff2": "font/woff2",      "ttf":  "font/ttf",
	]
	return types[(path as NSString).pathExtension.lowercased()] ?? "application/octet-stream"
}

// ==================
// = The job record =
// ==================

@objc(HOFileHandleJob)
@MainActor
class HOFileHandleJob: NSObject {
	@objc private(set) var fileHandle: FileHandle
	@objc private(set) var processIdentifier: pid_t

	init(fileHandle: FileHandle, processIdentifier: pid_t) {
		self.fileHandle        = fileHandle
		self.processIdentifier = processIdentifier
	}
}

@objc(HOFileHandleRegistry)
@MainActor
class HOFileHandleRegistry: NSObject {
	private var jobs: [URL: HOFileHandleJob] = [:]

	@objc static let sharedInstance = HOFileHandleRegistry()

	@objc(registerJobForURL:fileHandle:processIdentifier:)
	func registerJob(forURL aURL: URL?, fileHandle aFileHandle: FileHandle?, processIdentifier: pid_t) {
		guard let aURL, let aFileHandle else {
			return
		}
		jobs[aURL] = HOFileHandleJob(fileHandle: aFileHandle, processIdentifier: processIdentifier)
	}

	// One-shot: also removes the entry.
	@objc(claimJobForURL:)
	func claimJob(forURL aURL: URL?) -> HOFileHandleJob? {
		guard let aURL, let job = jobs[aURL] else {
			return nil
		}
		jobs.removeValue(forKey: aURL)
		return job
	}

	@objc(discardJobForURL:)
	func discardJob(forURL aURL: URL?) {
		guard let aURL else {
			return
		}
		jobs.removeValue(forKey: aURL)
	}
}

// ==========================
// = One in-flight URL task =
// ==========================

private final class HOFileHandleTask: @unchecked Sendable {
	// Main queue only — see the contract at the top of this file.
	private let task: any WKURLSchemeTask
	private var completionHandler: (() -> Void)?
	private var stopped = false

	// Taken off the job at construction rather than held as a reference to it.
	// HOFileHandleJob is @MainActor, and the read loop closes the handle from the
	// *background* queue — as the ObjC++ did, where nothing was isolated. Reaching
	// through the job there would need main-actor isolation the loop does not have.
	private let fileHandle: FileHandle
	private let processGroup: pid_t

	@MainActor
	init(task: any WKURLSchemeTask, job: HOFileHandleJob, completionHandler: @escaping () -> Void) {
		self.task              = task
		self.fileHandle        = job.fileHandle
		self.processGroup      = job.processIdentifier
		self.completionHandler = completionHandler
	}

	@MainActor
	func start() {
		guard let url = task.request.url else {
			// A scheme task always carries a URL; there is nothing to respond to
			// without one, so end it rather than inventing a response.
			finish()
			return
		}

		task.didReceive(URLResponse(url: url, mimeType: "text/html", expectedContentLength: -1, textEncodingName: "utf-8"))

		let fd = fileHandle.fileDescriptor
		DispatchQueue.global(qos: .default).async { [self] in
			var buf = [UInt8](repeating: 0, count: 8192)
			let rewriter = HOLocalURLRewriter()
			var keepRunning = true
			var len = 0

			while keepRunning {
				len = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, 8192) }
				if len <= 0 {
					break
				}

				let data = rewriter.rewriteChunk(Data(buf[0..<len]))
				if data.isEmpty { // whole chunk held back as a partial match
					continue
				}

				DispatchQueue.main.sync {
					keepRunning = !self.stopped
					if keepRunning {
						self.task.didReceive(data)
					}
				}
			}

			if len == -1 {
				perror("HTMLOutput: read")
			}

			// A partial `file://` at EOF was never a real one — emit it verbatim.
			let tail = rewriter.carry
			if keepRunning && !tail.isEmpty {
				DispatchQueue.main.sync {
					if !self.stopped {
						self.task.didReceive(tail)
					}
				}
			}

			self.fileHandle.closeFile()

			DispatchQueue.main.sync {
				MainActor.assumeIsolated {
					self.finish()
				}
			}
		}
	}

	@MainActor
	func finish() {
		if !stopped {
			stopped = true // no further callbacks are legal after didFinish either
			task.didFinish()
		}

		let handler = completionHandler
		completionHandler = nil
		handler?()
	}

	@MainActor
	func stop() {
		stopped           = true
		completionHandler = nil

		if processGroup != 0 {
			HOFileHandleSchemeSupport.killProcessGroup(inBackground: processGroup)
		}
	}
}

// ==================
// = Scheme handler =
// ==================

@objc(HOFileHandleSchemeHandler)
@MainActor
class HOFileHandleSchemeHandler: NSObject, @preconcurrency WKURLSchemeHandler {
	private var tasks: [ObjectIdentifier: HOFileHandleTask] = [:]
	// In-flight synchronous TextMate.system() calls.
	private var pendingSyncTasks: Set<ObjectIdentifier> = []

	// Set while the JavaScript API is installed; nil when the command opted out via
	// disableJavaScriptAPI, which also disables the synchronous bridge.
	@objc weak var syncRunner: HOSyncCommandRunner?

	func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
		guard let url = urlSchemeTask.request.url else {
			urlSchemeTask.didFinish()
			return
		}

		// tm-file sub-resources: the navigation policy rewrites tm-file to file:// for
		// page loads, but it never sees an <img>/<link>/<script>, so those arrive here.
		if url.scheme == kHOTMFileURLScheme {
			return serveFile(atPath: url.path, forTask: urlSchemeTask)
		}

		if url.path.hasPrefix(kHOSyncCommandPathPrefix) {
			return serveSyncCommand(forTask: urlSchemeTask)
		}

		if url.path.hasPrefix(kHOLocalFilePathPrefix) {
			// -path is already percent-decoded
			return serveFile(atPath: String(url.path.dropFirst(kHOLocalFilePathPrefix.count)), forTask: urlSchemeTask)
		}

		guard let job = HOFileHandleRegistry.sharedInstance.claimJob(forURL: url) else {
			// The job URL is unique per run and claimed once, so this is a reload of a
			// command whose output stream is already gone. The NSURLProtocol version
			// answered the same way.
			log.error("No command output for ‘\(url.absoluteString, privacy: .public)’")
			if let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil) {
				urlSchemeTask.didReceive(response)
			}
			urlSchemeTask.didFinish()
			return
		}

		let key = ObjectIdentifier(urlSchemeTask)
		let task = HOFileHandleTask(task: urlSchemeTask, job: job) { [weak self] in
			self?.tasks.removeValue(forKey: key)
		}

		tasks[key] = task
		task.start()
	}

	func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
		let key = ObjectIdentifier(urlSchemeTask)
		pendingSyncTasks.remove(key)

		let task = tasks.removeValue(forKey: key)
		task?.stop()
	}

	/*
		Answers a synchronous TextMate.system(). The page is blocked in a synchronous
		XMLHttpRequest for the duration — but that only stalls the web content process,
		so the app stays responsive and can still put up the 15-second warning alert.

		The task is finished exactly once, from the runner's completion handler.
	*/
	private func serveSyncCommand(forTask urlSchemeTask: any WKURLSchemeTask) {
		guard let url = urlSchemeTask.request.url else {
			urlSchemeTask.didFinish()
			return
		}

		let encoded = urlSchemeTask.request.allHTTPHeaderFields?[kHOSyncCommandHeader]
		let decoded = encoded.flatMap { Data(base64Encoded: $0, options: []) }
		let command = decoded.flatMap { String(data: $0, encoding: .utf8) }

		guard let command, let runner = syncRunner else {
			// No runner means the command opted out of the JavaScript API, so the page
			// should not have been able to reach here at all.
			log.error("HTMLOutput: synchronous bridge unavailable (command \(command != nil ? "ok" : "missing", privacy: .public), runner \(self.syncRunner != nil ? "ok" : "missing", privacy: .public))")
			if let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: "HTTP/1.1", headerFields: nil) {
				urlSchemeTask.didReceive(response)
			}
			urlSchemeTask.didFinish()
			return
		}

		let key = ObjectIdentifier(urlSchemeTask)
		pendingSyncTasks.insert(key)

		runner.runSyncCommand(command) { [weak self] output, error, status in
			MainActor.assumeIsolated {
				guard let self else {
					return
				}
				// -stopURLSchemeTask: drops the task from the set. If it is gone the page
				// navigated away mid-command, and touching the task now would raise.
				guard self.pendingSyncTasks.contains(key) else {
					return
				}
				self.pendingSyncTasks.remove(key)

				let payload: [String: Any] = [
					"outputString": output ?? "",
					"errorString":  error ?? "",
					"status":       status,
				]
				let json = (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data()

				urlSchemeTask.didReceive(URLResponse(url: url, mimeType: "application/json", expectedContentLength: json.count, textEncodingName: "utf-8"))
				urlSchemeTask.didReceive(json)
				urlSchemeTask.didFinish()
			}
		}
	}

	/*
		Serves a stylesheet/script/image that the page referenced as file:// before the
		stream rewrite. Read synchronously: these are small local assets, and the whole
		point is to answer before the page finishes parsing.

		This does let command output read any file the user can read — which is exactly
		the privilege +[WebView registerURLSchemeAsLocal:] granted the job scheme
		before, so it is not a widening. The content is the user’s own bundle output.
	*/
	private func serveFile(atPath path: String, forTask urlSchemeTask: any WKURLSchemeTask) {
		guard let url = urlSchemeTask.request.url else {
			urlSchemeTask.didFinish()
			return
		}

		let data = path.isEmpty ? nil : try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
		guard let data else {
			log.error("HTMLOutput: no local resource at ‘\(path, privacy: .public)’")
			if let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil) {
				urlSchemeTask.didReceive(response)
			}
			urlSchemeTask.didFinish()
			return
		}

		urlSchemeTask.didReceive(URLResponse(url: url, mimeType: MimeTypeForPath(path), expectedContentLength: data.count, textEncodingName: nil))
		urlSchemeTask.didReceive(data)
		urlSchemeTask.didFinish()
	}
}
