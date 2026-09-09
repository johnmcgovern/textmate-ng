import AppKit

// Ported from FFStatusBarViewController.mm — the strip under Find's results list:
// a stop button, a spinner, and the status text.
//
// No hand-written header (rule 23 does not apply): the only consumer is
// Find.swift, in this same module, so the class is visible directly and
// FFStatusBarViewController.h is gone along with its line in
// Find-Bridging-Header.h, where it would now collide with the generated
// Find-Swift.h (rule 43). The tests reach it through FindTesting.h, which is
// what pins the ObjC spellings.

// The status line's two joiners. A search string spanning lines is shown on one
// line with the breaks drawn as ¬, and tabs within a line as ‣ — pinned by
// t_find_view_controllers.mm, because losing them renders a multi-line search as
// one run-together string that is legible enough for nobody to report.
//
// `std::exchange(firstLine, false)` in the original; a plain Bool here.
private func OakFormatStatusString(_ aString: String?) -> NSAttributedString {
	let paragraphStyle = NSMutableParagraphStyle()
	paragraphStyle.lineBreakMode = .byTruncatingMiddle

	let regularAttrs: [NSAttributedString.Key: Any] = [
		.foregroundColor: NSColor.labelColor,
		.paragraphStyle:  paragraphStyle,
	]

	let dimmedAttrs: [NSAttributedString.Key: Any] = [
		.foregroundColor: NSColor.tertiaryLabelColor,
		.paragraphStyle:  paragraphStyle,
	]

	let lineJoiner = NSAttributedString(string: "¬", attributes: dimmedAttrs)
	let tabJoiner  = NSAttributedString(string: "‣", attributes: dimmedAttrs)

	let res = NSMutableAttributedString(string: "", attributes: regularAttrs)

	// -enumerateLinesUsingBlock: on a nil string was a no-op and produced an empty
	// result; so does this.
	guard let aString else { return res }

	var firstLine = true
	aString.enumerateLines { line, _ in
		if !firstLine {
			res.append(lineJoiner)
		}
		firstLine = false

		var firstTab = true
		for str in line.components(separatedBy: "\t") {
			if !firstTab {
				res.append(tabJoiner)
			}
			firstTab = false
			res.append(NSAttributedString(string: str, attributes: regularAttrs))
		}
	}

	return res
}

@objc(FFStatusBarViewController)
@MainActor
class FFStatusBarViewController: NSViewController {
	private var _stopButton: NSButton?
	private var _progressIndicator: NSProgressIndicator?
	private var _statusTextButton: NSButton?

	@objc var stopAction: Selector?
	@objc var stopTarget: AnyObject?

	private var _statusText: String?
	@objc var statusText: String? {
		get { _statusText }
		set {
			_statusText = newValue
			// Both titles, deliberately: a button with no alternate set would
			// otherwise show nothing while pressed. -setAlternateStatusText: below
			// then overrides just the alternate. Messaging a nil button is a no-op
			// (rule 33) — the lazy getter formats the stored value when the view is
			// finally built, which is what makes setting this before -loadView work.
			let formatted = OakFormatStatusString(newValue)
			_statusTextButton?.attributedTitle = formatted
			_statusTextButton?.attributedAlternateTitle = formatted
		}
	}

	private var _alternateStatusText: String?
	@objc var alternateStatusText: String? {
		get { _alternateStatusText }
		set {
			_alternateStatusText = newValue
			_statusTextButton?.attributedAlternateTitle = OakFormatStatusString(newValue)
		}
	}

	private var _progressIndicatorVisible = false
	@objc var progressIndicatorVisible: Bool {
		get { _progressIndicatorVisible }
		set {
			_progressIndicatorVisible = newValue
			if newValue {
				_progressIndicator?.startAnimation(self)
			} else {
				_progressIndicator?.stopAnimation(self)
			}

			_stopButton?.isHidden        = !newValue
			_progressIndicator?.isHidden = !newValue
		}
	}

	private var stopButton: NSButton {
		if let _stopButton {
			return _stopButton
		}
		let button = NSButton(frame: .zero)

		button.setAccessibilityLabel("Stop Search")
		button.isBordered   = false
		button.setButtonType(.momentaryChange)
		button.controlSize  = .small
		button.image        = NSImage(named: NSImage.stopProgressFreestandingTemplateName)
		button.imagePosition = .imageOnly
		button.toolTip      = "Stop Search"

		button.keyEquivalent = "."
		button.keyEquivalentModifierMask = .command

		button.target = self
		button.action = #selector(didClickStopButton(_:))

		(button.cell as? NSButtonCell)?.imageScaling = .scaleProportionallyDown
		button.setContentHuggingPriority(.required, for: .horizontal)

		_stopButton = button
		return button
	}

	private var progressIndicator: NSProgressIndicator {
		if let _progressIndicator {
			return _progressIndicator
		}
		let indicator = NSProgressIndicator(frame: .zero)
		indicator.controlSize          = .small
		indicator.isDisplayedWhenStopped = false
		indicator.style                = .spinning

		_progressIndicator = indicator
		return indicator
	}

	private var statusTextButton: NSButton {
		if let _statusTextButton {
			return _statusTextButton
		}
		let button = NSButton(frame: .zero)

		button.alignment   = .left
		button.isBordered  = false
		button.setButtonType(.toggle)
		button.controlSize = .small
		button.font        = NSFont.messageFont(ofSize: NSFont.systemFontSize(for: .small))

		button.attributedTitle          = OakFormatStatusString(_statusText)
		button.attributedAlternateTitle = OakFormatStatusString(_alternateStatusText)

		button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		button.setContentHuggingPriority(.defaultHigh, for: .vertical)

		button.heightAnchor.constraint(equalToConstant: 16).isActive = true

		_statusTextButton = button
		return button
	}

	override func loadView() {
		let stackView = NSStackView(views: [
			stopButton,
			progressIndicator,
			statusTextButton,
		])
		// `{ .left = 20, .right = 20 }` in the original — top and bottom stay zero.
		stackView.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)

		stackView.setCustomSpacing(2, after: progressIndicator)
		stackView.setHuggingPriority(NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.defaultHigh.rawValue - 1), for: .vertical)

		_stopButton?.isHidden        = !_progressIndicatorVisible
		_progressIndicator?.isHidden = !_progressIndicatorVisible

		self.view = stackView
	}

	@objc func didClickStopButton(_ sender: Any?) {
		if let stopAction {
			NSApp.sendAction(stopAction, to: stopTarget, from: sender)
		}
	}
}
