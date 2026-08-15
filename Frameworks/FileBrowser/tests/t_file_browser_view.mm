#import "../src/FileBrowserView.h"
#import "../src/FileBrowserOutlineView.h"
#import "../src/OFB/OFBHeaderView.h"
#import "../src/OFB/OFBActionsView.h"

// FileBrowserView is implemented in Swift behind a hand-written ObjC header, so
// nothing checks the two against each other at build time. This pins what
// FileBrowserViewController depends on: the three child views exist and have the
// types the controller casts them to (it sets targets/actions on the header's
// buttons and the actions strip's six controls), the outline view is the
// FileBrowserOutlineView subclass and not a plain NSOutlineView (the key
// bindings and context menu live on the subclass), and it is inside a scroll
// view with the single outline table column.
//
// The layout itself — the visual-format constraints, the header floated above
// the scroll view, and the content inset that offsets the list by the header's
// height — is verified in the running app, not here.

void setup ()
{
	NSApplicationLoad();
}

void test_file_browser_view_builds_its_subviews ()
{
	FileBrowserView* view = [[FileBrowserView alloc] initWithFrame:NSZeroRect];
	OAK_ASSERT(view != nil);

	OAK_ASSERT([view.headerView isKindOfClass:OFBHeaderView.class]);
	OAK_ASSERT([view.actionsView isKindOfClass:OFBActionsView.class]);
	OAK_ASSERT([view.outlineView isKindOfClass:FileBrowserOutlineView.class]);
}

void test_file_browser_view_configures_the_outline_view ()
{
	FileBrowserView* view = [[FileBrowserView alloc] initWithFrame:NSZeroRect];
	NSOutlineView* outlineView = view.outlineView;

	OAK_ASSERT_EQ(outlineView.tableColumns.count, 1);
	OAK_ASSERT(outlineView.outlineTableColumn == outlineView.tableColumns.firstObject);
	OAK_ASSERT(outlineView.allowsMultipleSelection);
	OAK_ASSERT(outlineView.headerView == nil);
	OAK_ASSERT([outlineView.registeredDraggedTypes containsObject:NSFilenamesPboardType]);

	// The controller never reaches the scroll view, but the outline view has to
	// be inside one to scroll at all.
	OAK_ASSERT(outlineView.enclosingScrollView != nil);
	OAK_ASSERT(outlineView.enclosingScrollView.documentView == outlineView);
}

void test_file_browser_view_is_an_accessibility_group ()
{
	FileBrowserView* view = [[FileBrowserView alloc] initWithFrame:NSZeroRect];
	// Not to_s() — xctest_preamble.h's generic to_s template takes an NSString*
	// here (ns.h is not in this bundle's scope) and enumerates it as a container.
	OAK_ASSERT([view.accessibilityRole isEqualToString:NSAccessibilityGroupRole]);
	OAK_ASSERT([view.accessibilityLabel isEqualToString:@"File browser"]);
	OAK_ASSERT([view.outlineView.accessibilityLabel isEqualToString:@"Files"]);
}
