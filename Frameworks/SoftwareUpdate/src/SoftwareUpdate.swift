import AppKit
import os

// Ported from SoftwareUpdate.mm — the version check and its background schedule.
// The three view controllers it drives are in SUDownloadViewController.swift.
//
// The class's ObjC face is the hand declaration in SoftwareUpdate.h (rule 23),
// kept out of the bridging header (rule 43). AppController calls -checkForUpdate:
// and SoftwareUpdatePreferences binds to `checking`.
//
// **`checking` and `errorString` are `@objc dynamic` and must stay that way.**
// SoftwareUpdatePreferences binds its Check Now button to `checking` and reads
// `errorString` through keyPathsForValuesAffecting…. Without `dynamic` there is
// no KVO, nothing fails to compile, and the button silently stops greying out —
// which is why t_software_update.mm pins both through Cocoa Bindings (rule 18).
//
// Not @MainActor: -setAutomaticUpdateCheckEnabled:'s scheduler block runs on
// NSBackgroundActivityScheduler's XPC queue and calls straight into
// -checkForTestBuild:, which does its own hop. See that method's comment — the
// hop is load-bearing, not tidiness.

private let log = Logger()

@objc(SoftwareUpdate)
class SoftwareUpdate: NSObject {
	// nonisolated(unsafe) for the same reason as OakDownloadManager's: this is not
	// a MainActor object, and the ObjC++ was a plain function-local static.
	@objc nonisolated(unsafe) static let sharedInstance: SoftwareUpdate = {
		registerDefaults()
		return SoftwareUpdate()
	}()

	private var updateCheckScheduler: NSBackgroundActivityScheduler?
	private let updateCheckInterval: TimeInterval = 60*60

	@objc var channels: [String: URL]?

	// Two names on purpose. The ObjC property was
	// `@property (readonly, getter = isChecking) BOOL checking`, which gives ObjC a
	// getter called `isChecking`, a setter called `setChecking:` and the KVC key
	// "checking". Swift cannot spell that combination on one property: @objc(isChecking)
	// would rename the setter to setIsChecking: and break the automatic KVO that
	// SoftwareUpdatePreferences' binding depends on.
	//
	// So the stored property keeps `checking`/`setChecking:` — which is what KVO
	// needs — and a computed `isChecking` restores the getter selector that
	// SoftwareUpdate.h promises and Preferences actually calls. Caught by the pin
	// (rule 18): nothing here fails to compile, it is an unrecognized selector at
	// runtime the first time somebody opens the Software Update pane.
	@objc dynamic private(set) var checking: Bool = false
	@objc var isChecking: Bool { checking }

	@objc dynamic private(set) var errorString: String?

	// Was +initialize, converted to explicit registration (rule 24) in its own
	// commit before this port, because a Swift class cannot provide one.
	//
	// +sharedInstance calls it, which is where +initialize effectively ran: that
	// method is the only message anything sends to this class.
	@objc static func registerDefaults() {
		_ = registerDefaultsOnce
	}

	private static let registerDefaultsOnce: Void = {
		UserDefaults.standard.register(defaults: [
			kUserDefaultsSoftwareUpdateChannelKey: kSoftwareUpdateChannelRelease
		])
	}()

