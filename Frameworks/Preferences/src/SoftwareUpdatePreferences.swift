import AppKit

@objc(SoftwareUpdatePreferences) final class SoftwareUpdatePreferences: PreferencesPane {
	private var relativeDateUserDefaultsObserver: NSObjectProtocol?
	private var relativeDateUpdateTimer: Timer?

	@objc dynamic private var relativeStringForLastCheck: String?

	@objc class func keyPathsForValuesAffectingLastCheckDescription() -> Set<String> {
		["softwareUpdateController.checking", "softwareUpdateController.errorString", "relativeStringForLastCheck"]
	}

	init() {
		super.init(nibName: nil, label: "Software Update", image: NSImage(named: "Software Update", inSameBundleAsClass: SoftwareUpdatePreferences.self))
		OakStringListTransformer.createTransformer(withName: "OakSoftwareUpdateChannelTransformer", andObjectsArray: [kSoftwareUpdateChannelRelease, kSoftwareUpdateChannelPrerelease])
	}

	@objc dynamic var softwareUpdateController: SoftwareUpdate {
		SoftwareUpdate.sharedInstance
	}

	@objc dynamic var lastCheckDescription: String {
		if softwareUpdateController.isChecking {
			return "Checking…"
		}
		return softwareUpdateController.errorString ?? relativeStringForLastCheck ?? "Never"
	}

	private func relativeString(for date: Date?) -> String? {
		guard let date else { return nil }
		return -date.timeIntervalSinceNow < 5 ? "Just now" : RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date.now)
	}

	private func refreshRelativeString() {
		relativeStringForLastCheck = relativeString(for: UserDefaults.standard.object(forKey: kUserDefaultsLastSoftwareUpdateCheckKey) as? Date)
	}

	override func viewWillAppear() {
		relativeDateUserDefaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main) { [weak self] _ in
			MainActor.assumeIsolated { self?.refreshRelativeString() }
		}

		relativeDateUpdateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated { self?.refreshRelativeString() }
		}

		refreshRelativeString()
	}

	override func viewDidDisappear() {
		relativeDateUpdateTimer?.invalidate()
		relativeDateUpdateTimer = nil
		if let relativeDateUserDefaultsObserver {
			NotificationCenter.default.removeObserver(relativeDateUserDefaultsObserver)
			self.relativeDateUserDefaultsObserver = nil
		}
	}

	override func loadView() {
		// Explicit types: see the note in FilesPreferences.loadView().
		let watchForUpdatesCheckBox: NSButton      = OakCreateCheckBox("Watch for:")
		let updateChannelPopUp: NSPopUpButton      = OakCreatePopUpButton(false, nil, nil)
		let askBeforeDownloadingCheckBox: NSButton = OakCreateCheckBox("Ask before downloading updates")

		let watchForStackView = NSStackView(views: [watchForUpdatesCheckBox, updateChannelPopUp])
		watchForStackView.alignment = .firstBaseline

		let lastCheckTextField: NSTextField = OakCreateLabel("Some time ago", nil, .left, .byTruncatingMiddle)
		let checkNowButton     = NSButton(title: "Check Now", target: softwareUpdateController, action: #selector(SoftwareUpdate.checkForUpdate(_:)))

		// Was "Submit to MacroMates": as of Phase 2.5 (2026-07-26), AppController.mm
		// no longer calls postNewCrashReportsToURLString: (that URL pointed at
		// MacroMates' collector, which this fork isn't affiliated with), so this
		// checkbox does not currently submit anywhere regardless of its state.
		let submitCrashReportsCheckBox: NSButton = OakCreateCheckBox("Submit crash reports")

		let contactTextField = NSTextField(string: "Anonymous")

		let smallFont = NSFont.messageFont(ofSize: NSFont.systemFontSize(for: .small))
		contactTextField.font = smallFont
		contactTextField.controlSize = .small

		let contactLabel: NSTextField = OakCreateLabel("Contact:", smallFont, .left, .byTruncatingMiddle)
		let contactStackView = NSStackView(views: [contactLabel, contactTextField])
		contactStackView.alignment = .firstBaseline
		contactStackView.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 0)
		contactStackView.setHuggingPriority(.defaultHigh - 1, for: .vertical)

		// MBMenu (a C++ aggregate) in the original — see FilesPreferences.swift.
		for (index, title) in ["Normal releases", "Prereleases"].enumerated() {
			updateChannelPopUp.menu?.addItem(withTitle: title, action: nil, keyEquivalent: "").tag = index
		}

		func label(_ text: String) -> NSTextField {
			OakCreateLabel(text, nil, .left, .byTruncatingMiddle)
		}

		let gridView = NSGridView(views: [
			[label("Software update:"), watchForStackView],
			[NSGridCell.emptyContentView, askBeforeDownloadingCheckBox],
			[],
			[label("Last check:"), lastCheckTextField],
			[NSGridCell.emptyContentView, checkNowButton],
			[],
			[label("Crash reports:"), submitCrashReportsCheckBox],
			[NSGridCell.emptyContentView, contactStackView],
		])

		contactTextField.trailingAnchor.constraint(equalTo: updateChannelPopUp.trailingAnchor).isActive = true

		view = PWSetupGridView(gridView, [2, 5])

		let defaultsController = NSUserDefaultsController.shared
		let negate = NSValueTransformerName.negateBooleanTransformerName
		func values(_ key: String) -> String { "values.\(key)" }

		watchForUpdatesCheckBox.bind(.value,      to: defaultsController, withKeyPath: values(kUserDefaultsDisableSoftwareUpdateKey),   options: [.valueTransformerName: negate])
		updateChannelPopUp.bind(.selectedTag,     to: defaultsController, withKeyPath: values(kUserDefaultsSoftwareUpdateChannelKey),   options: [.valueTransformerName: NSValueTransformerName("OakSoftwareUpdateChannelTransformer")])
		askBeforeDownloadingCheckBox.bind(.value, to: defaultsController, withKeyPath: values(kUserDefaultsAskBeforeUpdatingKey),       options: nil)
		lastCheckTextField.bind(.value,           to: self,               withKeyPath: "lastCheckDescription",                          options: nil)
		submitCrashReportsCheckBox.bind(.value,   to: defaultsController, withKeyPath: values(kUserDefaultsDisableCrashReportingKey),   options: [.valueTransformerName: negate])
		contactTextField.bind(.value,             to: defaultsController, withKeyPath: values(kUserDefaultsCrashReportsContactInfoKey), options: nil)

		updateChannelPopUp.bind(.enabled,         to: defaultsController, withKeyPath: values(kUserDefaultsDisableSoftwareUpdateKey),   options: [.valueTransformerName: negate])
		askBeforeDownloadingCheckBox.bind(.enabled, to: defaultsController, withKeyPath: values(kUserDefaultsDisableSoftwareUpdateKey), options: [.valueTransformerName: negate])
		checkNowButton.bind(.enabled,             to: softwareUpdateController, withKeyPath: "checking",                                options: [.valueTransformerName: negate])
		contactTextField.bind(.enabled,           to: defaultsController, withKeyPath: values(kUserDefaultsDisableCrashReportingKey),   options: [.valueTransformerName: negate])
	}
}
