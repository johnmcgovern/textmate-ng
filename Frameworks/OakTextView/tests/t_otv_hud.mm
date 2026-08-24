#import "OakTextViewTesting.h"
#import <ns/ns.h>
#import <Cocoa/Cocoa.h>

// Coverage for OTVHUD — the grey rounded overlay that shows the line number
// while you drag the scroller. 118 lines, no C++.
//
// Two things here are easy to lose in a port and invisible when lost: the HUD is
// *cached* per view rather than rebuilt, and its label is sized from a dummy
// "88888" at construction so that later numbers do not make it jump.

void setup ()
{
	NSApplicationLoad();
}

static std::string describe (NSString* str)
{
	return str ? to_s(str) : std::string("«nil»");
}

// A view in a real window: -initWithView: converts through
// -[NSWindow convertRectToScreen:] and cannot work on a detached view.
static NSView* hosted_view ()
{
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
	NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
	[window.contentView addSubview:view];
	return view;
}

static NSTextField* label_of (OTVHUD* hud)
{
	for(NSView* subview in hud.window.contentView.subviews)
	{
		if([subview isKindOfClass:NSTextField.class])
			return (NSTextField*)subview;
	}
	return nil;
}

// ==================================================================
// = The window it builds                                           =
// ==================================================================

void test_otv_hud_window_is_a_borderless_overlay ()
{
	OTVHUD* hud = [[OTVHUD alloc] initWithView:hosted_view()];
	OAK_ASSERT_EQ((bool)(hud != nil), true);

	NSWindow* window = hud.window;
	// Every one of these matters: a HUD that takes mouse events swallows clicks on
	// the editor underneath, and one at the wrong level hides behind menus.
	OAK_ASSERT_EQ((bool)(window.styleMask == NSWindowStyleMaskBorderless), true);
	OAK_ASSERT_EQ((bool)window.ignoresMouseEvents, true);
	OAK_ASSERT_EQ((bool)window.isOpaque, false);
	OAK_ASSERT_EQ((long)window.level, (long)NSPopUpMenuWindowLevel);
}

void test_otv_hud_is_100_by_30_in_the_top_right ()
{
	NSView* view = hosted_view();
	OTVHUD* hud = [[OTVHUD alloc] initWithView:view];

	// Fixed size, inset 10 from the view's visible rect and pinned to its
	// top-right corner. The numbers are constants in -initWithView:.
	OAK_ASSERT_EQ((double)NSWidth(hud.window.frame),  (double)100);
	OAK_ASSERT_EQ((double)NSHeight(hud.window.frame), (double)30);

	NSRect host = [view.window convertRectToScreen:[view convertRect:view.visibleRect toView:nil]];
	host = NSInsetRect(host, 10, 10);
	OAK_ASSERT_EQ((double)NSMaxX(hud.window.frame), (double)NSMaxX(host));
	OAK_ASSERT_EQ((double)NSMaxY(hud.window.frame), (double)NSMaxY(host));
}

// ==================================================================
// = The label, and the dummy string that sizes it                  =
// ==================================================================

void test_otv_hud_label_is_sized_from_a_five_digit_dummy ()
{
	OTVHUD* hud = [[OTVHUD alloc] initWithView:hosted_view()];
	NSTextField* label = label_of(hud);
	OAK_ASSERT_EQ((bool)(label != nil), true);

	// -initWithView: sets the string to "88888" and *then* calls -sizeToFit, so the
	// height is the height of five wide digits at 20pt — not of whatever text the
	// HUD happens to show first. Dropping that line makes the label resize as the
	// line number grows.
	OAK_ASSERT_EQ(describe(label.stringValue), std::string("88888"));
	OAK_ASSERT_GT((double)NSHeight(label.frame), (double)0);

	// Full width, vertically centred in the 30pt window.
	OAK_ASSERT_EQ((double)NSWidth(label.frame), (double)100);
	OAK_ASSERT_EQ((double)NSMinY(label.frame), (double)round((30 - NSHeight(label.frame)) / 2));
}

void test_otv_hud_string_value_is_centred_white_and_shadowed ()
{
	OTVHUD* hud = [[OTVHUD alloc] initWithView:hosted_view()];
	hud.stringValue = @"1234";

	NSTextField* label = label_of(hud);
	OAK_ASSERT_EQ(describe(label.stringValue), std::string("1234"));

	// The attributes are the HUD's whole appearance — it draws on a translucent
	// grey rounded rect, so white text with a shadow is what makes it readable
	// over both a light and a dark document.
	NSAttributedString* styled = label.objectValue;
	OAK_ASSERT_EQ((bool)[styled isKindOfClass:NSAttributedString.class], true);

	NSDictionary* attrs = [styled attributesAtIndex:0 effectiveRange:nullptr];
	OAK_ASSERT_EQ((long)[attrs[NSParagraphStyleAttributeName] alignment], (long)NSTextAlignmentCenter);
	OAK_ASSERT_EQ((bool)[attrs[NSForegroundColorAttributeName] isEqual:NSColor.whiteColor], true);

	NSShadow* shadow = attrs[NSShadowAttributeName];
	OAK_ASSERT_EQ((bool)(shadow != nil), true);
	OAK_ASSERT_EQ((double)shadow.shadowOffset.width,  (double)1);
	OAK_ASSERT_EQ((double)shadow.shadowOffset.height, (double)-1);
}

// ==================================================================
// = +showHudForView:withText:, which caches                        =
// ==================================================================

void test_otv_hud_is_reused_for_the_same_view ()
{
	NSView* view = hosted_view();

	OTVHUD* first  = [OTVHUD showHudForView:view withText:@"1"];
	OTVHUD* second = [OTVHUD showHudForView:view withText:@"2"];

	// Same view means the same HUD object, moved and relabelled rather than
	// rebuilt — otherwise every scroll tick would order a new window on screen.
	OAK_ASSERT_EQ((bool)(first == second), true);
	OAK_ASSERT_EQ(describe(label_of(second).stringValue), std::string("2"));
	OAK_ASSERT_EQ((bool)(second.lastView == view), true);
}

void test_otv_hud_is_rebuilt_for_a_different_view ()
{
	NSView* one = hosted_view();
	NSView* two = hosted_view();

	OTVHUD* first  = [OTVHUD showHudForView:one withText:@"1"];
	OTVHUD* second = [OTVHUD showHudForView:two withText:@"2"];

	// The cache key is the view, and it is a single slot — not a map. A second
	// editor gets its own HUD, and the first one's is dropped.
	OAK_ASSERT_EQ((bool)(first == second), false);
	OAK_ASSERT_EQ((bool)(second.lastView == two), true);
}
