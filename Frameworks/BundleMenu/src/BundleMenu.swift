import AppKit

// BundleMenu builds the Bundles menu and the disambiguation popup: given a set
// of bundle items, group them under their bundles, honour each bundle's own menu
// layout, and emit NSMenuItems carrying the item's UUID as represented object.
//
// It was the framework most obviously blocked on C++ — every one of its public
// functions took or returned bundles::item_ptr — and is now Swift over
// TMBundleItem. The C++-typed entry point survives unchanged for the ObjC++
// callers (OakTextView, OakMainMenu); see BundleMenuSupport.mm.

// Dispatched up the responder chain to AppController Commands.mm, and `nop:` is
// this codebase's convention for a deliberately-disabled placeholder item —
// nothing implements it, so AppKit greys the item out. Neither is declared by
// anything this framework can import, so both are spelled once here.
private enum Actions {
	static let performBundleItem = Selector(("performBundleItemWithUUIDStringFrom:"))
	static let nop = Selector(("nop:"))
}

@MainActor
@objc(BundleMenuDelegate)
class BundleMenuDelegate: NSObject, NSMenuDelegate {
	@objc static let sharedInstance = BundleMenuDelegate()

	func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>, action: UnsafeMutablePointer<Selector?>) -> Bool {
		return false
	}

	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()

		// The menu's title is the umbrella item's UUID — that is how a submenu
		// knows what to populate itself with, NSMenu carrying no other payload.
		// A title that is not a known UUID leaves the menu empty.
		guard let umbrellaItem = TMBundleItem.item(uuidString: menu.title) else { return }

		let scope = TMScopeContext.currentScope

		for item in umbrellaItem.menu {
			switch item.kind {
				case .menu:
					let menuItem = menu.addItem(withTitle: item.name ?? "", action: nil, keyEquivalent: "")
					let submenu = NSMenu(title: item.uuidString ?? "")
					submenu.delegate = BundleMenuDelegate.sharedInstance
					menuItem.submenu = submenu

				case .menuItemSeparator:
					menu.addItem(.separator())

				case .proxy:
					let items = TMBundleItem.items(forProxy: item, scope: scope)
					BundleMenuBuilder.addItems(items, to: menu, setKeys: true)

					// A proxy resolving to nothing still shows its own name,
					// disabled, so the menu does not silently lose an entry the
					// user's key equivalent still refers to.
					if items.isEmpty {
						let menuItem = menu.addItem(withTitle: item.name ?? "", action: Actions.nop, keyEquivalent: "")
						menuItem.setInactiveKeyEquivalent(item.keyEquivalent)
						menuItem.setTabTrigger(item.tabTrigger)
					}

				default:
					let menuItem = menu.addItem(withTitle: item.name ?? "", action: Actions.performBundleItem, keyEquivalent: "")
					menuItem.setInactiveKeyEquivalent(item.keyEquivalent)
					menuItem.setTabTrigger(item.tabTrigger)
					menuItem.representedObject = item.uuidString
			}
		}
	}
}

@MainActor
@objc(BundleMenuBuilder)
class BundleMenuBuilder: NSObject {
	// The former OakAddBundlesToMenu. `setKeys` controls whether each item shows
	// its inactive key equivalent and tab trigger; the disambiguation popup
	// passes false because it assigns 1…9,0 as real key equivalents instead.
	@objc(addItems:toMenu:setKeys:)
	static func addItems(_ items: [TMBundleItem], to menu: NSMenu, setKeys: Bool) {
		// Grammars never get bundle headings: the language popup is a flat,
		// name-sorted list.
		if !items.isEmpty && items.allSatisfy({ $0.kind == .grammar }) {
			for item in TMBundleItem.sortedByName(items) {
				add(item, to: menu, setKeys: setKeys, indented: false)
			}
			return
		}

		var byBundle: [TMBundleItem: [TMBundleItem]] = [:]
		for item in items {
			guard let bundle = item.bundle else { continue }
			byBundle[bundle, default: []].append(item)
		}

		// Sections are ordered by bundle name, matching the name-keyed multimap
		// the ObjC++ collected them in. Headings appear only when more than one
		// bundle contributed; otherwise the single section is the whole menu.
		let bundles = TMBundleItem.sortedByName(Array(byBundle.keys))
		let showBundleHeadings = bundles.count > 1

		for bundle in bundles {
			guard let bundleItems = byBundle[bundle] else { continue }

			if showBundleHeadings {
				menu.addItem(withTitle: bundle.name ?? "", action: nil, keyEquivalent: "")
			}

			var suppressSeparator = true
			var pendingSeparator = false

			for item in laidOut(bundleItems, in: bundle) {
				guard item.kind != .menuItemSeparator else {
					// Leading separators are dropped and runs of them collapse:
					// the layout brackets every flattened submenu with one, so
					// only the interior ones carry meaning.
					if !suppressSeparator {
						pendingSeparator = true
					}
					continue
				}

				// Separators are suppressed entirely under headings, where the
				// heading is already the visual break.
				if !showBundleHeadings && pendingSeparator {
					menu.addItem(.separator())
				}
				pendingSeparator = false

				add(item, to: menu, setKeys: setKeys, indented: showBundleHeadings)
				suppressSeparator = false
			}
		}
	}

