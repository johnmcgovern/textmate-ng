#import "../src/FileItemTableCellView.h"

// FileItemTableCellView is implemented in Swift behind a hand-written ObjC
// header, and it is the framework's first bindings-heavy port. This pins the
// two things a drift would break silently:
//
//   * -init still constructs the view with its two buttons wired.
//     FileBrowserViewController creates the cell with -init (rule 2) and sets
//     openButton/closeButton target+action by name, so a missing button or a
//     renamed -init is a dead control with no compile error.
//   * fileReference is @objc dynamic. Its getter/setter must be reachable for
//     KVO, because the icon and close-button bindings observe key paths rooted
//     at it and the view sets it from Swift — the rule-1 trap. A test can prove
//     the selectors exist; whether the binding actually fires is verified in the
//     app.
//
// The tag-crescent drawing and the basename-selection-on-rename need a live
// window and are checked there.

void setup ()
{
	NSApplicationLoad();
}

void test_file_item_table_cell_view_is_constructible ()
{
	FileItemTableCellView* view = [[FileItemTableCellView alloc] init];
	OAK_ASSERT(view != nil);
	OAK_ASSERT([view isKindOfClass:NSTableCellView.class]);
	OAK_ASSERT(view.openButton != nil);
	OAK_ASSERT(view.closeButton != nil);
}

void test_file_item_table_cell_view_keeps_its_binding_source ()
{
	// The rule-1 property the icon / closable bindings hang off.
	OAK_ASSERT([FileItemTableCellView instancesRespondToSelector:@selector(fileReference)]);
	OAK_ASSERT([FileItemTableCellView instancesRespondToSelector:@selector(setFileReference:)]);
	OAK_ASSERT([FileItemTableCellView instancesRespondToSelector:@selector(openButton)]);
	OAK_ASSERT([FileItemTableCellView instancesRespondToSelector:@selector(closeButton)]);
}
