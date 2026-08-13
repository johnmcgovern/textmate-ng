// The key-equivalent recorder: click it, press a chord, and it stores the event
// string TextMate uses for bundle-item key equivalents. Shown in Bundle Editor's
// properties pane and in BundleItemChooser.
//
// Pinned by t_key_equivalent_view.mm (9 tests), written against the ObjC++ and
// unchanged by this port. Note the comment there about -setRecording:YES: the
// tests deliberately avoid it because it disables the system's hot keys for the
// duration, which would outlive a failing test.
//
// The four C++ touchpoints are in OakAppKitSupport: two glyph conversions, the
// event-to-string conversion, and the symbolic-hot-key-mode pair. Nothing else
// here needed anything.
import AppKit

private let kRecordingPlaceholderString = "…"

@objc(OakKeyEquivalentView)
final class OakKeyEquivalentView: OakView {

	private var clearButton: OakRolloverButton?
	private var eventMonitor: Any?
	private var hotkeyToken: UnsafeMutableRawPointer?

	@objc var disableGlobalHotkeys: Bool = false

	@objc var eventString: String? {
		get { _eventString }
		set {
			if _eventString == newValue {
				return
			}

			_eventString = newValue

			showClearButton = OakNotEmptyString(eventString) && !recording
			displayString = recording ? kRecordingPlaceholderString : OakGlyphsForEventString(_eventString)

			// The binding is updated by hand because this view is not an NSControl,
			// so NSValueBinding does not round-trip on its own.
			if let info = infoForBinding(NSBindingName.value) {
				let controller = info[NSBindingInfoKey.observedObject]
				let keyPath = info[NSBindingInfoKey.observedKeyPath] as? String
				if let controller = controller, !(controller is NSNull), let keyPath = keyPath {
					let oldValue = (controller as AnyObject).value(forKeyPath: keyPath)
					if oldValue == nil || !((oldValue as AnyObject).isEqual(_eventString)) {
						(controller as AnyObject).setValue(_eventString, forKeyPath: keyPath)
					}
				}
			}
			NSAccessibility.post(element: self, notification: .valueChanged)
		}
	}
	private var _eventString: String?

	private var displayString: String? {
		get { _displayString }
		set {
			if _displayString == newValue {
				return
			}
			_displayString = newValue
			needsDisplay = true
		}
	}
	private var _displayString: String?