	private static func add(_ item: TMBundleItem, to menu: NSMenu, setKeys: Bool, indented: Bool) {
		let menuItem = menu.addItem(withTitle: item.name ?? "", action: Actions.performBundleItem, keyEquivalent: "")
		menuItem.representedObject = item.uuidString

		if setKeys {
			menuItem.setInactiveKeyEquivalent(item.keyEquivalent)
			menuItem.setTabTrigger(item.tabTrigger)
		}

		if indented {
			menuItem.indentationLevel = 1
		}
	}

	// Order `items` the way `bundle`'s own menu structure does, then append
	// whatever that structure did not mention, name-sorted. Items are consumed
	// as the structure claims them, so one listed twice is emitted once.
	private static func laidOut(_ items: [TMBundleItem], in bundle: TMBundleItem) -> [TMBundleItem] {
		var remaining = Set(items)
		var res = filteredMenu(of: bundle, including: &remaining)
		res.append(contentsOf: TMBundleItem.sortedByName(Array(remaining)))
		return res
	}

	private static func filteredMenu(of menuItem: TMBundleItem, including remaining: inout Set<TMBundleItem>) -> [TMBundleItem] {
		var res: [TMBundleItem] = []
		for item in menuItem.menu {
			switch item.kind {
				case .menuItemSeparator:
					res.append(item)

				case .menu:
					// A submenu is flattened into its parent, bracketed by
					// separators. The caller collapses runs of them, so an empty
					// submenu leaves no trace.
					res.append(TMBundleItem.menuItemSeparator)
					res.append(contentsOf: filteredMenu(of: item, including: &remaining))
					res.append(TMBundleItem.menuItemSeparator)

				default:
					if remaining.remove(item) != nil {
						res.append(item)
					}
			}
		}
		return res
	}
}

// The former OakShowMenuForBundleItems. Returns the chosen item, or nil when the
// menu was dismissed. Reached from ObjC++ through BundleMenuSupport.mm, which is
// where the bundles::item_ptr conversion lives.
@MainActor
@objc(BundleMenuPopup)
class BundleMenuPopup: NSObject {
	@objc(showMenuForItems:inView:atPoint:)
	static func showMenu(for items: [TMBundleItem], in view: NSView?, at point: NSPoint) -> TMBundleItem? {
		guard items.count > 1 else { return items.first }

		let menu = NSMenu()
		let configured = UserDefaults.standard.integer(forKey: "OakBundleManagerDisambiguateMenuFontSize")
		menu.font = NSFont.menuFont(ofSize: CGFloat(configured == 0 ? 11 : configured))

		BundleMenuBuilder.addItems(items, to: menu, setKeys: false)
		menu.update()

		// 1…9 then 0, bare digits with no modifiers, so the popup can be
		// answered from the keyboard. Anything past the tenth item gets none.
		let target = BundlePopupMenuTarget()
		var key = 0
		for menuItem in menu.items where menuItem.action == Actions.performBundleItem {
			menuItem.target = target
			if key < 10 {
				key += 1
				menuItem.keyEquivalent = String(UnicodeScalar(UInt8(0x30 + key % 10)))
			} else {
				menuItem.keyEquivalent = ""
			}
			menuItem.keyEquivalentModifierMask = []
		}

		guard menu.popUp(positioning: nil, at: point, in: view) else { return nil }
		return TMBundleItem.item(uuidString: target.selectedItemUUID)
	}
}

private final class BundlePopupMenuTarget: NSObject {
	var selectedItemUUID: String?

	@objc func performBundleItemWithUUIDStringFrom(_ sender: NSMenuItem) {
		selectedItemUUID = sender.representedObject as? String
	}
}
