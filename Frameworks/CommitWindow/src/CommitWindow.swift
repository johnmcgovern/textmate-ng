// The commit sheet: message editor (OakDocumentView), previous-messages popup,
// collapsible file table, diff buttons and per-file action commands. Swift port
// of the ObjC++ original; the pieces Swift cannot express live in
// CommitWindowServer.mm behind CWSupport.h — see the boundary notes there.
//
// The controller is NOT the window/text-view delegate the way the ObjC++
// version was: `variables` and `performBundleItem:` are C++-typed selectors, so
// CWInteropAdapter stands in as both delegates and forwards to us.
import AppKit

private let kOakCommitWindowShowFileList = "showFileListInCommitWindow"
private let kOakCommitWindowCommitMessages = "commitMessages"

private let kOakCommitWindowMinimumDocumentViewHeight: CGFloat = 195
private let kOakCommitWindowTableViewHeight: CGFloat = 190

@objc(OakCommitWindow) class OakCommitWindow: NSWindowController, NSTableViewDelegate, NSMenuDelegate, NSMenuItemValidation {
	private var options: [String: String]
	private var actions: [CWCommitLogic.ActionSpec]
	private var parameters: [String]
	private var environment: [String: String]
	private var clientPortName: String?

	private let arrayController = NSArrayController()
	private let interopAdapter = CWInteropAdapter()

	private var previousCommitMessagesPopUpButton = NSPopUpButton()
	private var documentView: OakDocumentView
	private var documentViewHeightConstraint: NSLayoutConstraint?
	private var scrollView: NSScrollView?
	private var scrollViewHeightConstraint: NSLayoutConstraint?
	private var tableView: NSTableView?

	private var topDocumentViewDivider: NSView
	private var bottomDocumentViewDivider: NSView
	private var topScrollViewDivider: NSView?
	private var bottomScrollViewDivider: NSView?

	private var showTableButton: NSButton
	private var actionPopUpButton: NSPopUpButton?
	private var commitButton: NSButton
	private var cancelButton: NSButton

	private var commitButtonPrefix: String
	private var filesToCommitCount = 0
	private var showContinueSuffix: Bool

	private var showsTableView: Bool
	private var scrollViewConstraints: [NSLayoutConstraint] = []
	private var bottomButtonsConstraints: [NSLayoutConstraint] = []

	private var retainedSelf: OakCommitWindow?
	private var windowWillCloseObserver: (any NSObjectProtocol)?
	private var eventMonitor: Any?
	private var didTearDown = false

	private nonisolated(unsafe) static var includeItemObserverContext = 0

	@objc init(options someOptions: [String: Any]) {
		let parsed = CWCommitLogic.parse(arguments: someOptions[kOakCommitWindowArguments] as? [String] ?? [])
		self.options = parsed.options
		self.actions = parsed.actions
		self.parameters = parsed.parameters
		self.commitButtonPrefix = parsed.commitButtonPrefix
		self.showContinueSuffix = parsed.showContinueButton

		self.clientPortName = someOptions[kOakCommitWindowClientPortName] as? String

		var environment = someOptions[kOakCommitWindowEnvironment] as? [String: String] ?? [:]
		// send all diffs to a separate window
		environment["TM_PROJECT_UUID"] = UUID().uuidString
		self.environment = environment

		self.showsTableView = UserDefaults.standard.bool(forKey: kOakCommitWindowShowFileList)

		self.documentView = OakDocumentView(frame: .zero)
		self.topDocumentViewDivider = OakCreateNSBoxSeparator()
		self.bottomDocumentViewDivider = OakCreateNSBoxSeparator()
		self.commitButton = OakCreateButton("Commit", .rounded)
		self.cancelButton = OakCreateButton("Cancel", .rounded)
		self.showTableButton = NSButton(frame: .zero)

		super.init(window: nil)

		// The ObjC++ version sent a failure reply (via cancel:) when the
		// arguments were malformed, then carried on; preserve that.
		if parsed.shouldCancel {
			sendCommitMessageToClient(false)
		}

		documentView.hideStatusBar = true
		documentView.textView.delegate = interopAdapter

		interopAdapter.projectDirectory = environment["TM_PROJECT_DIRECTORY"]
		interopAdapter.documentView = documentView
		interopAdapter.windowController = self

		setupArrayController()

		CWStatusStringTransformer.register()

		let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 350), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
		window.delegate = interopAdapter
		window.setFrameAutosaveName("Commit Window")
		self.window = window

