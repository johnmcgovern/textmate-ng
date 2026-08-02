import AppKit
import UserNotifications

// Collects the crash reports macOS wrote for this process and posts them to a
// collector, then tells the user through a notification.
//
// ⚠️ **The posting half is currently unreachable.** Phase 2.5 stopped
// AppController calling -postNewCrashReportsToURLString:, because the URL it was
// given resolved to MacroMates' api.textmate.org and the setting defaulted to
// enabled — see the comment at that call site. Only -applicationDidFinishLaunching:
// runs today. It is ported faithfully rather than deleted because re-enabling it
// against a J23-owned collector is a recorded intention, and its three helpers
// are unit-tested so the transliteration is checked even though the upload path
// cannot be exercised end to end.
//
// CrashReporter.h stays hand-written, so AppController was not touched.

@objc(CrashReporter)
final class CrashReporter: NSObject {
	// Deliberately NOT @MainActor, which would be a stronger contract than the
	// ObjC++ had and a wrong one: the URLSession completion handlers below
	// genuinely run off the main queue and touch this object. Marking the class
	// main-actor also makes it unable to satisfy the two notification-delegate
	// protocols at all — their requirements are nonisolated — which is the same
	// "crosses into main actor-isolated code" wall the OakTabBarView port hit
	// with the accessibility marker protocols.
	@objc nonisolated(unsafe) static let sharedInstance = CrashReporter()

	private static let crashReportsSentKey = "CrashReportsSent"
	private static let reportsDirectory = ("~/Library/Logs/DiagnosticReports" as NSString).expandingTildeInPath

	@objc override init() {
		super.init()
		UNUserNotificationCenter.current().delegate = self
	}

	// The app hands this the launch notification when macOS started TextMate by
	// the user clicking a crash-report notification. @MainActor because
	// NSApplication.launchUserNotificationUserInfoKey is, and because
	// AppController only ever calls this from applicationDidFinishLaunching:.
	@MainActor
	@objc func applicationDidFinishLaunching(_ notification: Notification) {
		guard let launched = notification.userInfo?[NSApplication.launchUserNotificationUserInfoKey] as? NSUserNotification else { return }
		userNotificationCenter(NSUserNotificationCenter.default, didActivate: launched)
	}

	@objc func postNewCrashReports(toURLString urlString: String) {
		guard !UserDefaults.standard.bool(forKey: kUserDefaultsDisableCrashReportingKey) else { return }
		guard let url = URL(string: urlString) else { return }

		let identifier = "\(Bundle.main.bundleIdentifier ?? "").CrashReporting"
		let activity = NSBackgroundActivityScheduler(identifier: identifier)
		activity.interval = 30
		activity.schedule { completionHandler in
			let date = Date(timeIntervalSinceNow: -7*24*60*60)
			self.postCrashReports(notBefore: date, to: url, forProcessName: ProcessInfo.processInfo.processName)
			completionHandler(.finished)
		}
	}

	private func postCrashReports(notBefore date: Date, to postURL: URL, forProcessName processName: String) {
		let canSend = CrashReporter.reports(forProcessName: processName, notBefore: date, in: CrashReporter.reportsDirectory)
		var shouldSend = Set(canSend)

		if let hasSent = UserDefaults.standard.stringArray(forKey: CrashReporter.crashReportsSentKey) {
			// Reports macOS has since deleted are dropped from the sent list, so
			// it cannot grow without bound.
			let trimmed = Set(hasSent).intersection(canSend)
			if trimmed.count < hasSent.count {
				UserDefaults.standard.set(Array(trimmed), forKey: CrashReporter.crashReportsSentKey)
			}
			shouldSend.subtract(trimmed)
		}

		for reportPath in shouldSend {
			guard let gzippedReport = CrashReporter.pathForGZipCompressedFile(atPath: reportPath) else { continue }

			var request = URLRequest(url: postURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60)
			let body = CrashReporter.data(for: &request, withFormValues: [
				"hardware": "\(CrashReporter.hardwareInfo(HW_MODEL))/\(CrashReporter.hardwareInfo(HW_MACHINE))/\(CrashReporter.hardwareInfo(HW_NCPU, isInteger: true))",
				"contact":  UserDefaults.standard.string(forKey: kUserDefaultsCrashReportsContactInfoKey) ?? "Anonymous",
				"report":   "@" + gzippedReport,
			])

			let task = URLSession.shared.uploadTask(with: request, from: body) { _, response, _ in
				let rc = (response as? HTTPURLResponse)?.statusCode ?? 0
				// 4xx is not retried: the report is as unwelcome next time.
				if (200..<300).contains(rc) || (400..<500).contains(rc) {
					self.recordAsSent(reportPath)
					if let location = (response as? HTTPURLResponse)?.allHeaderFields["Location"] as? String {
						CrashReporter.log("Crash report available at \(location)")
						self.notifyReportSent(reportPath: reportPath, locationURLString: location)
					}
				} else {
					CrashReporter.logError("Unexpected status code (\(rc)) from \(postURL)")
				}
				unlink(gzippedReport)
			}
			task.resume()
		}
	}

