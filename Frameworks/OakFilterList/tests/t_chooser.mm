#import "../src/OakChooser.h"

// Written against the ObjC++ OakChooser, before the Swift port (rule 18). OakChooser is the
// base four choosers subclass, so what the port must not break is the contract those
// subclasses stand on: the lazily-built view getters, the item/selection/filter plumbing,
// and — most importantly — that the base's own calls to -updateItems:/-updateStatusText:/
// -updateFilterString: dispatch through to a subclass override. In Swift those methods have
// to be @objc dynamic or an ObjC subclass override is silently bypassed; the subclass below
// judges exactly that, passing trivially on the ObjC++ original and failing loudly on a port
// that gets the dispatch wrong.

#import "OakChooserTestSubclass.h"

void setup ()
{
	NSApplicationLoad();
}

void test_chooser_is_constructible_with_a_window ()
{
	OakChooser* chooser = [OakChooser new];
	OAK_ASSERT(chooser != nil);
	OAK_ASSERT([chooser isKindOfClass:NSWindowController.class]);
	OAK_ASSERT(chooser.window != nil);
}

void test_chooser_builds_its_views_lazily ()
{
	OakChooser* chooser = [OakChooser new];
	OAK_ASSERT([chooser.searchField isKindOfClass:NSSearchField.class]);
	OAK_ASSERT([chooser.tableView isKindOfClass:NSTableView.class]);
	OAK_ASSERT([chooser.scrollView isKindOfClass:NSScrollView.class]);
	OAK_ASSERT([chooser.footerView isKindOfClass:NSVisualEffectView.class]);
	OAK_ASSERT([chooser.statusTextField isKindOfClass:NSTextField.class]);
	OAK_ASSERT([chooser.itemCountTextField isKindOfClass:NSTextField.class]);
}

void test_chooser_action_and_target_round_trip ()
{
	OakChooser* chooser = [OakChooser new];
	id target = [NSObject new];
	chooser.action = @selector(accept:);
	chooser.target = target;
	OAK_ASSERT(chooser.action == @selector(accept:));
	OAK_ASSERT(chooser.target == target);
}

void test_chooser_items_drive_count_and_selection ()
{
	OakChooser* chooser = [OakChooser new];
	(void)chooser.tableView; // -selectedItems needs the lazily-built table (nil selectedRowIndexes throws); every real subclass builds its UI at init

	chooser.items = @[ @{ @"name": @"alpha" }, @{ @"name": @"beta" } ];

	OAK_ASSERT(chooser.items.count == 2);
	OAK_ASSERT([chooser.itemCountTextField.stringValue rangeOfString:@"2"].location != NSNotFound);
	OAK_ASSERT(chooser.selectedItems.count == 1);
	OAK_ASSERT([chooser.selectedItems.firstObject isEqual:chooser.items.firstObject]);
}

void test_chooser_setFilterString_updates_search_field ()
{
	OakChooser* chooser = [OakChooser new];
	chooser.filterString = @"needle";
	OAK_ASSERT([chooser.filterString isEqualToString:@"needle"]);
	OAK_ASSERT([chooser.searchField.stringValue isEqualToString:@"needle"]);
}

void test_chooser_remove_items_at_indexes ()
{
	OakChooser* chooser = [OakChooser new];
	chooser.items = @[ @{ @"name": @"a" }, @{ @"name": @"b" }, @{ @"name": @"c" } ];
	NSUInteger removed = [chooser removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:1]];
	OAK_ASSERT(removed == 1);
	OAK_ASSERT(chooser.items.count == 2);
}

void test_chooser_dispatches_internal_calls_to_subclass_overrides ()
{
	OakChooserTestSubclass* chooser = [OakChooserTestSubclass new];

	// -setItems: calls -updateStatusText: on self.
	chooser.items = @[ @{ @"name": @"a" } ];
	OAK_ASSERT(chooser.updateStatusTextCalls > 0);

	// -setFilterString: calls -updateFilterString:, whose base impl calls -updateItems:.
	chooser.filterString = @"a";
	OAK_ASSERT(chooser.updateFilterStringCalls > 0);
	OAK_ASSERT(chooser.updateItemsCalls > 0);
}

void test_chooser_row_view_renders_an_attributed_name ()
{
	// SymbolChooser is the one subclass that uses the base's
	// -tableView:viewForTableColumn:row:, and its items' "name" is an NSAttributedString
	// carrying the match highlighting, never an NSString. The ObjC++ passed it straight to
	// -setStringValue:, which stores a non-string as the cell's objectValue and draws it
	// with its attributes. A translation that narrows the value to String instead blanks
	// every row in Jump to Symbol, with nothing else to notice it — so pin it here.
	OakChooser* chooser = [OakChooser new];
	NSAttributedString* name = [[NSAttributedString alloc] initWithString:@"symbolName" attributes:@{ NSBackgroundColorAttributeName: NSColor.yellowColor }];
	chooser.items = @[ @{ @"name": name } ];

	NSTableColumn* column = chooser.tableView.tableColumns.firstObject;
	NSTextField* view = (NSTextField*)[(id<NSTableViewDelegate>)chooser tableView:chooser.tableView viewForTableColumn:column row:0];

	OAK_ASSERT(view != nil);
	OAK_ASSERT([view.stringValue isEqualToString:@"symbolName"]);
	OAK_ASSERT([view.attributedStringValue.string isEqualToString:@"symbolName"]);
	OAK_ASSERT([view.attributedStringValue attribute:NSBackgroundColorAttributeName atIndex:0 effectiveRange:NULL] != nil);
}

void test_chooser_keeps_its_public_selector_surface ()
{
	SEL const selectors[] = {
		@selector(showWindowRelativeToFrame:),
		@selector(addTitlebarAccessoryView:),
		@selector(updateScrollViewInsets),
		@selector(updateFilterString:),
		@selector(removeItemsAtIndexes:),
		@selector(performDefaultButtonClick:),
		@selector(accept:),
		@selector(cancel:),
		@selector(filterString),        @selector(setFilterString:),
		@selector(items),               @selector(setItems:),
		@selector(selectedItems),
		@selector(action),              @selector(setAction:),
		@selector(target),              @selector(setTarget:),
		@selector(drawTableViewAsHighlighted), @selector(setDrawTableViewAsHighlighted:),
		@selector(searchField), @selector(tableView), @selector(scrollView),
		@selector(footerView), @selector(statusTextField), @selector(itemCountTextField),
	};

	for(SEL selector : selectors)
		OAK_ASSERT([OakChooser instancesRespondToSelector:selector]);
}
