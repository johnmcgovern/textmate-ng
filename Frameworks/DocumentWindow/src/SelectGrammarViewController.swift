import AppKit

// The strip that slides down over a document offering to install the bundle that
// would syntax-highlight it — "Would you like to install the “Ruby” bundle?"
// with Install / Not Now, and Never when you hold option.
//
// The first of DocumentWindow's four files to move, and the easiest: it had **no
// C++ at all**, which made it the right place to establish the framework's
// bridging header and its first tests. SelectGrammarViewController.h stays
// hand-written so nothing that imports it changed, and is deliberately absent
// from the bridging header — it declares this class. The response enum moved to
// SelectGrammarResponse.h for exactly that reason.
//
// `documentDisplayName` and `grammar` are `@objc dynamic` because `labelString`
// declares itself dependent on both. `@objc` alone would compile and the label
// would simply stop updating — the trap that has caused two defects in this
// project, and the reason t_select_grammar.mm was written before this file.

@MainActor private func OakSmallButton(_ title: String, _ action: Selector, _ target: AnyObject?, _ tag: Int) -> NSButton {
	let res = OakCreateButton(title, .rounded)!
	res.setContentCompressionResistancePriority(.required, for: .horizontal)
	res.font        = NSFont.messageFont(ofSize: NSFont.systemFontSize(for: .small))
	res.controlSize = .small
	res.action      = action
	res.target      = target
	res.tag         = tag
	return res
}

@objc(SelectGrammarViewController)
final class SelectGrammarViewController: NSViewController {

	private var didLoadViewAlready = false
	private var eventMonitor: Any?

	private var divider: NSView?
	private var label: NSTextField?
	private var installButton: NSButton?
	private var notNowButton: NSButton?
	private var neverButton: NSButton?
	private var progressIndicator: NSProgressIndicator?

	private var documentView: OakDocumentView?
	private var callback: ((SelectGrammarResponse, BundleGrammar?) -> Void)?

	@objc dynamic var documentDisplayName: String?
	@objc dynamic var grammar: BundleGrammar?

	@objc class func keyPathsForValuesAffectingLabelString() -> Set<String> {
		[ "grammar", "documentDisplayName" ]
	}

	// Three sentences, and the order of the tests matters: the grammar is checked
	// first, so a document name without a grammar falls all the way through to the
	// generic wording rather than naming the document.
	@objc var labelString: String {
		if let grammar, let documentDisplayName {
			return "Would you like to install the “\(grammar.bundle?.name ?? "")” bundle? This improves support for documents like “\(documentDisplayName)”."
		} else if let grammar {
			return "Would you like to install the “\(grammar.bundle?.name ?? "")” bundle? This improves support for this document."
		} else {
			return "Would you like to install additional support for this document?"
		}
	}