	private func recordAsSent(_ reportPath: String) {
		// @synchronized in the ObjC++, for the same reason: several uploads run
		// concurrently and each read-modify-writes the same default.
		objc_sync_enter(UserDefaults.standard)
		defer { objc_sync_exit(UserDefaults.standard) }

		var updated = [reportPath]
		if let old = UserDefaults.standard.stringArray(forKey: CrashReporter.crashReportsSentKey) {
			updated.append(contentsOf: old)
		}
		UserDefaults.standard.set(updated, forKey: CrashReporter.crashReportsSentKey)
	}

	private func notifyReportSent(reportPath: String, locationURLString: String) {
		UNUserNotificationCenter.current().requestAuthorization(options: [ .alert ]) { granted, _ in
			guard granted else {
				CrashReporter.log("User notifications disallowed")
				return
			}

			let content = UNMutableNotificationContent()
			content.title = "Crash Report Sent"
			content.body  = "Diagnostic information has been sent regarding your last crash."
			content.userInfo = [ "path": reportPath, "url": locationURLString ]

			let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
			UNUserNotificationCenter.current().add(request) { error in
				if let error {
					CrashReporter.logError("Failed to show notification: \(error.localizedDescription)")
				}
			}
		}
	}

	// MARK: - Helpers
	//
	// The three below are the whole of this class that can be checked without a
	// collector to post to, which is why they are @objc and why the tests drive
	// them directly.
	//
	// **Class methods, not instance methods.** None of them touches instance
	// state, and a test cannot construct this class at all: -init installs the
	// UNUserNotificationCenter delegate, and +currentNotificationCenter raises
	// NSInternalInconsistencyException ("bundleProxyForCurrentProcess is nil")
	// in a process that is not a bundled app — which the xctest runner is not.
	// That is pre-existing, not something the port introduced; it simply had
	// never been noticed because this framework had no tests.

	// Reports macOS wrote for `processName` since `cutOff`. The directory is a
	// parameter purely so a test can point it at a fixture; production passes
	// the real one.
	@objc static func reports(forProcessName processName: String, notBefore cutOff: Date, in directory: String) -> [String] {
		let timeFormat = processName + "_%F-%H%M%S"

		var res: [String] = []
		for fileName in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [] {
			guard fileName.hasPrefix(processName) else { continue }

			var bsdDate = tm()
			guard strptime(fileName, timeFormat, &bsdDate) != nil else { continue }

			let seconds = mktime(&bsdDate)
			if seconds != -1 && Double(seconds) >= cutOff.timeIntervalSince1970 {
				res.append((directory as NSString).appendingPathComponent(fileName))
			}
		}
		return res
	}

	// Builds the multipart/form-data body and sets the request's method and
	// Content-Type. A value beginning with "@" names a file to attach.
	@objc(dataForURLRequest:withFormValues:)
	static func data(for request: NSMutableURLRequest, withFormValues payload: [String: String]) -> Data {
		var swiftRequest = request as URLRequest
		let res = data(for: &swiftRequest, withFormValues: payload)
		request.httpMethod = swiftRequest.httpMethod ?? "POST"
		if let contentType = swiftRequest.value(forHTTPHeaderField: "Content-Type") {
			request.setValue(contentType, forHTTPHeaderField: "Content-Type")
		}
		return res
	}

