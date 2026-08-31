import AppKit

// Ported from HOStatusBar.mm — this framework's first Swift file, and a leaf: the
// bar along the bottom of an HTML output window. C++-free, so no boundary file.
//
// **The bar has no state of its own.** Every public property reads and writes a
// subview — statusText is the text field's stringValue, progress is the progress
// indicator's doubleValue, canGoBack is the button's isEnabled. That is preserved
// here as computed properties with no backing storage: adding storage would pass
// a round-trip test and still be wrong, because the control and the property
// would drift apart. t_status_bar.mm asserts against the controls for that reason.
//
// The class's ObjC face is the hand declaration in HOStatusBar.h (rule 23).

private func OakCreateImageButton(_ image: NSImage?) -> NSButton {
	let res = NSButton()
	res.setButtonType(.momentaryChange)
	res.isBordered    = false
	res.image         = image
	res.imagePosition = .imageOnly
	return res
}

private func OakCreateTextField() -> NSTextField {
	let res = NSTextField(frame: .zero)
	res.isBordered      = false
	res.isEditable      = false
	res.isSelectable    = false
	res.isBezeled       = false
	res.drawsBackground = false
	res.font            = OakStatusBarFont()
	return res
}

@objc(HOStatusBar)
class HOStatusBar: NSVisualEffectView {
	@objc var topDivider: NSView!
	@objc var divider: NSView!
	@objc var goBackButton: NSButton!
	@objc var goForwardButton: NSButton!
	@objc var statusTextField: NSTextField!
	@objc var progressIndicator: NSProgressIndicator!
	@objc var spinner: NSProgressIndicator!

	private var layoutConstraints: [NSLayoutConstraint] = []

	@objc weak var delegate: AnyObject?

