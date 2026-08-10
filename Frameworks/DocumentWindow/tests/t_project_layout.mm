#import "DocumentWindowTesting.h"

// ProjectLayoutView is the splitter: document view in the middle, file browser
// on one side, HTML output on the other side or underneath, with a draggable
// divider between each.
//
// Almost all of it is Auto Layout and a manual mouse-tracking loop, neither of
// which a headless test can drive. What *is* pure, and what everything else
// depends on, are the two resize rects: they decide where the cursor changes
// shape (-resetCursorRects) and where a click starts a drag instead of falling
// through to the view underneath (-hitTest:). Get them wrong and the divider
// silently stops being draggable — a defect no build or signature check can see,
// and one you would only notice by trying to drag it.
//
// The rects are deliberately not symmetric: 3pt on one side of the divider and
// 4pt on the other, for a 10pt-wide target. That asymmetry looks like a typo, is
// not, and is exactly what a port would "clean up".

static ProjectLayoutView* LayoutViewWithFileBrowser (NSRect browserFrame, BOOL onRight)
{
	ProjectLayoutView* view = [[ProjectLayoutView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
	NSView* browser = [[NSView alloc] initWithFrame:browserFrame];
	view.fileBrowserOnRight = onRight;
	view.fileBrowserView    = browser;
	browser.frame           = browserFrame; // Auto Layout has not run; pin it back
	return view;
}

static ProjectLayoutView* LayoutViewWithHTMLOutput (NSRect outputFrame, BOOL onRight)
{
	ProjectLayoutView* view = [[ProjectLayoutView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
	NSView* output = [[NSView alloc] initWithFrame:outputFrame];
	view.htmlOutputOnRight = onRight;
	view.htmlOutputView    = output;
	output.frame           = outputFrame;
	return view;
}

void test_project_layout_view_is_constructible ()
{
	ProjectLayoutView* view = [[ProjectLayoutView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
	OAK_ASSERT(view != nil);
}

// With no file browser and no HTML output there is nothing to drag, and both
// rects are empty rather than some default — otherwise the whole window would
// show a resize cursor.
void test_resize_rects_are_empty_without_their_views ()
{
	ProjectLayoutView* view = [[ProjectLayoutView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
	OAK_ASSERT(NSIsEmptyRect(view.fileBrowserResizeRect));
	OAK_ASSERT(NSIsEmptyRect(view.htmlOutputResizeRect));
}

// File browser on the left: the grab strip sits at its trailing edge, starting
// 4pt *inside* the browser and running 10pt across the divider.
void test_file_browser_resize_rect_on_the_left ()
{
	NSRect frame = NSMakeRect(0, 0, 250, 600);
	ProjectLayoutView* view = LayoutViewWithFileBrowser(frame, NO);

	NSRect rect = view.fileBrowserResizeRect;
	OAK_ASSERT_EQ(NSMinX(rect), NSMaxX(frame) - 4);
	OAK_ASSERT_EQ(NSWidth(rect), 10);
	OAK_ASSERT_EQ(NSMinY(rect), NSMinY(frame));
	OAK_ASSERT_EQ(NSHeight(rect), NSHeight(frame));
}

// On the right it flips to the leading edge, and to 3pt rather than 4 — the
// asymmetry this file exists to pin.
void test_file_browser_resize_rect_on_the_right ()
{
	NSRect frame = NSMakeRect(550, 0, 250, 600);
	ProjectLayoutView* view = LayoutViewWithFileBrowser(frame, YES);

	NSRect rect = view.fileBrowserResizeRect;
	OAK_ASSERT_EQ(NSMinX(rect), NSMinX(frame) - 3);
	OAK_ASSERT_EQ(NSWidth(rect), 10);
}

// HTML output on the right is a vertical strip at its leading edge…
void test_html_output_resize_rect_on_the_right ()
{
	NSRect frame = NSMakeRect(600, 0, 200, 600);
	ProjectLayoutView* view = LayoutViewWithHTMLOutput(frame, YES);

	NSRect rect = view.htmlOutputResizeRect;
	OAK_ASSERT_EQ(NSMinX(rect), NSMinX(frame) - 3);
	OAK_ASSERT_EQ(NSWidth(rect), 10);
	OAK_ASSERT_EQ(NSHeight(rect), NSHeight(frame));
}

// …and underneath it is a *horizontal* strip at its top edge, spanning the full
// width. Both the orientation and which edge it hangs off change together.
void test_html_output_resize_rect_underneath ()
{
	NSRect frame = NSMakeRect(0, 0, 800, 200);
	ProjectLayoutView* view = LayoutViewWithHTMLOutput(frame, NO);

	NSRect rect = view.htmlOutputResizeRect;
	OAK_ASSERT_EQ(NSMinX(rect), NSMinX(frame));
	OAK_ASSERT_EQ(NSWidth(rect), NSWidth(frame));
	OAK_ASSERT_EQ(NSMinY(rect), NSMaxY(frame) - 4);
	OAK_ASSERT_EQ(NSHeight(rect), 10);
}

// The two defaults the view registers for itself. 250 and 200×200 are the
// out-of-the-box pane sizes; a port that forgets to register them gets 0 from
// -integerForKey: and opens with a collapsed file browser.
void test_layout_defaults_are_registered ()
{
	// Constructing the view is what triggers registration — +initialize in the
	// ObjC++, and the first construction in Swift, which has no +initialize.
	(void)[[ProjectLayoutView alloc] initWithFrame:NSZeroRect];

	OAK_ASSERT_EQ([NSUserDefaults.standardUserDefaults integerForKey:@"fileBrowserWidth"], 250);
	OAK_ASSERT(NSEqualSizes(NSSizeFromString([NSUserDefaults.standardUserDefaults stringForKey:@"htmlOutputSize"]), NSMakeSize(200, 200)));
}

// The <rdar://13093498> workaround: moving the HTML output from the bottom to
// the side has to rebuild the divider, because reusing it leaves a line drawn
// along the wrong axis. The observable part is that the setter re-runs the view
// setter rather than only flipping the flag.
void test_moving_html_output_to_the_side_rebuilds_its_divider ()
{
	ProjectLayoutView* view = LayoutViewWithHTMLOutput(NSMakeRect(0, 0, 800, 200), NO);
	NSView* dividerBefore = view.htmlOutputDivider;
	OAK_ASSERT(dividerBefore != nil);

	view.htmlOutputOnRight = YES;
	OAK_ASSERT(view.htmlOutputDivider != nil);
	OAK_ASSERT(view.htmlOutputDivider != dividerBefore);
}