	override init() {
		super.init()

		NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main) { [weak self] _ in
			self?.automaticUpdateCheckEnabled = !UserDefaults.standard.bool(forKey: kUserDefaultsDisableSoftwareUpdateKey)
		}
		automaticUpdateCheckEnabled = !UserDefaults.standard.bool(forKey: kUserDefaultsDisableSoftwareUpdateKey)
	}

	private var _automaticUpdateCheckEnabled = false
	private var automaticUpdateCheckEnabled: Bool {
		get { _automaticUpdateCheckEnabled }
		set {
			guard _automaticUpdateCheckEnabled != newValue else { return }

			updateCheckScheduler?.invalidate()
			updateCheckScheduler = nil

			_automaticUpdateCheckEnabled = newValue
			guard newValue else { return }

			let scheduler = NSBackgroundActivityScheduler(identifier: "\(Bundle.main.bundleIdentifier ?? "").SoftwareUpdate")
			scheduler.interval = updateCheckInterval
			scheduler.repeats  = true
			scheduler.schedule { completionHandler in
				if let suspendUntil = UserDefaults.standard.object(forKey: kUserDefaultsSoftwareUpdateSuspendUntilKey) as? Date {
					if suspendUntil.timeIntervalSinceNow > 0 {
						log.log("Skip version check: Suspended until \(suspendUntil as NSDate, privacy: .public)")
						completionHandler(.finished)
						return
					}
					UserDefaults.standard.removeObject(forKey: kUserDefaultsSoftwareUpdateSuspendUntilKey)
				}

				self.checkForTestBuild(false) { remoteURL, remoteVersion, error in
					self.errorString = error.map { "Error: \($0.localizedDescription)" }
					if let error {
						log.log("Failed to check for update: \(error.localizedDescription, privacy: .public)")
						completionHandler(.finished)
					} else {
						// assumeIsolated, not a hop: -checkForTestBuild: guarantees this
						// handler runs on the main thread, which is the whole point of
						// the note on that method.
						MainActor.assumeIsolated {
							let alertViewController = SUDownloadViewController(completionHandler: {
								completionHandler(.finished)
							})
							alertViewController.presentUI(forBackgroundCheck: true, remoteURL: remoteURL, remoteVersion: remoteVersion, redownloadEnabled: false)
						}
					}
				}
			}
			updateCheckScheduler = scheduler
		}
	}

	@objc func checkForUpdate(_ sender: Any?) {
		let isOptionDown = OakIsAlternateKeyOrMouseEvent(NSEvent.ModifierFlags.option.rawValue)
		let isShiftDown  = OakIsAlternateKeyOrMouseEvent(NSEvent.ModifierFlags.shift.rawValue)

		checkForTestBuild(isOptionDown) { remoteURL, remoteVersion, error in
			MainActor.assumeIsolated {
				let alertViewController = SUDownloadViewController()
				if let error {
					alertViewController.presentError(error)
				} else {
					alertViewController.presentUI(forBackgroundCheck: false, remoteURL: remoteURL, remoteVersion: remoteVersion, redownloadEnabled: isShiftDown)
				}
			}
		}
	}

	// The media type of a Content-Type header, without its parameters.
	//
	// The original compared the *whole* header against "application/json", which
	// is wrong for any server that sends a charset — and a media type with
	// parameters is perfectly legal (RFC 9110 §8.3). Against MacroMates' bucket it
	// never mattered, because that returns a bare `application/json`. It matters
	// for anywhere else: every GitHub surface returns
	// `application/json; charset=utf-8` (or `text/plain; charset=utf-8` for raw),
	// measured 2026-09-06, so a GitHub-hosted manifest would fall through to the
	// property-list parser and be reported as "Malformed server response."
	//
	// Exposed to the tests through SoftwareUpdateTesting.h rather than left
	// private: it has enough edge cases — parameters, case, whitespace — to be
	// worth pinning on its own, and it cannot be reached through
	// -checkForTestBuild: without a server.
	@objc(mediaTypeFromContentType:)
	static func mediaType(fromContentType contentType: String?) -> String? {
		guard let contentType else { return nil }
		let head = contentType.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
		let trimmed = head.trimmingCharacters(in: .whitespaces).lowercased()
		return trimmed.isEmpty ? nil : trimmed
	}

	// Runs on the main thread, and calls its completion handler there, always.
	//
	// This used to be true only of the success path — the URL session's completion
	// dispatches to main before touching `checking` — while the two early returns
	// below called back synchronously on whatever queue the caller was on. From
	// -setAutomaticUpdateCheckEnabled: that queue is NSBackgroundActivityScheduler's
	// XPC queue, so a machine with no configured update channel took an early return
	// on a background thread and set `errorString` there.
	//
	// That is a KVO notification raised off the main thread, and since 81d5d8a7 the
	// observer on the other end is Cocoa Bindings driving a **@MainActor** Swift
	// getter (SoftwareUpdatePreferences.lastCheckDescription). Swift 6 checks the
	// executor and traps: EXC_BREAKPOINT in _dispatch_assert_queue_fail, reported
	// against alpha.13 as "Settings ▸ Software Update crashes". It needs the pane to
	// have been opened once, so the binding exists, and it fires whenever the
	// background activity next runs — about twenty seconds after launch, which is
	// why clicking through every pane during a smoke pass does not surface it.
	//
	// The hop goes here rather than in the setters because automatic KVO swizzles
	// the setter: -willChangeValueForKey: runs on the *calling* thread before the
	// body does, so marshalling inside the setters would not move the notification
	// at all. Fixing the one method that owns every path is also what stops
	// `checking = true` below — same hazard, reached only when a channel *is*
	// configured — and hands the completion handler a main-thread guarantee it
	// needs anyway, since callers present UI from it.
	//
	// t_software_update_threading.mm pins this both ways round.
	@objc(checkForTestBuild:completionHandler:)
	func checkForTestBuild(_ testBuild: Bool, completionHandler: @escaping (URL?, String?, Error?) -> Void) {
		guard Thread.isMainThread else {
			// nonisolated(unsafe) states the crossing the ObjC++ made implicitly with
			// dispatch_async: neither SoftwareUpdate nor the handler is Sendable, and
			// this is precisely the hop that makes everything after it main-thread.
			nonisolated(unsafe) let unsafeSelf = self
			nonisolated(unsafe) let unsafeHandler = completionHandler
			DispatchQueue.main.async {
				unsafeSelf.checkForTestBuild(testBuild, completionHandler: unsafeHandler)
			}
			return
		}

		let updateChannel = testBuild ? kSoftwareUpdateChannelCanary : UserDefaults.standard.string(forKey: kUserDefaultsSoftwareUpdateChannelKey)
		guard let updateChannel else {
			return completionHandler(nil, nil, NSError(domain: "SoftwareUpdate", code: 0, userInfo: [NSLocalizedDescriptionKey: "No channel configured."]))
		}

		guard let url = channels?[updateChannel] else {
			return completionHandler(nil, nil, NSError(domain: "SoftwareUpdate", code: 0, userInfo: [NSLocalizedDescriptionKey: "No channel named ‘\(updateChannel)’."]))
		}

		SURunInSoftwareUpdateCheckActivity {
			self.checking = true

			var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60)
			request.setValue(OakDownloadManager.sharedInstance.userAgentString, forHTTPHeaderField: "User-Agent")

			let dataTask = URLSession.shared.dataTask(with: request) { data, response, error in
				var error = error
				var remoteURL: URL?
				var remoteVersion: String?

				if error == nil {
					if let contentType = (response as? HTTPURLResponse)?.allHeaderFields["Content-Type"] as? String {
						var plist: [String: Any]?
						if SoftwareUpdate.mediaType(fromContentType: contentType) == "application/json" {
							plist = data.flatMap { try? JSONSerialization.jsonObject(with: $0, options: []) } as? [String: Any]
						} else {
							plist = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, options: 0, format: nil) } as? [String: Any]
						}

						if let plist {
							remoteURL     = (plist["url"] as? String).flatMap { URL(string: $0) }
							remoteVersion = plist["version"] as? String
							if remoteURL == nil || remoteVersion == nil {
								error = NSError(domain: "SoftwareUpdate", code: 0, userInfo: [NSLocalizedDescriptionKey: "Incomplete server response."])
							}
						} else {
							error = NSError(domain: "SoftwareUpdate", code: 0, userInfo: [NSLocalizedDescriptionKey: "Malformed server response."])
						}
					} else {
						error = NSError(domain: "SoftwareUpdate", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing Content-Type in server response."])
					}
				}

				// Same crossing, same reason — and this is the one that has to stay:
				// `checking` is KVO-observed by a @MainActor Swift getter through
				// Cocoa Bindings, so setting it off the main thread traps (see above).
				nonisolated(unsafe) let unsafeSelf = self
				nonisolated(unsafe) let unsafeHandler = completionHandler
				nonisolated(unsafe) let unsafeRemoteURL = remoteURL
				nonisolated(unsafe) let unsafeError = error
				DispatchQueue.main.async {
					UserDefaults.standard.set(Date(), forKey: kUserDefaultsLastSoftwareUpdateCheckKey)
					unsafeSelf.checking = false
					unsafeHandler(unsafeRemoteURL, remoteVersion, unsafeError)
				}
			}
			dataTask.resume()
		}
	}
}