	private static func data(for request: inout URLRequest, withFormValues payload: [String: String]) -> Data {
		let boundary = UUID().uuidString

		request.httpMethod = "POST"
		request.setValue("multipart/form-data; boundary=\"\(boundary)\"", forHTTPHeaderField: "Content-Type")

		var body = Data()
		for (name, value) in payload {
			var head = [ "--\(boundary)" ]
			var partData: Data

			if value.hasPrefix("@") {
				let path = String(value.dropFirst())
				head.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\((path as NSString).lastPathComponent)\"")
				head.append("Content-Type: application/octet-stream")
				partData = FileManager.default.contents(atPath: path) ?? Data()
			} else {
				head.append("Content-Disposition: form-data; name=\"\(name)\"")
				partData = Data(value.utf8)
			}

			body.append(Data(head.joined(separator: "\r\n").utf8))
			body.append(Data("\r\n\r\n".utf8))
			body.append(partData)
			body.append(Data("\r\n".utf8))
		}
		body.append(Data("--\(boundary)--\r\n".utf8))

		return body
	}

	// gzips the file at `path` into a per-bundle temporary directory, returning
	// the new path. nil on any failure, each of which is logged.
	@objc static func pathForGZipCompressedFile(atPath path: String) -> String? {
		guard let data = FileManager.default.contents(atPath: path) else {
			CrashReporter.logError("Failed reading \(path)")
			return nil
		}

		let gzPath = NSString.path(withComponents: [
			NSTemporaryDirectory(),
			Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName,
			"\((path as NSString).lastPathComponent).gz",
		])

		let parent = (gzPath as NSString).deletingLastPathComponent
		guard (try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)) != nil else {
			CrashReporter.logError("Failed creating directory \(parent)")
			return nil
		}

		// zlib is not reachable from Swift; see CRSupport.h.
		return CRWriteGZipFile(data, gzPath) ? gzPath : nil
	}

	private static func hardwareInfo(_ field: Int32, isInteger: Bool = false) -> String {
		var request = [ CTL_HW, field ]
		var size = 0
		guard sysctl(&request, UInt32(request.count), nil, &size, nil, 0) != -1, size != 0 else { return "???" }

		var buf = [UInt8](repeating: 0, count: size)
		guard sysctl(&request, UInt32(request.count), &buf, &size, nil, 0) != -1 else { return "???" }

		if isInteger && size == MemoryLayout<Int32>.size {
			return String(buf.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
		}
		// Sized from the first sysctl rather than assumed, and NUL-trimmed —
		// the ObjC++ used a fixed 1024-byte buffer and +initWithUTF8String:.
		return String(decoding: buf.prefix(while: { $0 != 0 }), as: UTF8.self)
	}

	private static let log = OSLog(subsystem: "com.j23software.TextMate", category: "crash-reporter")
	private static func log(_ message: String)      { os_log("%{public}@", log: log, type: .default, message) }
	private static func logError(_ message: String) { os_log("%{public}@", log: log, type: .error, message) }
}

// MARK: - Notification delegates

extension CrashReporter: UNUserNotificationCenterDelegate {
	// ⚠️ -userNotificationCenter:willPresentNotification:withCompletionHandler:
	// is deliberately NOT here — it is in CRSupport.mm. See the comment there:
	// under this project's -cxx-interoperability-mode it cannot be satisfied
	// from Swift at all, in either spelling.
	//
	// This one is fine, and the difference is instructive: its completion
	// handler takes no arguments, so no NS_OPTIONS type crosses the boundary.
	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		openURL(in: response.notification.request.content.userInfo)
		completionHandler()
	}

}

extension CrashReporter: NSUserNotificationCenterDelegate {
	// Deprecated since macOS 11, and kept for the same reason the ObjC++ kept
	// it: a notification posted by an older build can still be delivered
	// through this path after an update.
	func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
		return true
	}

	func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
		openURL(in: notification.userInfo)
	}
}

private extension CrashReporter {
	func openURL(in userInfo: [AnyHashable: Any]?) {
		guard let urlString = userInfo?["url"] as? String, let url = URL(string: urlString) else { return }
		NSWorkspace.shared.open(url)
	}
}
