// The standalone window that hosts a bundle command's HTML output when the
// command is not showing it inside a document window.
//
// Swift port of HTMLOutputWindow.mm (2026-07-29). The whole framework is Swift;
// HTMLOutputWindow.h stays hand-written as the public ObjC surface, the same
// pattern as Preferences.h — the module name equals the class name's framework,
// and consumers (AppController Commands.mm, DocumentWindowController.mm,
// OakCommand.mm) are untouched.
import AppKit

@objc(HTMLOutputWindowController)
class HTMLOutputWindowController: NSWindowController, NSWindowDelegate {
	@objc var htmlOutputView: OakHTMLOutputView

	// The window keeps itself alive between showWindow: and windowWillClose:,
	// exactly as the ObjC++ version did — nothing else retains it.
	private var retainedSelf: HTMLOutputWindowController?

	@objc override init(window: NSWindow?) {
		// Inset the main screen's visible frame by a third horizontally and a
		// fifth vertically, then snap to integral pixels.
		var rect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
		rect = NSIntegralRect(NSInsetRect(rect, NSWidth(rect) / 3, NSHeight(rect) / 5))

		let newWindow = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)

		self.htmlOutputView = OakHTMLOutputView()
		super.init(window: newWindow)

		// `mainFrameTitle` is not declared in HTMLOutput.h — it resolves through
		// KVC on OakHTMLOutputView at runtime, as it did before. Renaming it there
		// breaks the window title silently.
		newWindow.bind(NSBindingName.title, to: htmlOutputView, withKeyPath: "mainFrameTitle", options: nil)
		newWindow.bind(NSBindingName.documentEdited, to: htmlOutputView, withKeyPath: "runningCommand", options: nil)
		newWindow.contentView = htmlOutputView
		newWindow.delegate = self
		newWindow.isReleasedWhenClosed = false
		newWindow.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
	}

	@objc convenience init(identifier anIdentifier: UUID) {
		self.init(window: nil)
		window?.setFrameAutosaveName("HTML output for \(anIdentifier.uuidString)")
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func showWindow(_ sender: Any?) {
		retainedSelf = self
		super.showWindow(sender)
	}

	@objc override func cancelOperation(_ sender: Any?) {
		window?.performClose(sender)
	}

	// MARK: - NSWindowDelegate

	func windowShouldClose(_ sender: NSWindow) -> Bool {
		guard htmlOutputView.isRunningCommand else { return true }

		// A command is still running: ask, and only close if the user agreed to
		// stop it. Returning false here keeps the window until that answer.
		htmlOutputView.stopLoading(withUserInteraction: true) { [weak self] didStop in
			MainActor.assumeIsolated {
				guard didStop, let window = self?.window else { return }
				window.orderOut(self)
				window.close()
			}
		}
		return false
	}

	func windowWillClose(_ notification: Notification) {
		// Teardown that the ObjC++ version did in -dealloc. A @MainActor class
		// cannot touch its own state from deinit under Swift 6, so it happens here
		// instead — which is the same moment in practice, since releasing
		// retainedSelf is what deallocates the controller.
		window?.delegate = nil

		DispatchQueue.main.async { [self] in
			retainedSelf = nil
		}
	}
}
