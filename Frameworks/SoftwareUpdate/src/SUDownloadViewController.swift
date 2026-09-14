import AppKit
import os

// Ported from the second half of SoftwareUpdate.mm: the update panel, its info
// and progress pages, and the download/install flow behind them.
//
// All three are @MainActor — they are view controllers, every API they touch is
// main-thread-only, and SoftwareUpdate creates them from -checkForTestBuild:'s
// completion handler, which that method guarantees runs on the main thread. The
// two creation sites say so with MainActor.assumeIsolated rather than hoping.
//
// None of these is @objc: nothing outside this framework names them, and
// SoftwareUpdate.swift is in the same module. Keeping them out of the ObjC
// runtime is not an optimisation — it is what stops a hand declaration from
// existing to drift (rule 23 applies only where ObjC++ still consumes a class).

private let log = Logger()

// ========================
// = SUInfoViewController =
// ========================

@MainActor
final class SUInfoViewController: NSViewController {
	private(set) var messageTextField: NSTextField!
	private(set) var informativeTextField: NSTextField!

	override func loadView() {
		let messageTextField     = NSTextField(labelWithString: "New Version Available")
		let informativeTextField = NSTextField(wrappingLabelWithString: "Would you like to download and install?")

		let stackView = NSStackView(views: [messageTextField, informativeTextField])

		stackView.orientation = .vertical
		stackView.alignment   = .leading
		stackView.setHuggingPriority(NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.defaultHigh.rawValue - 1), for: .vertical)

		messageTextField.isSelectable     = true
		messageTextField.font             = NSFont.boldSystemFont(ofSize: 0)
		informativeTextField.isSelectable = true
		informativeTextField.font         = NSFont.messageFont(ofSize: NSFont.smallSystemFontSize)

		stackView.widthAnchor.constraint(equalToConstant: 298).isActive = true

		self.messageTextField     = messageTextField
		self.informativeTextField = informativeTextField
		self.view = stackView
	}
}

// ============================
// = SUProgressViewController =
// ============================

@MainActor
// @objc so t_software_update.mm can reach it. Not otherwise needed — nothing
// outside this file uses the class — and added only because the crash it now
// guards was unreachable from any test, which is how it shipped twice.
@objc(SUProgressViewController)
final class SUProgressViewController: NSViewController {
	// @objc alongside the class name, so the test can read what the timer wrote.
	@objc private(set) var messageTextField: NSTextField!
	@objc private(set) var informativeTextField: NSTextField!
	@objc private(set) var progressIndicator: NSProgressIndicator!

	private var checkProgressTimer: Timer?