	override init(frame: NSRect) {
		super.init(frame: frame)

		wantsLayer   = true
		material     = .titlebar
		blendingMode = .withinWindow
		state        = .followsWindowActiveState

		_indeterminateProgress = true

		topDivider = OakCreateNSBoxSeparator()
		divider    = OakCreateNSBoxSeparator()

		goBackButton         = OakCreateImageButton(NSImage(named: NSImage.goLeftTemplateName))
		goBackButton.toolTip = "Show the previous page"
		goBackButton.isEnabled = false
		goBackButton.target  = self
		goBackButton.action  = #selector(goBack(_:))

		goForwardButton         = OakCreateImageButton(NSImage(named: NSImage.goRightTemplateName))
		goForwardButton.toolTip = "Show the next page"
		goForwardButton.isEnabled = false
		goForwardButton.target  = self
		goForwardButton.action  = #selector(goForward(_:))

		statusTextField = OakCreateTextField()
		statusTextField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		statusTextField.cell?.lineBreakMode = .byTruncatingMiddle

		progressIndicator = NSProgressIndicator()
		progressIndicator.controlSize          = .small
		progressIndicator.maxValue             = 1
		progressIndicator.isIndeterminate      = false
		progressIndicator.isDisplayedWhenStopped = false
		progressIndicator.isBezeled            = false

		spinner = NSProgressIndicator()
		spinner.controlSize          = .small
		spinner.style                = .spinning
		spinner.isDisplayedWhenStopped = false

		// The determinate indicator is deliberately *not* in this list: the bar opens
		// in the spinning state, and -setIndeterminateProgress: adds it when a
		// command first reports a non-zero fraction.
		let views: [NSView] = [ topDivider, divider, goBackButton, goForwardButton, statusTextField, spinner ]
		OakAddAutoLayoutViewsToSuperview(views, self)

		progressIndicator.translatesAutoresizingMaskIntoConstraints = false
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func updateConstraints() {
		removeConstraints(layoutConstraints)
		layoutConstraints = []

		super.updateConstraints()

		let views: [String: NSView] = [
			"topDivider": topDivider,
			"back":       goBackButton,
			"forward":    goForwardButton,
			"divider":    divider,
			"status":     statusTextField,
			// One key, two possible controls — whichever indicator is installed.
			"spinner":    _indeterminateProgress ? spinner : progressIndicator,
		]

		let layout = [
			"H:|[topDivider]|", "V:|[topDivider(==1)]-4-[divider(==15)]-5-|", "V:[status]-5-|",
		]

		for str in layout {
			layoutConstraints.append(contentsOf: NSLayoutConstraint.constraints(withVisualFormat: str, options: [], metrics: nil, views: views))
		}
		layoutConstraints.append(contentsOf: NSLayoutConstraint.constraints(withVisualFormat: "H:|-(3)-[back(==22)]-(2)-[forward(==back)]-(2)-[divider(==1)]", options: .alignAllCenterY, metrics: nil, views: views))

		if !_indeterminateProgress {
			layoutConstraints.append(contentsOf: NSLayoutConstraint.constraints(withVisualFormat: "H:[divider]-[status(>=100)]-[spinner(>=50,<=150)]-|", options: [], metrics: nil, views: views))
			layoutConstraints.append(contentsOf: NSLayoutConstraint.constraints(withVisualFormat: "V:[spinner]-6-|", options: [], metrics: nil, views: views))
		}
		else {
			layoutConstraints.append(contentsOf: NSLayoutConstraint.constraints(withVisualFormat: "H:[divider]-[status(>=100)]-[spinner]-|", options: [], metrics: nil, views: views))
			layoutConstraints.append(contentsOf: NSLayoutConstraint.constraints(withVisualFormat: "V:[spinner]-5-|", options: [], metrics: nil, views: views))
		}

		addConstraints(layoutConstraints)
	}

	private var _indeterminateProgress: Bool = false
	@objc var indeterminateProgress: Bool {
		get { _indeterminateProgress }
		set {
			guard _indeterminateProgress != newValue else {
				return
			}

			_indeterminateProgress = newValue
			if _indeterminateProgress {
				progressIndicator.removeFromSuperview()
				addSubview(spinner)
				if _busy {
					spinner.startAnimation(nil)
				}
			}
			else {
				addSubview(progressIndicator)
				// Note the asymmetry, kept as it was: this branch *stops* the spinner
				// rather than starting the bar, because a determinate bar shows its
				// value rather than motion.
				if _busy {
					spinner.stopAnimation(nil)
				}
				spinner.removeFromSuperview()
			}
			needsUpdateConstraints = true
		}
	}

	private var _busy: Bool = false
	// Named isBusy on the Swift side, not busy: HOJSBridgeDelegate's imported
	// requirement takes its name from the ObjC getter, and a conformance has to match
	// it. The ObjC selectors are unchanged either way.
	@objc var isBusy: Bool {
		// rule 4: the getter is spelled isBusy while the setter is setBusy:.
		@objc(isBusy) get { _busy }
		@objc(setBusy:) set {
			_busy = newValue
			// Drives the spinner only; in the determinate state the flag is recorded
			// and nothing moves.
			if _indeterminateProgress {
				if _busy {
					spinner.startAnimation(nil)
				}
				else {
					spinner.stopAnimation(nil)
				}
			}
		}
	}

	@objc func goBack(_ sender: Any?) {
		NSApp.sendAction(#selector(goBack(_:)), to: delegate, from: self)
	}

	@objc func goForward(_ sender: Any?) {
		NSApp.sendAction(#selector(goForward(_:)), to: delegate, from: self)
	}

	// Facades, all of them: the control *is* the storage.
	@objc var canGoBack: Bool {
		get { goBackButton.isEnabled }
		set { goBackButton.isEnabled = newValue }
	}

	@objc var canGoForward: Bool {
		get { goForwardButton.isEnabled }
		set { goForwardButton.isEnabled = newValue }
	}

	@objc var statusText: String? {
		get { statusTextField.stringValue }
		set { statusTextField.stringValue = newValue ?? "" }
	}

	@objc var progress: CGFloat {
		get { progressIndicator.doubleValue }
		set {
			progressIndicator.doubleValue = newValue
			// Not a plain setter: a non-zero fraction swaps the spinner for the
			// determinate bar, and zero swaps it back. This is how a command that
			// reports progress replaces the spinner.
			indeterminateProgress = newValue == 0
		}
	}
}
