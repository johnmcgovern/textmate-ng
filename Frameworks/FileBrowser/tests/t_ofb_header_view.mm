#import "../src/OFB/OFBHeaderView.h"

// OFBHeaderView is the framework's first Swift-implemented class. The header is
// hand-written ObjC (OFBHeaderView.h) and nothing checks it against the Swift at
// build time, so this pins the two things that would otherwise fail silently at
// runtime: the class is still constructible through -initWithFrame:, and its
// three controls are wired.
//
// They matter because FileBrowserViewController reaches every one of them by
// name — folderPopUpButton for the location menu and its will-pop-up
// notification, goBackButton / goForwardButton for target/action and the
// enabled-state bindings. A port that renamed or dropped one would leave a nil
// control and a dead button, with no compile error to catch it.

void setup ()
{
	NSApplicationLoad();
}

void test_ofb_header_view_builds_its_controls ()
{
	OFBHeaderView* view = [[OFBHeaderView alloc] initWithFrame:NSZeroRect];
	OAK_ASSERT(view != nil);
	OAK_ASSERT(view.folderPopUpButton != nil);
	OAK_ASSERT(view.goBackButton != nil);
	OAK_ASSERT(view.goForwardButton != nil);
}
