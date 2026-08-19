// The recessed radio-button strip — "In: Document / Selection / Project" in the
// Find window, and the file browser's data-source picker.
//
// Nothing here is C++; it is a stack view of push-on-push-off buttons plus the
// binding plumbing that makes the selected index round-trip.
import AppKit

private func OakCreateScopeButton(_ label: String, _ tag: Int, _ action: Selector, _ target: AnyObject?, _ controlSize: NSControl.ControlSize) -> NSButton {
	let res = NSButton(frame: .zero)
	res.setAccessibilityRole(.radioButton)
	res.bezelStyle                      = .recessed
	res.setButtonType(.pushOnPushOff)
	res.controlSize                     = controlSize
	res.font                            = NSFont.messageFont(ofSize: NSFont.systemFontSize(for: controlSize))
	res.title                           = label
	res.tag                             = tag
	res.action                          = action
	res.target                          = target
	res.showsBorderOnlyWhileMouseInside = true

	return res
}

@objc(OakScopeBarViewController)
class OakScopeBarViewController: NSViewController {

	private var stackView: NSStackView!

	@objc var allowsEmptySelection: Bool = false

	@objc var labels: [String]? {
		get { _labels }
		set {
			if _labels == newValue {
				return
			}
			_labels = newValue
			updateButtons()
		}
	}
	private var _labels: [String]?

	@objc var controlSize: NSControl.ControlSize {
		get { _controlSize }
		set {
			if _controlSize == newValue {
				return
			}
			_controlSize = newValue
			updateButtons()
		}
	}
	private var _controlSize: NSControl.ControlSize = .regular

	@objc var selectedIndex: UInt {
		get { _selectedIndex }
		set {
			let notifyObservers = _selectedIndex != newValue

			_selectedIndex = newValue
			for case let button as NSButton in stackView?.arrangedSubviews ?? [] {
				button.state = UInt(button.tag) == _selectedIndex ? .on : .off
			}

			if notifyObservers {
				// Updated by hand for the same reason OakKeyEquivalentView does it: this
				// is an NSViewController, not an NSControl, so NSValueBinding does not
				// write back on its own.
				if let info = infoForBinding(NSBindingName.value) {
					let controller = info[NSBindingInfoKey.observedObject]
					let keyPath = info[NSBindingInfoKey.observedKeyPath] as? String
					if let controller = controller, !(controller is NSNull), let keyPath = keyPath {
						let newValue = NSNumber(value: _selectedIndex)
						let oldValue = (controller as AnyObject).value(forKeyPath: keyPath)
						if oldValue == nil || !((oldValue as AnyObject).isEqual(newValue)) {
							(controller as AnyObject).setValue(newValue, forKeyPath: keyPath)
						}
					}
				}
			}
		}
	}
	private var _selectedIndex: UInt = 0

	override func loadView() {
		stackView = NSStackView(frame: .zero)
		stackView.setAccessibilityRole(.radioGroup)
		updateButtons()
		view = stackView
	}

	private func updateButtons() {
		guard let stackView = stackView else { return }

		for button in stackView.arrangedSubviews {
			stackView.removeArrangedSubview(button)
		}

		switch _controlSize {
			case .regular: stackView.spacing = 4
			case .small:   stackView.spacing = 2
			case .mini:    stackView.spacing = 2
			default:       break
		}

		for (i, label) in (_labels ?? []).enumerated() {
			let button = OakCreateScopeButton(label, i, #selector(takeSelectedIndexFrom(_:)), self, _controlSize)
			button.state = UInt(i) == _selectedIndex ? .on : .off
			stackView.addArrangedSubview(button)
		}

		OakSetupKeyViewLoop([ stackView ] + stackView.arrangedSubviews)
	}

	@objc func updateGoToMenu(_ aMenu: NSMenu) {
		if view.window?.isKeyWindow == true {
			for (i, label) in (_labels ?? []).enumerated() {
				let item = aMenu.addItem(withTitle: label, action: #selector(takeSelectedIndexFrom(_:)), keyEquivalent: i < 9 ? String(UnicodeScalar(UInt8(0x31 + i))) : "")
				item.tag = i
				item.target = self
			}
		} else {
			aMenu.addItem(withTitle: "No Sources", action: Selector(("nop:")), keyEquivalent: "")
		}
	}

	@objc func selectNextButton(_ sender: Any?) {
		let count = UInt((_labels ?? []).count)
		guard count != 0 else { return }
		selectedIndex = (_selectedIndex + 1) % count
	}

	@objc func selectPreviousButton(_ sender: Any?) {
		let count = UInt((_labels ?? []).count)
		guard count != 0 else { return }
		selectedIndex = (_selectedIndex + count - 1) % count
	}

	@objc func takeSelectedIndexFrom(_ sender: Any?) {
		guard let sender = sender as AnyObject?, sender.responds(to: #selector(getter: NSMenuItem.tag)) else { return }

		var newSelectedIndex = UInt(sender.tag)
		// Clicking the already-selected button turns it off, which is a
		// *deselection* only where the caller allows one.
		if let button = sender as? NSButton, button.state == .off, allowsEmptySelection {
			newSelectedIndex = UInt(NSNotFound)
		}
		selectedIndex = newSelectedIndex
	}

	// NSValueBinding reads and writes through these.
	@objc var value: Any? {
		get { NSNumber(value: selectedIndex) }
		set { selectedIndex = UInt((newValue as? NSNumber)?.intValue ?? 0) }
	}
}

extension OakScopeBarViewController: NSMenuItemValidation {
	func validateMenuItem(_ item: NSMenuItem) -> Bool {
		if item.action == #selector(takeSelectedIndexFrom(_:)) {
			item.state = UInt(item.tag) == selectedIndex ? .on : .off
		}
		return true
	}
}
