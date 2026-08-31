#import "TextMateTesting.h"
#import <ns/ns.h>
#import <Cocoa/Cocoa.h>

// Coverage for AboutWindowController, written before the port. The app shell's
// first pinned file, and a leaf: a window controller with five pages of HTML and
// a segmented control to pick between them.
//
// The pages are loaded into a WKWebView from bundle resources, so what is pinned
// is everything *around* that — which page is selected, how the tabs cycle, and
// the menu the Window menu builds. That is where the behaviour actually is.

void setup ()
{
	NSApplicationLoad();
}

static std::string describe (NSString* str)
{
	return str ? to_s(str) : std::string("«nil»");
}

static std::string join (NSArray* items)
{
	return to_s([items componentsJoinedByString:@" | "]);
}

// A fresh controller rather than +sharedInstance: the singleton would carry state
// between tests, and every one of these changes the selected page.
static AboutWindowController* make_controller ()
{
	return [AboutWindowController new];
}

// ==================================================================
// = The surface a Swift port has to keep reachable                 =
// ==================================================================

void test_about_selector_surface ()
{
	Class cls = AboutWindowController.class;

	OAK_ASSERT_EQ((bool)[cls isSubclassOfClass:NSWindowController.class], true);

	OAK_ASSERT_EQ((bool)[cls respondsToSelector:@selector(sharedInstance)],        true);
	OAK_ASSERT_EQ((bool)[cls respondsToSelector:@selector(showChangesIfUpdated)],  true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(showAboutWindow:)],   true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(showChangesWindow:)], true);

	// Driven from the Window menu, and from the segmented control's action.
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(selectNextTab:)],            true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(selectPreviousTab:)],        true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(takeSelectedSegmentFrom:)],  true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(updateShowTabMenu:)],        true);
}

void test_about_shared_instance_is_a_singleton ()
{
	OAK_ASSERT_EQ((bool)(AboutWindowController.sharedInstance == AboutWindowController.sharedInstance), true);
	OAK_ASSERT_EQ((bool)(AboutWindowController.sharedInstance != nil), true);
}

// ==================================================================
// = The five pages, in order                                       =
// ==================================================================

void test_about_has_five_pages_in_a_fixed_order ()
{
	AboutWindowController* controller = make_controller();

	// The order is not decoration: it is the segmented control's left-to-right
	// order, the ⌘1–⌘5 assignment in the Window menu, and the sequence ⌘⇧] cycles
	// through. Changing it changes all three at once.
	OAK_ASSERT_EQ(join(controller.segmentLabels), std::string("About | Changes | Bundles | Legal | Contributions"));
	OAK_ASSERT_EQ((size_t)controller.segmentedControl.segmentCount, (size_t)5);
}

void test_about_toolbar_centres_the_segmented_control ()
{
	AboutWindowController* controller = make_controller();

	// Two flexible spaces around one item — that is the whole toolbar, and it is
	// what keeps the tabs centred rather than left-aligned.
	OAK_ASSERT_EQ(join([controller toolbarDefaultItemIdentifiers:nil]),
	              std::string("NSToolbarFlexibleSpaceItem | TMSegmentedControlIdentifier | NSToolbarFlexibleSpaceItem"));

	// Allowed is defined as identical to default, so the customisation sheet — if
	// it were ever opened — offers exactly what is already there.
	OAK_ASSERT_EQ(join([controller toolbarAllowedItemIdentifiers:nil]), join([controller toolbarDefaultItemIdentifiers:nil]));
}

// ==================================================================
// = Selecting a page                                               =
// ==================================================================

void test_about_selecting_a_page_moves_the_control ()
{
	AboutWindowController* controller = make_controller();

	controller.selectedPage = @"Legal";
	OAK_ASSERT_EQ(describe(controller.selectedPage), std::string("Legal"));
	OAK_ASSERT_EQ((long)controller.segmentedControl.selectedSegment, (long)3);

	controller.selectedPage = @"About";
	OAK_ASSERT_EQ((long)controller.segmentedControl.selectedSegment, (long)0);
}

