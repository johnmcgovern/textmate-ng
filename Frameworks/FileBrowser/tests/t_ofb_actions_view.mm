#import "../src/OFB/OFBActionsView.h"

// OFBActionsView is implemented in Swift with a hand-written ObjC header, so
// nothing checks the two against each other at build time. This pins that the
// class is still constructible through -initWithFrame: and that all six controls
// are wired — FileBrowserViewController reaches every one by name (createButton,
// reloadButton, searchButton, favoritesButton, scmButton for target/action, and
// actionsPopUpButton for the actions menu's delegate). A dropped or renamed
// control is a dead button with no compile error.

void setup ()
{
	NSApplicationLoad();
}

void test_ofb_actions_view_builds_its_controls ()
{
	OFBActionsView* view = [[OFBActionsView alloc] initWithFrame:NSZeroRect];
	OAK_ASSERT(view != nil);
	OAK_ASSERT(view.createButton != nil);
	OAK_ASSERT(view.actionsPopUpButton != nil);
	OAK_ASSERT(view.reloadButton != nil);
	OAK_ASSERT(view.searchButton != nil);
	OAK_ASSERT(view.favoritesButton != nil);
	OAK_ASSERT(view.scmButton != nil);
}