	override func loadView() {
		// Belt and braces in the ObjC++ too — NSViewController calls -loadView
		// once, but -showGrammars: reaches self.view and the guard predates it.
		if didLoadViewAlready { return }
		didLoadViewAlready = true

		let divider           = OakCreateNSBoxSeparator()!
		let label             = OakCreateLabel(labelString, nil, .left, .byTruncatingMiddle)!
		let neverButton       = OakSmallButton("Never",   #selector(didClickButton(_:)), self, SelectGrammarResponse.never.rawValue)
		let notNowButton      = OakSmallButton("Not Now", #selector(didClickButton(_:)), self, SelectGrammarResponse.notNow.rawValue)
		let installButton     = OakSmallButton("Install", #selector(didClickButton(_:)), self, SelectGrammarResponse.install.rawValue)
		let progressIndicator = NSProgressIndicator(frame: .zero)

		self.divider           = divider
		self.label             = label
		self.neverButton       = neverButton
		self.notNowButton      = notNowButton
		self.installButton     = installButton
		self.progressIndicator = progressIndicator

		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		progressIndicator.controlSize          = .small
		progressIndicator.maxValue             = 1
		progressIndicator.isIndeterminate      = true
		progressIndicator.isDisplayedWhenStopped = false
		// Deprecated since macOS 14 and ignored since 10.15, but carried over
		// rather than dropped: removing it is a behaviour question, not a port one.
		progressIndicator.isBezeled            = false

		let views: [String: NSView] = [
			"divider":  divider,
			"label":    label,
			"progress": progressIndicator,
			"never":    neverButton,
			"notNow":   notNowButton,
			"install":  installButton,
		]

		let view = NSView(frame: .zero)
		self.view = view
		OakAddAutoLayoutViewsToSuperview(Array(views.values), view)

		view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[divider]|", options: [], metrics: nil, views: views))
		view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[label]-(>=8)-[notNow(==install)]-[install]-|", options: .alignAllCenterY, metrics: nil, views: views))
		view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[label]-(>=8)-[never(==install)]-[install]-|", options: .alignAllCenterY, metrics: nil, views: views))
		view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[label]-(>=8)-[progress]-|", options: .alignAllCenterY, metrics: nil, views: views))
		view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-(8)-[label]-(8)-[divider(==1)]|", options: [], metrics: nil, views: views))
		view.addConstraint(NSLayoutConstraint(item: progressIndicator, attribute: .leading, relatedBy: .equal, toItem: notNowButton, attribute: .leading, multiplier: 1, constant: 0))

		neverButton.isHidden = true

		// Holding option swaps "Not Now" for "Never". The monitor is what makes
		// that live rather than sampled once, and it retains self until -dismiss
		// takes it down — which is why -dismiss nils it out explicitly.
		eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
			guard let self else { return event }
			let modifierFlags: NSEvent.ModifierFlags = (self.view.window?.isKeyWindow ?? false) ? event.modifierFlags.intersection([ .shift, .control, .option, .command ]) : []
			self.neverButton?.isHidden  = modifierFlags != .option
			self.notNowButton?.isHidden = modifierFlags == .option
			return event
		}
	}

	@objc(showGrammars:forView:completionHandler:)
	func showGrammars(_ grammars: [BundleGrammar], for documentView: OakDocumentView?, completionHandler callback: @escaping (SelectGrammarResponse, BundleGrammar?) -> Void) {
		self.documentView = documentView
		self.grammar      = grammars.first
		self.callback     = callback

		// A nil document view was a message to nil in the ObjC++ and stays a no-op
		// here — pinned by t_select_grammar.mm, which drives the response path
		// without one.
		documentView?.addAuxiliaryView(view, at: .maxY)
	}

	@objc(dismiss)
	func dismissStrip() {
		documentView?.removeAuxiliaryView(view)

		if let eventMonitor {
			NSEvent.removeMonitor(eventMonitor)
		}
		eventMonitor = nil // This retains ‘self’
	}

	@objc(didClickButton:)
	func didClickButton(_ sender: Any?) {
		// The three buttons share one action and are told apart by tag, so the tag
		// *is* the response. Anything without a tag answers Not Now — the reading
		// that neither installs nor suppresses the offer for good.
		let object = sender as AnyObject
		var tag = SelectGrammarResponse.notNow
		if object.responds(to: #selector(getter: NSMenuItem.tag)), let raw = object.value(forKey: "tag") as? NSNumber, let response = SelectGrammarResponse(rawValue: raw.intValue) {
			tag = response
		}

		if tag == .install, let bundle = grammar?.bundle {
			installButton?.isHidden = true
			notNowButton?.isHidden  = true
			neverButton?.isHidden   = true

			label?.stringValue = "Installing ‘\(bundle.name ?? "")’…"
			progressIndicator?.startAnimation(self)

			// `TMBundle`, not `Bundle`: Bundle.h carries NS_SWIFT_NAME(TMBundle) so the
			// class does not collide with Foundation's. BundlesPreferences.swift spells
			// it the same way.
			BundlesManager.sharedInstance.installBundles([ bundle ]) { [weak self] (_: [TMBundle]?) in
				guard let self else { return }
				self.progressIndicator?.stopAnimation(self)
				self.callback?(tag, self.grammar)
				self.dismissStrip()
			}
		} else {
			// `callback?` rather than an unconditional call: the ObjC++ would have
			// crashed on a nil block, and nothing reaches here without one, so this
			// only changes what happens in a case that was already a bug.
			callback?(tag, grammar)
			dismissStrip()
		}
	}
}