		commitButton.title = commitButtonTitle
		commitButton.action = #selector(performCommit(_:))
		commitButton.keyEquivalent = "\r"
		commitButton.keyEquivalentModifierMask = .command
		commitButton.target = self

		cancelButton.action = #selector(cancel(_:))
		cancelButton.keyEquivalent = "."
		cancelButton.keyEquivalentModifierMask = .command
		cancelButton.target = self

		showTableButton.setButtonType(.onOff)
		showTableButton.bezelStyle = .roundedDisclosure
		showTableButton.title = ""
		showTableButton.action = #selector(toggleTableView(_:))
		showTableButton.state = showsTableView ? .on : .off

		previousCommitMessagesPopUpButton.isBordered = true
		previousCommitMessagesPopUpButton.pullsDown = true
		previousCommitMessagesPopUpButton.bezelStyle = .texturedRounded
		setupPreviousCommitMessagesMenu()

		let contentView = window.contentView!
		OakAddAutoLayoutViewsToSuperview(Array(allViews.values), contentView)

		let views = allViews
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:[previousMessages(>=200)]-(20)-|", options: [], metrics: nil, views: views))
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[documentView(>=400,==topDocumentViewDivider,==bottomDocumentViewDivider)]|", options: .alignAllLeading, metrics: nil, views: views))
		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(20)-[showTableButton]", options: [], metrics: nil, views: views))

		contentView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-(12)-[previousMessages]-(12)-[topDocumentViewDivider(==1)][documentView][bottomDocumentViewDivider(==1)]-(12)-[showTableButton]", options: [], metrics: nil, views: views))

		if showsTableView {
			showTableView(animated: false)
		} else {
			let constraint = NSLayoutConstraint(item: documentView, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: kOakCommitWindowMinimumDocumentViewHeight)
			contentView.addConstraint(constraint)
			documentViewHeightConstraint = constraint
			setupBottomButtonsConstraints()
		}

		arrayController.addObserver(self, forKeyPath: "arrangedObjects.commit", options: [.initial, .new], context: &Self.includeItemObserverContext)