void test_about_an_unknown_page_is_recorded_but_not_shown ()
{
	AboutWindowController* controller = make_controller();
	controller.selectedPage = @"Legal";

	// **The assignment happens before the lookup.** A name that is not one of the
	// five updates `selectedPage` and then falls out of the `if`, so no page is
	// loaded and the control does not move. Pinned as it behaves: a port that
	// validated first would leave selectedPage on "Legal" instead.
	controller.selectedPage = @"Nonesuch";
	OAK_ASSERT_EQ(describe(controller.selectedPage), std::string("Nonesuch"));
	OAK_ASSERT_EQ((long)controller.segmentedControl.selectedSegment, (long)3);
}

void test_about_setting_the_same_page_returns_early ()
{
	AboutWindowController* controller = make_controller();
	controller.selectedPage = @"Bundles";

	// The guard matters because the setter reloads the web view: without it, every
	// click on the already-selected tab would re-fetch the page.
	controller.segmentedControl.selectedSegment = 0;
	controller.selectedPage = @"Bundles";
	OAK_ASSERT_EQ((long)controller.segmentedControl.selectedSegment, (long)0);
}

// ==================================================================
// = Cycling                                                        =
// ==================================================================

void test_about_tabs_cycle_in_both_directions_and_wrap ()
{
	AboutWindowController* controller = make_controller();
	controller.selectedPage = @"About";

	[controller selectNextTab:nil];
	OAK_ASSERT_EQ(describe(controller.selectedPage), std::string("Changes"));

	[controller selectPreviousTab:nil];
	OAK_ASSERT_EQ(describe(controller.selectedPage), std::string("About"));

	// Backwards off the front wraps to the end — that is what the `+ count` in the
	// modulo is for, and without it the index goes negative.
	[controller selectPreviousTab:nil];
	OAK_ASSERT_EQ(describe(controller.selectedPage), std::string("Contributions"));

	[controller selectNextTab:nil];
	OAK_ASSERT_EQ(describe(controller.selectedPage), std::string("About"));
}

void test_about_cycling_from_an_unknown_page_does_nothing ()
{
	AboutWindowController* controller = make_controller();
	controller.selectedPage = @"Nonesuch";

	// indexOfObject: returns NSNotFound and the method returns early rather than
	// wrapping from a garbage index.
	[controller selectNextTab:nil];
	OAK_ASSERT_EQ(describe(controller.selectedPage), std::string("Nonesuch"));
}

// ==================================================================
// = The Window menu's tab list                                     =
// ==================================================================

void test_about_tab_menu_says_no_tabs_when_the_window_is_not_key ()
{
	AboutWindowController* controller = make_controller();

	// A test window is never key, which makes this the branch a test can reach —
	// and it is the one that matters, because the Window menu is built whether or
	// not the About window is in front.
	NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Window"];
	[controller updateShowTabMenu:menu];

	OAK_ASSERT_EQ((size_t)menu.numberOfItems, (size_t)1);
	OAK_ASSERT_EQ(describe([menu itemAtIndex:0].title), std::string("No Tabs"));
	OAK_ASSERT_EQ((bool)([menu itemAtIndex:0].action == @selector(nop:)), true);
}

// ==================================================================
// = Taking a selection from a menu item                            =
// ==================================================================

void test_about_takes_a_page_from_a_menu_items_represented_object ()
{
	AboutWindowController* controller = make_controller();
	controller.selectedPage = @"About";

	// The Window menu's rows carry their page name as the represented object; the
	// segmented control is handled by identity instead. Anything else is ignored.
	NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"Legal" action:NULL keyEquivalent:@""];
	item.representedObject = @"Legal";
	[controller takeSelectedSegmentFrom:item];
	OAK_ASSERT_EQ(describe(controller.selectedPage), std::string("Legal"));

	[controller takeSelectedSegmentFrom:nil];
	OAK_ASSERT_EQ(describe(controller.selectedPage), std::string("Legal"));
}
