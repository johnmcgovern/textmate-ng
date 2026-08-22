import AppKit

// Ported from OakSavePanel.mm once OakSavePanelSupport had taken the C++.
//
// The class keeps a second, C++-typed entry point in OakSavePanelCxx.mm, and it
// has to: rule 15 says a block parameter with a C++ type makes a method
// uncallable from Swift, and both callers hand in an encoding::type *and* take
// one back out of the completion block. That forwarder is the only ObjC++ left
// here, and it is twelve lines.

@objc(OakEncodingSaveOptionsViewController)
class OakEncodingSaveOptionsViewController: NSViewController, @preconcurrency NSOpenSavePanelDelegate {
	@objc var encodingOptions: OakEncodingOptions
	@objc var fileType: String?

	// The two binding key paths. Nothing declares them publicly, but the accessory
	// view binds to them by name, so they are API.
	@objc dynamic var lineEndings: String?
	@objc dynamic var encoding: String?

	// nonisolated(unsafe) so deinit can read it: deinit is nonisolated, and the
	// only thing it does with the panel happens back on the main actor.
	@objc nonisolated(unsafe) var savePanel: NSSavePanel?

	@objc(initWithOptions:fileType:)
	init(options: OakEncodingOptions, fileType: String?) {
		// +initialize's job, and it has to happen before loadView(): the
		// line-endings pop-up binds through this transformer *by name*, and a
		// missing transformer is a silent no-selection rather than an error.
		OakSavePanelSupport.registerValueTransformers()

		self.encodingOptions = options
		self.fileType = fileType
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		// NSSavePanel outlives the accessory controller once the sheet is
		// dismissed, and it does not hold its delegate weakly — the pin in
		// t_save_panel.mm records that it is still set after the controller goes.
		//
		// A view controller is deallocated on the main thread, which is what makes
		// assumeIsolated correct here rather than merely convenient.
		let panel = savePanel
		MainActor.assumeIsolated {
			if panel?.delegate === self {
				panel?.delegate = nil
			}
		}
	}

	override func loadView() {
		let encodingPopUpButton    = OakEncodingPopUpButton(frame: .zero, pullsDown: false)
		let lineEndingsPopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)

		encodingPopUpButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		encodingPopUpButton.setAccessibilityLabel("Encoding")
		lineEndingsPopUpButton.setAccessibilityLabel("Line endings")

		// Tags 0/1/2, in this order: they are what OakLineEndingsTransformer maps,
		// and the titles carry no meaning to the binding.
		for (i, title) in ["LF", "CR", "CRLF"].enumerated() {
			lineEndingsPopUpButton.menu?.addItem(withTitle: title, action: nil, keyEquivalent: "").tag = i
		}

		let views: [String: Any] = [
			"encodingLabel":    OakCreateLabel("Encoding:", nil, .left, .byTruncatingMiddle) as Any,
			"encodingPopUp":    encodingPopUpButton,
			"lineEndingsPopUp": lineEndingsPopUpButton,
		]

		let containerView = NSView(frame: .zero)
		OakAddAutoLayoutViewsToSuperview(Array(views.values) as? [NSView] ?? [], containerView)

		containerView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[encodingLabel]-[encodingPopUp]-[lineEndingsPopUp]-(>=20)-|", options: .alignAllLastBaseline, metrics: nil, views: views))
		containerView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-(8)-[encodingPopUp]-(8)-|", options: .alignAllLeading, metrics: nil, views: views))

		containerView.frame = NSRect(origin: .zero, size: containerView.fittingSize)
		view = containerView

		encodingPopUpButton.bind(NSBindingName("encoding"), to: self, withKeyPath: "encoding", options: nil)
		lineEndingsPopUpButton.bind(.selectedTag, to: self, withKeyPath: "lineEndings", options: [.valueTransformerName: "OakLineEndingsTransformer"])
	}

	@objc(updateSettingsWithOptions:)
	func updateSettings(with options: OakEncodingOptions) {
		lineEndings = options.newlines
		encoding    = options.charset
	}

	@objc(resolvedOptionsForURL:)
	func resolvedOptions(for url: URL?) -> OakEncodingOptions {
		return OakSavePanelSupport.resolve(encodingOptions, for: url, fileType: fileType)
	}

	func panel(_ sender: Any, didChangeToDirectoryURL url: URL?) {
		updateSettings(with: resolvedOptions(for: (sender as? NSSavePanel)?.url))
	}
}

// @MainActor because everything it touches is: NSSavePanel, the accessory view,
// and the completion handler that runs when the sheet closes.
@objc(OakSavePanel)
@MainActor
class OakSavePanel: NSObject {
	@objc(showWithPath:directory:fowWindow:options:fileType:completionHandler:)
	class func show(path pathSuggestion: String, directory directorySuggestion: String?, fowWindow window: NSWindow, options: OakEncodingOptions, fileType: String?, completionHandler: @escaping (String?, OakEncodingOptions) -> Void) {
		let optionsViewController = OakEncodingSaveOptionsViewController(options: options, fileType: fileType)

		window.attachedSheet?.orderOut(self) // incase there already is a sheet showing (like “Do you want to save?”)

		let savePanel = NSSavePanel()
		optionsViewController.savePanel = savePanel
		savePanel.treatsFilePackagesAsDirectories = true
		if let directorySuggestion {
			savePanel.directoryURL = URL(fileURLWithPath: directorySuggestion)
		}
		savePanel.nameFieldStringValue = (pathSuggestion as NSString).lastPathComponent
		savePanel.accessoryView = optionsViewController.view
		optionsViewController.updateSettings(with: optionsViewController.resolvedOptions(for: savePanel.url))
		savePanel.delegate = optionsViewController
		savePanel.beginSheetModal(for: window) { result in
			savePanel.delegate = nil
			let path = result == .OK ? (savePanel.url as NSURL?)?.filePathURL?.path : nil
			completionHandler(path, OakEncodingOptions(newlines: optionsViewController.lineEndings, charset: optionsViewController.encoding))
		}

		// Deselect Extension
		if let textView = savePanel.firstResponder as? NSTextView {
			let extRange = (textView.textStorage?.string as NSString?)?.range(of: ".") ?? NSRange(location: NSNotFound, length: 0)
			if extRange.location != NSNotFound {
				textView.setSelectedRange(NSRange(location: 0, length: extRange.location))
			}
		}
	}
}