	private var _progress: Progress?
	@objc var progress: Progress? {
		get { _progress }
		set {
			if _progress != nil && newValue == nil {
				checkProgressTimerDidFire(nil)
			}

			_progress = newValue
			if newValue != nil {
				checkProgressTimerDidFire(nil)

				checkProgressTimer = Timer.scheduledTimer(timeInterval: 0.04, target: self, selector: #selector(checkProgressTimerDidFire(_:)), userInfo: nil, repeats: true)
				checkProgressTimerDidFire(checkProgressTimer)
			} else {
				checkProgressTimer?.invalidate()
				checkProgressTimer = nil
			}
		}
	}

	override func loadView() {
		let messageTextField     = NSTextField(labelWithString: "Downloading Archive…")
		let progressIndicator    = NSProgressIndicator(frame: .zero)
		let informativeTextField = NSTextField(labelWithString: "999.9 MB of 999.9 MB — About 59 minutes, 59 seconds remaining")

		messageTextField.isSelectable     = true
		progressIndicator.maxValue        = 1
		progressIndicator.isIndeterminate = false
		informativeTextField.font         = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
		informativeTextField.isSelectable = true

		let stackView = NSStackView(views: [messageTextField, progressIndicator, informativeTextField])
		stackView.spacing     = 0
		stackView.orientation = .vertical
		stackView.alignment   = .leading

		stackView.widthAnchor.constraint(greaterThanOrEqualToConstant: informativeTextField.fittingSize.width + 20).isActive = true

		self.messageTextField     = messageTextField
		self.progressIndicator    = progressIndicator
		self.informativeTextField = informativeTextField
		self.view = stackView
	}

	override func viewWillAppear() {
		if _progress != nil {
			checkProgressTimerDidFire(nil)
		}
	}

	override func viewDidDisappear() {
		checkProgressTimer?.invalidate()
	}

	@objc func checkProgressTimerDidFire(_ timer: Timer?) {
		// **The three fields are IUO and only exist once -loadView has run, and this
		// method is reached before that happens.** -downloadSoftwareUpdate: sets
		// `progress` and *then* installs the view:
		//
		//     progressViewController.progress = progressReporting.progress   // fires this
		//     contentViewController.subview = progressViewController.view    // runs loadView
		//
		// so on the first download of a session every one of them is nil here. In the
		// ObjC++ these were nil ivars and -setStringValue: on nil did nothing (rule
		// 33); as Swift implicitly-unwrapped optionals (rule 44) the same nil is a
		// trap, and it killed the app the moment anybody clicked Download. It shipped
		// in alpha.22 and alpha.23 and is the reason neither can install an update.
		//
		// `isViewLoaded` rather than reordering the two lines at the call site: doing
		// nothing is precisely what the original did, it holds for every caller
		// instead of one, and it does not force a view to load as a side effect of
		// reporting progress. Nothing is lost by skipping — -viewWillAppear calls this
		// again once there is a view, and the timer is still running every 0.04s.
		guard isViewLoaded else { return }

		// Messaging a nil _progress returned nil/0 in the original, and -stringValue
		// tolerates neither, so the fallbacks are what nil-messaging did.
		messageTextField.stringValue     = _progress?.localizedDescription ?? ""
		informativeTextField.stringValue = (_progress?.isIndeterminate ?? false) ? "Estimating time remaining." : (_progress?.localizedAdditionalDescription ?? "")
		progressIndicator.doubleValue    = _progress?.fractionCompleted ?? 0
	}
}

// ============================
// = SUDownloadViewController =
// ============================

@MainActor
final class SUDownloadViewController: NSViewController {
	private var retainedSelf: SUDownloadViewController?

	// nonisolated(unsafe) so `deinit` can call it: a @MainActor class's deinit is
	// nonisolated, and the ObjC++ -dealloc invoked this same block.
	private nonisolated(unsafe) var completionHandler: (() -> Void)?
	private var runModalCompletionHandler: ((NSApplication.ModalResponse) -> Bool)?

	private var downloadedArchiveURL: URL?
	// The verified manifest for the update being offered. Held rather than passed
	// around so the Retry button has the checksum too — retrying a download that
	// then skipped its verification would be the obvious way to reintroduce the
	// hole step 4 closes.
	private var manifest: UpdateManifest?

	private var _buttonStackView: NSStackView?

	private var updateBadgeVisible = false

	// No `publicKeys` any more. The archive used to be vouched for by a signature
	// in its response headers, checked against Info.plist's TMSigningKeys; it is
	// now vouched for by the checksum inside the signed manifest, so this
	// controller needs no keys at all. **TMSigningKeys is consequently unreferenced
	// by the application** — BundlesManager takes its keys from inside the
	// downloaded bundle index, not from Info.plist — but removing it is a separate
	// change and does not belong in a commit about verification.

	private let contentViewController: OakTransitionViewController
	private let infoViewController: SUInfoViewController
	private let progressViewController: SUProgressViewController

	init(completionHandler: (() -> Void)? = nil) {
		self.completionHandler      = completionHandler

		self.contentViewController  = OakTransitionViewController()
		self.infoViewController     = SUInfoViewController()
		self.progressViewController = SUProgressViewController()

		super.init(nibName: nil, bundle: nil)

		self.title = ""
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		completionHandler?()
	}

	private var buttonStackView: NSStackView {
		if let _buttonStackView {
			return _buttonStackView
		}
		let stackView = NSStackView(frame: .zero)
		stackView.spacing = 16
		stackView.setHuggingPriority(NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.defaultHigh.rawValue - 1), for: .vertical)
		_buttonStackView = stackView
		return stackView
	}

	private var buttons: [NSButton] {
		return buttonStackView.views.reversed().compactMap { $0 as? NSButton }
	}