		if showContinueSuffix {
			// local event monitors always fire on the main thread; assumeIsolated
			// bridges that guarantee into the type system (NSEvent itself is not
			// Sendable, so the isolated region computes and the event passes through)
			eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
				let hasOption = event.modifierFlags.contains(.option)
				MainActor.assumeIsolated {
					self?.updateCommitButtonForFlags(hasOption: hasOption)
				}
				return event
			}
		}
	}

	private func updateCommitButtonForFlags(hasOption: Bool) {
		guard window?.isKeyWindow == true else { return }

		if hasOption {
			commitButton.keyEquivalentModifierMask.insert(.option)
			commitButton.action = #selector(performCommit(_:))
			showContinueSuffix = false
		} else {
			commitButton.keyEquivalentModifierMask.remove(.option)
			commitButton.action = #selector(performCommitAndContinue(_:))
			showContinueSuffix = true
		}
		commitButton.title = commitButtonTitle
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported — OakCommitWindow is created from server options")
	}

	// The ObjC++ version did this in dealloc; a @MainActor class cannot touch
	// its state from deinit under Swift 6, so teardown runs when the retained
	// self-reference is released (the end of the window's life either way).
	private func teardown() {
		guard !didTearDown else { return }
		didTearDown = true

		arrayController.removeObserver(self, forKeyPath: "arrangedObjects.commit", context: &Self.includeItemObserverContext)
		if let eventMonitor {
			NSEvent.removeMonitor(eventMonitor)
			self.eventMonitor = nil
		}
		if let windowWillCloseObserver {
			NotificationCenter.default.removeObserver(windowWillCloseObserver)
			self.windowWillCloseObserver = nil
		}
	}

	private var commitButtonTitle: String {
		CWCommitLogic.commitButtonTitle(prefix: commitButtonPrefix, count: filesToCommitCount, showsContinue: showContinueSuffix)
	}

	private var allViews: [String: NSView] {
		var views: [String: NSView] = [
			"previousMessages":          previousCommitMessagesPopUpButton,
			"topDocumentViewDivider":    topDocumentViewDivider,
			"documentView":              documentView,
			"bottomDocumentViewDivider": bottomDocumentViewDivider,
			"showTableButton":           showTableButton,
			"cancel":                    cancelButton,
			"commit":                    commitButton,
		]
		views["topScrollViewDivider"] = topScrollViewDivider
		views["scrollView"] = scrollView
		views["bottomScrollViewDivider"] = bottomScrollViewDivider
		views["action"] = actionPopUpButton
		return views
	}

	private func setupBottomButtonsConstraints() {
		guard let contentView = window?.contentView else { return }

		contentView.removeConstraints(bottomButtonsConstraints)

		var constraints: [NSLayoutConstraint] = []
		let views = allViews

		constraints.append(NSLayoutConstraint(item: cancelButton, attribute: .bottom, relatedBy: .equal, toItem: contentView, attribute: .bottom, multiplier: 1, constant: -12))

		if let bottomScrollViewDivider {
			constraints += NSLayoutConstraint.constraints(withVisualFormat: "H:[cancel]-[commit]-(20)-|", options: .alignAllLastBaseline, metrics: nil, views: views)
			constraints += NSLayoutConstraint.constraints(withVisualFormat: "V:[bottomDocumentViewDivider]-(12)-[showTableButton]-(12)-[topScrollViewDivider]", options: [], metrics: nil, views: views)
			constraints += NSLayoutConstraint.constraints(withVisualFormat: "V:[bottomScrollViewDivider]-(12)-[action]", options: [], metrics: nil, views: views)
			constraints += NSLayoutConstraint.constraints(withVisualFormat: "H:|-(20)-[action]", options: [], metrics: nil, views: views)
			constraints.append(NSLayoutConstraint(item: commitButton, attribute: .top, relatedBy: .equal, toItem: bottomScrollViewDivider, attribute: .bottom, multiplier: 1, constant: 12))
		} else {
			constraints += NSLayoutConstraint.constraints(withVisualFormat: "H:|-(20)-[showTableButton]-(>=100)-[cancel]-[commit]-(20)-|", options: .alignAllLastBaseline, metrics: nil, views: views)
			constraints += NSLayoutConstraint.constraints(withVisualFormat: "V:[bottomDocumentViewDivider]-(12)-[showTableButton]", options: [], metrics: nil, views: views)
			constraints.append(NSLayoutConstraint(item: commitButton, attribute: .top, relatedBy: .equal, toItem: bottomDocumentViewDivider, attribute: .top, multiplier: 1, constant: 12))
		}

		bottomButtonsConstraints = constraints
		contentView.addConstraints(constraints)
	}

	private func tearDownTableView() {
		guard let contentView = window?.contentView else { return }

		window?.makeFirstResponder(documentView.textView)

		contentView.removeConstraints(scrollViewConstraints)
		if let scrollViewHeightConstraint {
			contentView.removeConstraint(scrollViewHeightConstraint)
		}
		scrollViewConstraints = []
		scrollViewHeightConstraint = nil

		for view in [topScrollViewDivider, scrollView, bottomScrollViewDivider, actionPopUpButton].compactMap({ $0 }) {
			view.removeFromSuperview()
		}

		tableView?.unbind(.content)
		tableView?.delegate = nil
		tableView?.menu?.delegate = nil
		tableView?.target = nil
		tableView = nil

		topScrollViewDivider = nil
		scrollView = nil
		bottomScrollViewDivider = nil

		actionPopUpButton?.menu?.delegate = nil
		actionPopUpButton = nil

		setupBottomButtonsConstraints()
		window?.displayIfNeeded()
		if let documentViewHeightConstraint {
			contentView.removeConstraint(documentViewHeightConstraint)
		}
		let constraint = NSLayoutConstraint(item: documentView, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: kOakCommitWindowMinimumDocumentViewHeight)
		contentView.addConstraint(constraint)
		documentViewHeightConstraint = constraint
	}

	private func showTableView(animated: Bool) {
		guard let contentView = window?.contentView else { return }

		let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
		tableColumn.isEditable = false

		let tableView = NSTableView(frame: .zero)
		tableView.addTableColumn(tableColumn)
		tableView.headerView = nil
		tableView.focusRingType = .none
		tableView.usesAlternatingRowBackgroundColors = true
		tableView.doubleAction = #selector(didDoubleClickTableView(_:))
		tableView.target = self
		tableView.delegate = self
		tableView.menu = NSMenu()
		tableView.menu?.delegate = self
		self.tableView = tableView
		tableView.bind(.content, to: arrayController, withKeyPath: "arrangedObjects", options: nil)

		let scrollView = NSScrollView(frame: .zero)
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers = true
		scrollView.borderType = .noBorder
		scrollView.documentView = tableView
		self.scrollView = scrollView

		topScrollViewDivider = OakCreateNSBoxSeparator()
		bottomScrollViewDivider = OakCreateNSBoxSeparator()

		let actionPopUpButton: NSPopUpButton = OakCreateActionPopUpButton(true)
		actionPopUpButton.bezelStyle = .texturedRounded
		actionPopUpButton.menu?.delegate = self
		self.actionPopUpButton = actionPopUpButton

		OakAddAutoLayoutViewsToSuperview([topScrollViewDivider!, scrollView, bottomScrollViewDivider!, actionPopUpButton], contentView)

		let views = allViews
		var constraints: [NSLayoutConstraint] = []
		constraints += NSLayoutConstraint.constraints(withVisualFormat: "V:[showTableButton]-(12)-[topScrollViewDivider(==1)][scrollView][bottomScrollViewDivider(==1)]", options: [], metrics: nil, views: views)
		constraints += NSLayoutConstraint.constraints(withVisualFormat: "H:|[scrollView(==topScrollViewDivider,==bottomScrollViewDivider)]|", options: .alignAllLeading, metrics: nil, views: views)

		scrollViewConstraints = constraints
		let heightConstraint = NSLayoutConstraint(item: scrollView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
		scrollViewHeightConstraint = heightConstraint
		contentView.addConstraints(constraints)
		contentView.addConstraint(heightConstraint)

		setupBottomButtonsConstraints()

		if let documentViewHeightConstraint {
			contentView.removeConstraint(documentViewHeightConstraint)
		}
		if animated {
			NSAnimationContext.runAnimationGroup({ context in
				context.duration = 0.25
				showTableButton.isEnabled = false
				let constraint = NSLayoutConstraint(item: documentView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: documentView.frame.height)
				contentView.addConstraint(constraint)
				documentViewHeightConstraint = constraint
				heightConstraint.animator().constant = kOakCommitWindowTableViewHeight
			}, completionHandler: {
				MainActor.assumeIsolated {
					self.window?.displayIfNeeded()
					if let documentViewHeightConstraint = self.documentViewHeightConstraint {
						contentView.removeConstraint(documentViewHeightConstraint)
					}
					let constraint = NSLayoutConstraint(item: self.documentView, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: kOakCommitWindowMinimumDocumentViewHeight)
					contentView.addConstraint(constraint)
					self.documentViewHeightConstraint = constraint
					self.showTableButton.isEnabled = true
				}
			})
		} else {
			let constraint = NSLayoutConstraint(item: documentView, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: kOakCommitWindowMinimumDocumentViewHeight)
			contentView.addConstraint(constraint)
			documentViewHeightConstraint = constraint
			heightConstraint.constant = kOakCommitWindowTableViewHeight
		}
	}

	private func hideTableView(animated: Bool) {
		guard let contentView = window?.contentView else { return }

		if let documentViewHeightConstraint {
			contentView.removeConstraint(documentViewHeightConstraint)
		}
		let constraint = NSLayoutConstraint(item: documentView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: documentView.frame.height)
		contentView.addConstraint(constraint)
		documentViewHeightConstraint = constraint

		if animated {
			NSAnimationContext.runAnimationGroup({ context in
				context.duration = 0.25
				showTableButton.isEnabled = false
				actionPopUpButton?.isHidden = true
				scrollViewHeightConstraint?.animator().constant = 0
			}, completionHandler: {
				MainActor.assumeIsolated {
					self.tearDownTableView()
					self.showTableButton.isEnabled = true
				}
			})
		} else {
			tearDownTableView()
		}
	}

	private func setupArrayController() {
		arrayController.objectClass = CWItem.self

		let didSelectFiles = environment["TM_SELECTED_FILES"] != nil

		let statuses = options["--status"]?.components(separatedBy: ":") ?? []
		for (status, path) in zip(statuses, parameters) {
			let include = !(status.hasPrefix("X") || (status.hasPrefix("?") && !didSelectFiles))
			arrayController.addObject(CWItem(path: path, scmStatus: status, commit: include))
		}
	}

	override nonisolated func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		if context == &Self.includeItemObserverContext {
			MainActor.assumeIsolated {
				let items = arrayController.arrangedObjects as? [CWItem] ?? []
				filesToCommitCount = items.filter(\.commit).count
				commitButton.title = commitButtonTitle
			}
		} else {
			super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
		}
	}

	@objc private func toggleTableView(_ sender: Any?) {
		setShowsTableView(!showsTableView)

		if showsTableView {
			showTableView(animated: true)
		} else {
			hideTableView(animated: true)
		}
	}

	private func setShowsTableView(_ flag: Bool) {
		guard showsTableView != flag else { return }
		showsTableView = flag
		UserDefaults.standard.set(flag, forKey: kOakCommitWindowShowFileList)
	}

	// Presents the commit window, as a sheet when there is a window to attach to
	// and standalone otherwise.
	//
	// `parentWindow` used to be non-optional and was passed `NSApp.mainWindow`,
	// which is nil whenever the app is merely *inactive* — the normal state when
	// a commit is started from a terminal. `[nil beginSheet:…]` is a silent
	// no-op, so nothing appeared and CommitWindowTool blocked forever on a reply
	// that could never come. Reproduced 2026-07-29: with TextMate inactive the
	// tool hung indefinitely and the parent window reported 0 sheets; with
	// TextMate active the same call presented normally.
	@objc(presentAttachedToWindow:)
	func present(attachedTo parentWindow: NSWindow?) {
		let fileType = CWCommitMessageGrammarForSCMName(environment["TM_SCM_NAME"])

		let message = options["--log"] ?? ""
		let commitMessage = OakDocument(string: message, fileType: fileType, customName: "Commit Message")
		commitMessage?.virtualPath = ((environment["TM_PROJECT_DIRECTORY"] ?? "") as NSString).appendingPathComponent("commit-message.txt")
		documentView.document = commitMessage

		window?.recalculateKeyViewLoop()
		window?.makeFirstResponder(documentView)

		retainedSelf = self

		// Last-resort guarantee that the client is never left waiting: however
		// this window goes away, a reply goes out. sendCommitMessageToClient is
		// idempotent — it returns early once clientPortName has been cleared — so
		// the normal Commit/Cancel paths are unaffected.
		if let window {
			windowWillCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
				MainActor.assumeIsolated { self?.sendCommitMessageToClient(false) }
			}
		}

		// The user is being asked for a commit message while a command-line tool
		// blocks on the answer, so bring the app forward. Without this the window
		// opens behind whatever is frontmost and the terminal just looks wedged —
		// which is the same user-visible symptom as the hang being fixed here.
		NSApp.activate(ignoringOtherApps: true)

		if let parentWindow, parentWindow.isVisible {
			parentWindow.beginSheet(window!) { _ in }
		} else {
			window?.center()
			window?.makeKeyAndOrderFront(nil)
		}
	}

	/// Dismisses the window however it was presented: ending the sheet when it is
	/// one, closing it when it is standalone. The old code only ever called
	/// `sheetParent?.endSheet`, which is a no-op for a standalone window and would
	/// leave it on screen after a commit.
	private func dismiss() {
		guard let window else { return }
		if let sheetParent = window.sheetParent {
			sheetParent.endSheet(window)
		} else {
			window.close()
		}
	}

	private func sendCommitMessageToClient(_ success: Bool, andContinue continueFlag: Bool = false) {
		guard let clientPortName else { return } // reply already sent

		var stdoutString: String? = nil
		if success {
			let message = documentView.document?.content ?? ""
			let escapedPaths = (arrayController.arrangedObjects as? [CWItem] ?? [])
				.filter(\.commit)
				.map { CWEscapedShellPath($0.path) }
			stdoutString = CWCommitLogic.commitOutput(message: message, escapedPaths: escapedPaths)
		}

		if CWClientChannel.reply(toClientPortName: clientPortName, stdoutString: stdoutString, returnCode: success ? 0 : 1, continueFlag: continueFlag) {
			saveCommitMessage()
			self.clientPortName = nil
		}

		DispatchQueue.main.async {
			self.teardown()
			self.retainedSelf = nil
		}
	}

	private func chooseAllItems(_ state: Bool) {
		for item in arrayController.arrangedObjects as? [CWItem] ?? [] {
			item.commit = state
		}
	}

	private func saveCommitMessage() {
		let message = documentView.document?.content ?? ""
		let defaults = UserDefaults.standard
		if let messages = CWCommitLogic.updatedMessageHistory(defaults.stringArray(forKey: kOakCommitWindowCommitMessages), adding: message) {
			defaults.set(messages, forKey: kOakCommitWindowCommitMessages)
			defaults.synchronize()
		}
	}

	private func setupPreviousCommitMessagesMenu() {
		guard let menu = previousCommitMessagesPopUpButton.menu else { return }
		menu.removeAllItems()
		menu.addItem(withTitle: "Previous Commit Messages", action: nil, keyEquivalent: "")

		if let commitMessages = UserDefaults.standard.stringArray(forKey: kOakCommitWindowCommitMessages) {
			for message in commitMessages.reversed() {
				let item = menu.addItem(withTitle: CWCommitLogic.menuTitle(forMessage: message), action: #selector(restorePreviousCommitMessage(_:)), keyEquivalent: "")
				item.toolTip = message
				item.target = self
				item.representedObject = message
			}

			menu.addItem(.separator())
			let item = menu.addItem(withTitle: "Clear Menu", action: #selector(clearPreviousCommitMessages(_:)), keyEquivalent: "")
			item.target = self
		} else {
			previousCommitMessagesPopUpButton.isEnabled = false
		}
	}

	@objc private func restorePreviousCommitMessage(_ sender: NSMenuItem) {
		guard let message = sender.representedObject as? String else { return }
		let commitMessage = OakDocument(string: message, fileType: documentView.document?.fileType, customName: "Commit Message")
		commitMessage?.virtualPath = ((environment["TM_PROJECT_DIRECTORY"] ?? "") as NSString).appendingPathComponent("commit-message.txt")
		documentView.document = commitMessage
	}

	@objc private func clearPreviousCommitMessages(_ sender: Any?) {
		UserDefaults.standard.removeObject(forKey: kOakCommitWindowCommitMessages)
		setupPreviousCommitMessagesMenu()
	}

	// ==================
	// = Action Methods =
	// ==================

	@objc private func didDoubleClickTableView(_ sender: Any?) {
		guard let tableView else { return }

		let senderRow = (sender as? NSView).map { tableView.row(for: $0) } ?? -1
		if tableView.clickedRow == -1 && senderRow == -1 {
			return
		}

		guard let diffCommand = options["--diff-cmd"] else { return }

		var diffCmd = diffCommand.components(separatedBy: ",")
		diffCmd[0] = CWCommitLogic.absolutePath(forTool: diffCmd[0], environment: environment)

		let row = senderRow == -1 ? tableView.clickedRow : senderRow
		guard let item = (arrayController.arrangedObjects as? [CWItem])?[safe: row] else { return }
		diffCmd.append(item.path)

		let escaped = diffCmd.map { CWEscapedShellPath($0) }
		let cmdString = "cd \"${TM_PROJECT_DIRECTORY}\" && \(escaped.joined(separator: " "))|\"$TM_MATE\" --no-wait --name \"---/+++ \(CWDisplayNameForPath(item.path))\""

		let environment = self.environment
		Task { [weak self] in
			let success = await Task.detached { CWRunShellCommand(environment, cmdString) != nil }.value
			if !success, let self {
				let alert = NSAlert()
				alert.messageText = "Failed running diff command."
				alert.informativeText = cmdString
				alert.addButton(withTitle: "OK")
				alert.beginSheetModal(for: self.window!) { _ in }
			}
		}
	}

	@objc private func performCommit(_ sender: Any?) {
		sendCommitMessageToClient(true)
		dismiss()
	}

	@objc private func performCommitAndContinue(_ sender: Any?) {
		sendCommitMessageToClient(true, andContinue: true)
		dismiss()
	}

	@objc func cancel(_ sender: Any?) {
		sendCommitMessageToClient(false)
		dismiss()
	}

	@objc private func checkAll(_ sender: Any?) {
		chooseAllItems(true)
	}

	@objc private func uncheckAll(_ sender: Any?) {
		chooseAllItems(false)
	}

	@objc private func performActionCommand(_ sender: NSMenuItem) {
		guard let tableView, let spec = sender.representedObject as? CWCommitLogic.ActionSpec else { return }

		var command = spec.command
		guard !command.isEmpty else { return }
		command[0] = CWCommitLogic.absolutePath(forTool: command[0], environment: environment)

		let row = tableView.clickedColumn == -1 ? tableView.selectedRow : tableView.clickedRow
		guard let item = (arrayController.arrangedObjects as? [CWItem])?[safe: row] else { return }
		command.append(item.path)

		let escaped = command.map { CWEscapedShellPath($0) }
		let cmdString = "cd \"${TM_PROJECT_DIRECTORY}\" && " + escaped.joined(separator: " ")

		if let output = CWRunShellCommand(environment, cmdString) {
			guard let statusEnd = output.rangeOfCharacter(from: .whitespacesAndNewlines) else {
				let alert = NSAlert()
				alert.messageText = "Cannot understand output from command"
				alert.informativeText = cmdString
				alert.addButton(withTitle: "OK")
				alert.beginSheetModal(for: window!) { _ in }
				return
			}
			item.scmStatus = String(output[output.startIndex ..< statusEnd.lowerBound])
			item.commit = false
		} else {
			let alert = NSAlert()
			alert.messageText = "Failed running command"
			alert.informativeText = cmdString
			alert.addButton(withTitle: "OK")
			alert.beginSheetModal(for: window!) { _ in }
		}
	}

	// ===============
	// = Action menu =
	// ===============

	func menuNeedsUpdate(_ menu: NSMenu) {
		guard let tableView else { return }

		menu.removeAllItems()
		if tableView.clickedColumn == -1 {
			menu.addItem(withTitle: "Dummy", action: nil, keyEquivalent: "")
		}

		let row = tableView.clickedRow
		if row == -1 && tableView.selectedRow == -1 {
			menu.addItem(withTitle: "Check All", action: #selector(checkAll(_:)), keyEquivalent: "")
			menu.addItem(withTitle: "Uncheck All", action: #selector(uncheckAll(_:)), keyEquivalent: "")
		} else {
			if !actions.isEmpty {
				for spec in actions {
					let item = NSMenuItem(title: spec.name, action: #selector(performActionCommand(_:)), keyEquivalent: "")
					item.representedObject = spec
					menu.addItem(item)
				}
				menu.addItem(.separator())
			}
			menu.addItem(withTitle: "Check All", action: #selector(checkAll(_:)), keyEquivalent: "")
			menu.addItem(withTitle: "Uncheck All", action: #selector(uncheckAll(_:)), keyEquivalent: "")
		}
	}

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let tableView else { return true }

		var active = true
		let row = tableView.clickedColumn == -1 || tableView.clickedRow == -1 ? tableView.selectedRow : tableView.clickedRow
		if menuItem.action == #selector(performActionCommand(_:)) {
			guard row != -1, let item = (arrayController.arrangedObjects as? [CWItem])?[safe: row],
			      let spec = menuItem.representedObject as? CWCommitLogic.ActionSpec
			else { return false }

			active = spec.targetStatuses.contains(item.scmStatus)
			let variables = active ? ["TM_DISPLAYNAME": CWDisplayNameForPath(item.path)] : [:]
			menuItem.title = CWExpandFormatString(spec.name, variables)
		}
		return active
	}

	// ========================
	// = NSTableView Delegate =
	// ========================

	func tableView(_ aTableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard let tableColumn else { return nil }

		let cellView = aTableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? CWTableCellView ?? {
			let view = CWTableCellView()
			view.identifier = tableColumn.identifier
			return view
		}()

		cellView.diffButton.action = #selector(didDoubleClickTableView(_:))
		cellView.diffButton.target = self
		if options["--diff-cmd"] == nil {
			cellView.diffButton.isHidden = true
		}

		return cellView
	}
}

private extension Array {
	subscript(safe index: Int) -> Element? {
		indices.contains(index) ? self[index] : nil
	}
}