	private var showClearButton: Bool {
		get { _showClearButton }
		set {
			if _showClearButton == newValue {
				return
			}

			_showClearButton = newValue
			if newValue {
				if clearButton == nil {
					// The C++ default argument on OakCreateCloseButton is not visible to
					// Swift, so the label is spelled out — it is the one the ObjC++ passed.
					guard let button = OakCreateCloseButton("Remove key equivalent") else { return }
					button.refusesFirstResponder = true
					button.disableWindowOrderingForFirstMouse = true
					button.target = self
					button.action = #selector(clearKeyEquivalent(_:))

					button.translatesAutoresizingMaskIntoConstraints = false
					addSubview(button)

					button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4).isActive = true
					button.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
					clearButton = button
				}
				clearButton?.isHidden = false
				clearButton?.updateTrackingAreas()
			} else {
				clearButton?.isHidden = true
			}
		}
	}
	private var _showClearButton: Bool = false

	@objc var recording: Bool {
		get { _recording }
		set {
			if _recording == newValue {
				return
			}

			_recording = newValue
			showClearButton = OakNotEmptyString(eventString) && !recording
			displayString = _recording ? kRecordingPlaceholderString : OakGlyphsForEventString(eventString)

			if recording {
				if disableGlobalHotkeys {
					hotkeyToken = OakPushSymbolicHotKeyModeAllDisabled()
				}

				eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [ .flagsChanged, .keyDown ]) { [self] event in
					if event.type == .flagsChanged {
						let str = OakGlyphsForModifierFlags(event.modifierFlags.rawValue)
						displayString = (str?.isEmpty ?? true) ? kRecordingPlaceholderString : str
					} else if event.type == .keyDown {
						eventString = OakEventString(event)
						recording = false
					}
					return nil
				}
			} else {
				if let eventMonitor = eventMonitor {
					NSEvent.removeMonitor(eventMonitor)
				}
				eventMonitor = nil

				if disableGlobalHotkeys {
					OakPopSymbolicHotKeyMode(hotkeyToken)
					hotkeyToken = nil
				}
			}
		}
	}
	private var _recording: Bool = false

	override init(frame aRect: NSRect) {
		super.init(frame: aRect)
		disableGlobalHotkeys = true
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override var intrinsicContentSize: NSSize {
		return NSSize(width: NSView.noIntrinsicMetric, height: 22)
	}

	override var baselineOffsetFromBottom: CGFloat {
		return 5
	}

	// NSValueBinding reads and writes through these rather than -eventString.
	@objc var value: Any? {
		get { eventString }
		set { eventString = newValue as? String }
	}

	@objc override var keyState: UInt {
		get { super.keyState }
		set {
			super.keyState = newValue

			let responderMask: UInt = OakViewViewIsFirstResponderMask | OakViewWindowIsKeyMask
			let doesHaveResponder = (newValue & responderMask) == responderMask
			if !doesHaveResponder {
				recording = false
			}

			let focusMask: UInt = OakViewViewIsFirstResponderMask | OakViewWindowIsKeyMask | OakViewApplicationIsActiveMask
			let doesHaveFocus = (newValue & focusMask) == focusMask
			if !doesHaveFocus && recording {
				displayString = kRecordingPlaceholderString // reset potential display string from flagsChanged:
			}
		}
	}

	@objc func clearKeyEquivalent(_ sender: Any?) {
		eventString = nil
	}

	override var isOpaque: Bool { true }

	override func acceptsFirstMouse(for anEvent: NSEvent?) -> Bool { true }

	override var acceptsFirstResponder: Bool { true }

	override func mouseDown(with anEvent: NSEvent) {
		if window?.isKeyWindow == true {
			if self != window?.firstResponder as? OakKeyEquivalentView {
				window?.makeFirstResponder(self)
			}
			recording = true
		}
	}

	override func keyDown(with anEvent: NSEvent) {
		// std::set<std::string> in the ObjC++, built with utf8::to_s from the two
		// delete constants. The scalars are the same; the escape is "\e".
		let clearKeys: Set<String> = [
			String(UnicodeScalar(UInt8(NSDeleteCharacter))),
			String(UnicodeScalar(NSDeleteFunctionKey)!),
			"\u{1b}",
		]
		let recordingKeys: Set<String> = [ " " ]

		let keyString = OakEventString(anEvent) ?? ""
		if clearKeys.contains(keyString) && !OakIsEmptyString(eventString) {
			clearKeyEquivalent(self)
		} else if recordingKeys.contains(keyString) {
			recording = true
		} else {
			super.keyDown(with: anEvent)
		}
	}

	override func draw(_ aRect: NSRect) {
		let frame = bounds

		var frameColor = NSColor.lightGray
		// Carried over verbatim, including the shape: `backgroundColor` is assigned
		// twice and the first assignment is dead, because the second is outside the
		// `if`. Behaviour is "always controlColor"; the ObjC++ reads as though dark
		// mode were meant to differ and it does not.
		var backgroundColor = NSColor.white

		if NSApp.effectiveAppearance.bestMatch(from: [ .aqua, .darkAqua ]) == .darkAqua {
			frameColor = NSColor.tertiaryLabelColor
		}
		backgroundColor = NSColor.controlColor

		frameColor.set()
		frame.frame()

		backgroundColor.set()
		aRect.intersection(frame.insetBy(dx: 1, dy: 1)).fill()

		let stringAttributes: [NSAttributedString.Key: Any] = [
			.foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
			.font: OakControlFont(),
		]

		let display = displayString ?? ""
		let size = display.size(withAttributes: stringAttributes)
		display.draw(at: NSPoint(x: visibleRect.midX - size.width / 2, y: visibleRect.midY - size.height / 2), withAttributes: stringAttributes)
	}

	override func drawFocusRingMask() {
		bounds.fill()
	}

	override var focusRingMaskBounds: NSRect {
		return bounds
	}

	// A method, not a property: -accessibilityIsIgnored is the legacy NSObject
	// accessibility call, and Swift imports it as a func.
	override func accessibilityIsIgnored() -> Bool { false }

	override func accessibilityAttributeNames() -> [NSAccessibility.Attribute] {
		let myAttributes: [NSAccessibility.Attribute] = [
			.value,
			.numberOfCharacters,
			.description,
			.selectedText,
			.selectedTextRange,
			.visibleCharacterRange,
		]
		return Array(Set(myAttributes).union(super.accessibilityAttributeNames()))
	}

	override func accessibilityAttributeValue(_ attribute: NSAccessibility.Attribute) -> Any? {
		let isEmptyRecording = displayString == kRecordingPlaceholderString
		switch attribute {
			case .role:
				return NSAccessibility.Role.textField
			case .value:
				return isEmptyRecording ? "" : displayString
			case .numberOfCharacters:
				return isEmptyRecording ? 0 : (displayString?.count ?? 0)
			case .selectedText, .selectedTextRange, .visibleCharacterRange:
				return nil
			case .description:
				return "Key Equivalent"
			default:
				return super.accessibilityAttributeValue(attribute)
		}
	}
}
