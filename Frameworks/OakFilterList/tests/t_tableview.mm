#import "../src/ui/TableView.h"

// Written against the ObjC++ OakInactiveTableRowView, before the Swift port, so it
// judges the original and not the translation (rule 18). This is OakFilterList's
// first test bundle: it exists to pin the one class this framework starts porting
// bottom-up, the row view OakChooser's table uses to draw an inactive selection.
//
// The whole contract is a selector surface with no protocol behind it. OakChooser
// makes the view with +new and drives it through -setDrawAsHighlighted: from
// -setDrawTableViewAsHighlighted: and -tableView:didAddRowView:forRow:; the four
// NSTableRowView overrides (-setSelected:, -setEmphasized:, -interiorBackgroundStyle,
// -drawSelectionInRect:) are what make the dark-fill actually appear. A Swift port
// that renamed or dropped -drawAsHighlighted/-setDrawAsHighlighted: — or exported the
// property under a trimmed spelling — would leave the selection stuck in its default
// look with no compile error and no failing build, exactly the gap rule 18 covers.

void setup ()
{
	NSApplicationLoad();
}

void test_inactive_table_row_view_is_constructible ()
{
	OakInactiveTableRowView* view = [OakInactiveTableRowView new];
	OAK_ASSERT(view != nil);
	OAK_ASSERT([view isKindOfClass:NSTableRowView.class]);
}

void test_inactive_table_row_view_keeps_its_highlight_surface ()
{
	SEL const selectors[] = {
		@selector(drawAsHighlighted),
		@selector(setDrawAsHighlighted:),
		@selector(setSelected:),
		@selector(setEmphasized:),
		@selector(interiorBackgroundStyle),
		@selector(drawSelectionInRect:),
	};

	for(SEL selector : selectors)
		OAK_ASSERT([OakInactiveTableRowView instancesRespondToSelector:selector]);
}

void test_inactive_table_row_view_drawAsHighlighted_round_trips ()
{
	OakInactiveTableRowView* view = [OakInactiveTableRowView new];
	OAK_ASSERT(view.drawAsHighlighted == NO);
	view.drawAsHighlighted = YES;
	OAK_ASSERT(view.drawAsHighlighted == YES);
}
