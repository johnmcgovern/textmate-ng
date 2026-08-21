import AppKit

// Ported from SymbolChooser.mm (2026-08-20). The ⇧⌘T "Jump to Symbol" panel: an OakChooser
// whose items are the current document's symbols, filtered by the search field. All of its
// C++ — the symbol walk, the ranking, the caret-position matching — was extracted first and
// stays ObjC++ behind SymbolChooserSupport (rules 15 and 19); what is left here is the
// controller. Contract pinned by t_symbol_chooser.mm (rule 18).
//
// OakDocumentView.mm drives this write-only through the hand-declaration in SymbolChooser.h,
// setting .TMDocument and .selectionString. The class is the first Swift subclass of the
// (also Swift) OakChooser; its overrides of updateItems:/updateStatusText: are the hooks the
// base calls on self, which is why the base declares them dynamic (rule 50).
@objc(SymbolChooser)
class SymbolChooser: OakChooser {
	@objc static let sharedInstance = SymbolChooser()

	private static let baseTitle = "Jump to Symbol"

	@objc override init() {
		super.init()

		window?.title = Self.baseTitle

		let titlebarViews: [String: NSView] = ["searchField": searchField]
		let titlebarView = NSView(frame: .zero)
		OakAddAutoLayoutViewsToSuperview(Array(titlebarViews.values), titlebarView)

		titlebarView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(8)-[searchField]-(8)-|", options: [], metrics: nil, views: titlebarViews))
		titlebarView.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-(4)-[searchField]-(8)-|", options: [], metrics: nil, views: titlebarViews))
		addTitlebarAccessoryView(titlebarView)

		let footerViews: [String: NSView] = [
			"dividerView":        OakCreateNSBoxSeparator(),
			"statusTextField":    statusTextField,
			"itemCountTextField": itemCountTextField,
		]

		let footer = footerView
		OakAddAutoLayoutViewsToSuperview(Array(footerViews.values), footer)

		footer.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[dividerView]|", options: [], metrics: nil, views: footerViews))
		footer.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[statusTextField]-[itemCountTextField]-|", options: .alignAllCenterY, metrics: nil, views: footerViews))
		footer.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[dividerView(==1)]-(4)-[statusTextField]-(5)-|", options: [], metrics: nil, views: footerViews))

		updateScrollViewInsets()

		window?.initialFirstResponder = searchField
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func windowWillClose(_ notification: Notification) {
		TMDocument = nil
	}

	@objc var TMDocument: OakDocument? {
		didSet {
			if TMDocument != nil {
				updateItems(self)
			}
			window?.title = TMDocument.map { "\(Self.baseTitle) — \($0.displayName ?? "")" } ?? Self.baseTitle
		}
	}

	@objc var selectionString: String? {
		didSet {
			let row = SymbolChooserSupport.indexOfItem(forSelectionString: selectionString, in: items as? [SymbolChooserItem] ?? [])
			if row != NSNotFound {
				tableView.selectRowIndexes(IndexSet(integer: Int(row)), byExtendingSelection: false)
				tableView.scrollRowToVisible(Int(row))
			}
		}
	}

	override func updateItems(_ sender: Any?) {
		items = SymbolChooserSupport.items(for: TMDocument, filterString: filterString)
	}

	override func updateStatusText(_ sender: Any?) {
		if let item = (items as? [SymbolChooserItem])?.at(tableView.selectedRow == -1 ? 0 : tableView.selectedRow) {
			statusTextField.stringValue = item.infoString ?? ""
		} else {
			statusTextField.stringValue = ""
		}
	}
}

private extension Array {
	func at(_ index: Int) -> Element? {
		indices.contains(index) ? self[index] : nil
	}
}