	@discardableResult
	private func addButton(withTitle title: String) -> NSButton {
		let countOfButtons = buttons.count

		let button = NSButton(title: title, target: self, action: #selector(didClickButton(_:)))
		button.tag = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + countOfButtons
		if countOfButtons == 0 {
			button.keyEquivalent = "\r"
		} else if title == "Cancel" {
			button.keyEquivalent = "\u{1b}"
		}

		button.setContentCompressionResistancePriority(.required, for: .horizontal)
		let widthConstraint = button.widthAnchor.constraint(equalToConstant: 86)
		widthConstraint.priority = .defaultHigh
		widthConstraint.isActive = true

		buttonStackView.insertView(button, at: 0, in: .trailing)

		return button
	}

	override func loadView() {
		let image = NSImage(named: NSImage.applicationIconName)
		image?.size = NSMakeSize(64, 64)

		let views: [String: NSView] = [
			"image":   NSImageView(image: image ?? NSImage()),
			"content": contentViewController.view,
			"buttons": buttonStackView,
		]

		let contentView = NSView(frame: .zero)
		OakAddAutoLayoutViewsToSuperview(Array(views.values), contentView)

		NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(24)-[image(==64)]-(16)-[content]-|",          options: .alignAllTop, metrics: nil, views: views))
		NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: "H:[image]-(>=20)-[buttons]-|",                     options: [],           metrics: nil, views: views))
		NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: "V:|-(16)-[image(==64)]-(>=20)-|",                  options: [],           metrics: nil, views: views))
		NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: "V:[content]-(==20@750,>=20@250)-[buttons]-(18)-|", options: [],           metrics: nil, views: views))

		self.view = contentView
	}

	override func viewWillAppear() {
		retainedSelf = self
	}

	override func viewDidDisappear() {
		setUpdateBadgeVisible(false)
		progressViewController.progress?.cancel()

		if let downloadedArchiveURL {
			do {
				try FileManager.default.removeItem(at: downloadedArchiveURL)
			} catch {
				log.error("Unable to remove \(downloadedArchiveURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
			}
			self.downloadedArchiveURL = nil
		}

		retainedSelf = nil
	}

	// `override`, because the ObjC `- (BOOL)presentError:(NSError*)error` was
	// overriding NSResponder's too — the error-presentation chain reaches this
	// controller and gets the update panel instead of a default alert. Swift made
	// that explicit rather than changing it.
	@discardableResult
	override func presentError(_ error: Error) -> Bool {
		contentViewController.subview = infoViewController.view

		infoViewController.messageTextField.stringValue     = "Error Checking for Update"
		infoViewController.informativeTextField.stringValue = error.localizedDescription
		addButton(withTitle: "OK")

		runModal(completionHandler: nil)

		return true
	}

	private func presentAlert(message messageText: String, informativeText: String, buttonTitles: [String], completionHandler: ((NSApplication.ModalResponse) -> Bool)?) {
		let alert = NSAlert()

		alert.messageText     = messageText
		alert.informativeText = informativeText

		for title in buttonTitles {
			alert.addButton(withTitle: title)
		}

		guard let window = view.window else { return }
		alert.beginSheetModal(for: window) { returnCode in
			MainActor.assumeIsolated {
				if completionHandler == nil || completionHandler!(returnCode) {
					self.view.window?.close()
				}
			}
		}
	}

	private func runModal(completionHandler: ((NSApplication.ModalResponse) -> Bool)?) {
		let window = NSPanel(contentViewController: self)

		window.animationBehavior       = .alertPanel
		window.isExcludedFromWindowsMenu = true
		window.hidesOnDeactivate       = false
		window.level                   = .modalPanel
		window.styleMask               = .titled

		// If we use -[NSApplication runModalForWindow:] then the window
		// won’t stay above document windows after the modal session ends
		runModalCompletionHandler = completionHandler
		window.makeKeyAndOrderFront(self)
	}

	@objc private func didClickButton(_ sender: Any?) {
		let tag = (sender as? NSButton)?.tag ?? 0
		if runModalCompletionHandler == nil || runModalCompletionHandler!(NSApplication.ModalResponse(rawValue: tag)) {
			view.window?.close()
		}
		runModalCompletionHandler = nil
	}

	private func setUpdateBadgeVisible(_ flag: Bool) {
		guard updateBadgeVisible != flag else { return }

		updateBadgeVisible = flag
		if flag {
			if let dlBadge = NSImage(named: "Update Badge", inSameBundleAsClass: SUDownloadViewController.self), let appIcon = NSApp.applicationIconImage {
				NSApp.applicationIconImage = NSImage(size: appIcon.size, flipped: false) { dstRect in
					let upperRightRect = dstRect.intersection(dstRect.offsetBy(dx: (dstRect.width * 2 / 3).rounded(), dy: dstRect.height * 2 / 3))
					appIcon.draw(in: dstRect, from: .zero, operation: .copy, fraction: 1)
					dlBadge.draw(in: upperRightRect, from: .zero, operation: .sourceOver, fraction: 1)
					return true
				}
			}
		} else {
			NSApp.applicationIconImage = nil
		}
	}

	func presentUI(forBackgroundCheck backgroundCheck: Bool, manifest: UpdateManifest?, redownloadEnabled allowRedownload: Bool) {
		self.manifest = manifest

		let localVersion  = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
		let remoteVersion = manifest?.version
		let ordering = OakCompareVersionStrings(localVersion, remoteVersion)

		if backgroundCheck && ordering != .orderedAscending {
			return
		}

		contentViewController.subview = infoViewController.view

		let appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? ""
		// A newer version that this Mac cannot run is not an offer, it is an
		// explanation. Offering Download here would install a bundle whose own
		// LSMinimumSystemVersion stops macOS launching it, and the application that
		// could have told the user so has already been replaced. See
		// +manifestRunsOnThisSystem: — the unattended path skips these silently,
		// but somebody who asked deserves to know why the answer is no.
		if ordering == .orderedAscending && !SoftwareUpdate.manifestRunsOnThisSystem(manifest) {
			infoViewController.messageTextField.stringValue     = "Update Requires a Newer macOS"
			infoViewController.informativeTextField.stringValue = "\(appName) \(remoteVersion ?? "") requires macOS \(manifest?.minimumSystemVersion ?? "?") or later. This Mac is running macOS \(SoftwareUpdate.runningSystemVersion()), so the update has not been installed."

			addButton(withTitle: "OK")
		} else if ordering == .orderedAscending {
			infoViewController.messageTextField.stringValue     = "New Version Available"
			infoViewController.informativeTextField.stringValue = "\(appName) \(remoteVersion ?? "") is now available. You have version \(localVersion ?? ""). Would you like to download it now?"

			addButton(withTitle: "Download")
			addButton(withTitle: backgroundCheck ? "Later" : "Cancel")
			buttons.last?.keyEquivalent = "\u{1b}"
		} else if ordering == .orderedSame {
			infoViewController.messageTextField.stringValue     = "Up To Date"
			infoViewController.informativeTextField.stringValue = "You are running \(remoteVersion ?? "") which is the latest version available."

			addButton(withTitle: "OK")
			if allowRedownload {
				addButton(withTitle: "Redownload")
			}
		} else if ordering == .orderedDescending {
			infoViewController.messageTextField.stringValue     = "You are Using a Prerelease"
			infoViewController.informativeTextField.stringValue = "\(remoteVersion ?? "") is the latest version available. You have version \(localVersion ?? "")."

			addButton(withTitle: "OK")
			addButton(withTitle: "Downgrade to \(remoteVersion ?? "")")
		}

		// `expected` is the response that means "go ahead and download". The
		// too-old-macOS branch has a single OK button, whose tag is
		// alertFirstButtonReturn — the same tag Download carries — so without this
		// it would read as consent and start the download it just declined to offer.
		let offersDownload = (ordering == .orderedAscending) && SoftwareUpdate.manifestRunsOnThisSystem(manifest)
		runModal { response in
			let expected: NSApplication.ModalResponse = offersDownload ? .alertFirstButtonReturn : .alertSecondButtonReturn
			if response == expected {
				var sfsb = statfs()
				let readOnly = Bundle.main.bundlePath.withCString { statfs($0, &sfsb) == 0 } && (sfsb.f_flags & UInt32(MNT_RDONLY)) != 0
				if readOnly {
					let informativeText = "\(appName) is running on a read-only file system and can therefore not be updated.\n\nIf you downloaded \(appName) from the internet then moving it out of the Downloads folder should solve the problem."
					self.presentAlert(message: "Read-only File System", informativeText: informativeText, buttonTitles: ["OK"]) { _ in
						return true // Close window
					}
				} else if let manifest {
					self.downloadSoftwareUpdate(manifest)
				}
				return false // Keep window open
			} else {
				if backgroundCheck {
					UserDefaults.standard.set(Date().addingTimeInterval(24*60*60), forKey: kUserDefaultsSoftwareUpdateSuspendUntilKey)
				}
				return true // Close window
			}
		}
	}

	@objc private func cancel(_ sender: Any?) {
		view.window?.close()
	}

	// Retry. Reads the stored manifest rather than a URL off the button, so the
	// checksum comes along with it.
	@objc private func takeURLToDownloadFrom(_ sender: NSButton) {
		if let manifest {
			downloadSoftwareUpdate(manifest)
		}
	}

	private func downloadSoftwareUpdate(_ manifest: UpdateManifest) {
		self.manifest = manifest
		let downloadURL = manifest.url

		let progressReporting = OakDownloadManager.sharedInstance.downloadArchive(at: downloadURL, forReplacing: Bundle.main.bundleURL, expectedSHA256: manifest.sha256, expectedSize: manifest.size) { extractedArchiveURL, error in
			MainActor.assumeIsolated {
				self.progressViewController.progress = nil

				if let extractedArchiveURL {
					self.setUpdateBadgeVisible(true)
					if NSApp.isActive {
						OakPlayUISound(OakSoundDidCompleteSomethingUISound)
					}

					self.progressViewController.messageTextField.stringValue = "Downloaded \(downloadURL.lastPathComponent)"

					self.buttons[0].isEnabled              = true
					self.buttons[0].cell?.representedObject = extractedArchiveURL
					self.buttons[0].action                 = #selector(self.takeURLToInstallFrom(_:))

					self.downloadedArchiveURL = extractedArchiveURL // Will be deleted in viewDidDisappear
				} else {
					self.progressViewController.messageTextField.stringValue     = "Error Downloading Update"
					self.progressViewController.informativeTextField.stringValue = error?.localizedDescription ?? ""

					self.buttons[0].title                  = "Retry"
					self.buttons[0].isEnabled              = true
					self.buttons[0].action                 = #selector(self.takeURLToDownloadFrom(_:))
				}
			}
		}

		progressViewController.progress = progressReporting.progress
		contentViewController.subview = progressViewController.view

		buttons[0].title         = "Install & Relaunch"
		buttons[0].isEnabled     = false

		buttons[1].title         = "Cancel"
		buttons[1].action        = #selector(cancel(_:))
		buttons[1].keyEquivalent = "\u{1b}"
	}

	// Was an executable-bit check on Contents/MacOS/<name>, which answered "is this
	// shaped like an app" and nothing about whether it should be installed. Now it
	// answers the two questions that matter: will macOS run it, and is it the build
	// the manifest described (step 5).
	//
	// The old check is not kept alongside: a valid signature over a bundle that has
	// no executable is not a thing that happens, and two overlapping checks would
	// mean two error paths for one failure.
	// Returns the reason it is not installable, or nil when it is. Was a Bool, and
	// the Bool is what made the dialog below lie: the caller had no way to tell a
	// bundle that arrived damaged from one that is intact and unacceptable.
	private func reasonNotInstallable(at applicationURL: URL) -> Error? {
		guard let manifest else {
			log.error("No manifest for the downloaded update; refusing to install it")
			return NSError(domain: UpdateVerificationError.errorDomain,
			               code: UpdateVerificationError.signatureNotValid.rawValue,
			               userInfo: [NSLocalizedDescriptionKey: "The update could not be checked against its manifest."])
		}

		do {
			try UpdateVerification.checkCodeSignature(ofBundleAt: applicationURL, requirement: UpdateVerification.designatedRequirement)
			try UpdateVerification.checkBundle(at: applicationURL, matches: manifest)
			return nil
		} catch {
			log.error("Refusing to install \(applicationURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
			return error
		}
	}

	@objc private func takeURLToInstallFrom(_ sender: NSButton) {
		guard let applicationURL = sender.cell?.representedObject as? URL else { return }

		let appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? ""

		// **This used to say "The download is incomplete. This can happen if the
		// system has been deleting temporary files" and offer Redownload, whatever
		// had gone wrong.** By the time execution reaches here the payload has
		// already matched the SHA-256 and the size inside the signed manifest, so
		// an incomplete download is very nearly the one thing it cannot be. The
		// text was written for the check this replaced — an executable-bit test —
		// and step 5 changed what the guard means without changing what it says.
		//
		// Getting it wrong is not cosmetic. A build signed by the wrong identity,
		// or one whose version disagrees with its manifest, is intact: downloading
		// it again produces the same bytes and the same refusal, so the offered
		// remedy is an infinite loop, and the actual reason — which may be that
		// somebody is serving a payload we did not build — is never shown.
		if let reason = reasonNotInstallable(at: applicationURL) {
			let retryable = UpdateVerification.isWorthRetrying(reason)
			let message = retryable ? "The Update Could Not Be Verified" : "Update Refused"
			let informativeText = retryable
				? "\(reason.localizedDescription)\n\nThe download may have been damaged after it arrived. Would you like to download it again?"
				: "\(reason.localizedDescription)\n\nThe download matched its signed description, so downloading it again will not help. \(appName) has not been changed."

			presentAlert(message: message, informativeText: informativeText,
			             buttonTitles: retryable ? ["Redownload", "Cancel"] : ["OK"]) { returnCode in
				// With one button there is nothing to redownload; close on any response.
				guard retryable else { return true }

				if returnCode == .alertFirstButtonReturn {
					if let manifest = self.manifest {
						self.downloadSoftwareUpdate(manifest)
					}

					do {
						try FileManager.default.removeItem(at: applicationURL)
					} catch {
						log.error("Unable to remove \(applicationURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
					}

					self.downloadedArchiveURL = nil
				}
				return returnCode == .alertSecondButtonReturn // Close window if clicking “Cancel”
			}
			return
		}

		progressViewController.messageTextField.stringValue     = "Installing \(appName)…"
		progressViewController.informativeTextField.stringValue = ""
		progressViewController.progressIndicator.isIndeterminate = true
		progressViewController.progressIndicator.startAnimation(self)

		buttons[0].isEnabled = false
		buttons[1].isEnabled = false

		do {
			try FileManager.default.replaceItem(at: Bundle.main.bundleURL, withItemAt: applicationURL, backupItemName: nil, options: .usingNewMetadataOnly, resultingItemURL: nil)

			progressViewController.messageTextField.stringValue = "Relaunching \(appName)…"

			let script = "{ kill \(getpid()); while ps -xp \(getpid()); do if (( ++n == 300 )); then exit; fi; sleep .2; done; open \"$0\" --args $1; } &>/dev/null &"

			let task = Process()
			task.launchPath     = "/bin/sh"
			task.arguments      = [ "-c", script, Bundle.main.bundlePath, "-showReleaseNotes YES" ]
			task.standardInput  = FileHandle.nullDevice
			task.standardOutput = FileHandle.nullDevice
			task.standardError  = FileHandle.nullDevice

			// The original wrapped -launch in @try/@catch; -run() surfaces the same
			// failure as a Swift error, which Swift can actually catch.
			do {
				try task.run()
			} catch {
				log.error("-[NSTask launch]: \(error.localizedDescription, privacy: .public)")
			}
		} catch {
			progressViewController.progressIndicator.stopAnimation(self)
			progressViewController.progressIndicator.isIndeterminate = false

			presentAlert(message: "Failed to Install Update", informativeText: error.localizedDescription, buttonTitles: ["Retry", "Cancel"]) { returnCode in
				if returnCode == .alertFirstButtonReturn {
					self.takeURLToInstallFrom(sender)
				}
				return returnCode == .alertSecondButtonReturn // Close window if clicking “Cancel”
			}
		}
	}
}
