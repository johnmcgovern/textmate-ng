#import <OakAppKit/OakPopOutAnimation.h>
#import <QuartzCore/QuartzCore.h>

// OakShowPopOutAnimation is the "found it" flash TextMate draws over a match: a
// borderless child window holding a yellow rounded rect and a snapshot image,
// which grows, fades, and then closes itself. Everything here is observable
// without a visible window — the child-window bookkeeping is synchronous, and the
// animation runs off the main run loop, which a test can drive itself.

static NSWindow* parent_window ()
{
	// Off-screen, never ordered front: enough for -addChildWindow: and for
	// Core Animation to attach to the layer tree.
	NSWindow* res = [[NSWindow alloc] initWithContentRect:NSMakeRect(-10000, -10000, 400, 300) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
	res.releasedWhenClosed = NO;
	[res.contentView setWantsLayer:YES];
	return res;
}

static NSImage* test_image ()
{
	NSImage* res = [[NSImage alloc] initWithSize:NSMakeSize(32, 32)];
	[res lockFocus];
	[[NSColor redColor] set];
	NSRectFill(NSMakeRect(0, 0, 32, 32));
	[res unlockFocus];
	return res;
}

// The pop-out closes itself when its animation finishes (~0.7s). Spin the run
// loop until that happens rather than sleeping, and cap it so a regression that
// stops the window closing fails the test instead of hanging the bundle.
static bool wait_for_child_windows (NSWindow* window, NSUInteger count, NSTimeInterval timeout = 5.0)
{
	NSDate* giveUp = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while(window.childWindows.count != count && [giveUp timeIntervalSinceNow] > 0)
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
	return window.childWindows.count == count;
}

void setup ()
{
	// CAAnimation needs an application object to have set up the main run loop
	// before it will schedule anything.
	NSApplicationLoad();
}

// A degenerate rect is the documented no-op: OakTextView asks for a pop-out over
// whatever rect the match occupies, and an empty match must not flash a window.
void test_empty_rect_is_ignored ()
{
	NSWindow* window = parent_window();
	NSView* view = window.contentView;

	OakShowPopOutAnimation(view, NSMakeRect(100, 100, 0, 20), test_image());
	OAK_ASSERT_EQ(window.childWindows.count, 0);

	OakShowPopOutAnimation(view, NSMakeRect(100, 100, 40, 0), test_image());
	OAK_ASSERT_EQ(window.childWindows.count, 0);

	OakShowPopOutAnimation(view, NSZeroRect, test_image());
	OAK_ASSERT_EQ(window.childWindows.count, 0);
}

void test_shows_and_closes_child_window ()
{
	NSWindow* window = parent_window();
	NSView* view = window.contentView;
	NSRect const popOutRect = NSMakeRect(100, 100, 48, 20);

	OakShowPopOutAnimation(view, popOutRect, test_image());
	OAK_ASSERT_EQ(window.childWindows.count, 1);

	NSWindow* popOut = window.childWindows.firstObject;
	OAK_ASSERT_EQ((bool)popOut.ignoresMouseEvents, true);   // must not steal clicks
	OAK_ASSERT_EQ((bool)popOut.isOpaque, false);
	OAK_ASSERT_EQ((bool)popOut.excludedFromWindowsMenu, true);

	// The window is grown around the rect to leave room for the 1.3x scale-up and
	// the shadow, so it is strictly larger than what the caller asked for.
	OAK_ASSERT_GT(NSWidth(popOut.frame),  NSWidth(popOutRect));
	OAK_ASSERT_GT(NSHeight(popOut.frame), NSHeight(popOutRect));

	// …and closes itself once the fade completes, with no help from the caller.
	OAK_ASSERT_EQ(wait_for_child_windows(window, 0), true);
}

// Successive pop-outs replace each other by default — otherwise holding down
// find-next would stack a window per match.
void test_hide_previous ()
{
	NSWindow* window = parent_window();
	NSView* view = window.contentView;

	OakShowPopOutAnimation(view, NSMakeRect(10, 10, 48, 20), test_image());
	OakShowPopOutAnimation(view, NSMakeRect(80, 10, 48, 20), test_image());
	OAK_ASSERT_EQ(window.childWindows.count, 1);

	OAK_ASSERT_EQ(wait_for_child_windows(window, 0), true);
}

void test_keep_previous ()
{
	NSWindow* window = parent_window();
	NSView* view = window.contentView;

	OakShowPopOutAnimation(view, NSMakeRect(10, 10, 48, 20), test_image(), NO);
	OakShowPopOutAnimation(view, NSMakeRect(80, 10, 48, 20), test_image(), NO);
	OAK_ASSERT_EQ(window.childWindows.count, 2);

	OAK_ASSERT_EQ(wait_for_child_windows(window, 0), true);
}

// A pop-out anchored in a scroll view has to disappear the moment the view
// scrolls, or it would sit over unrelated text at a stale position.
void test_scrolling_dismisses ()
{
	NSWindow* window = parent_window();
	NSScrollView* scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
	NSView* documentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 2000)];
	scrollView.documentView = documentView;
	scrollView.contentView.postsBoundsChangedNotifications = YES;
	[window.contentView addSubview:scrollView];

	OakShowPopOutAnimation(documentView, NSMakeRect(10, 10, 48, 20), test_image());
	OAK_ASSERT_EQ(window.childWindows.count, 1);

	[scrollView.contentView scrollToPoint:NSMakePoint(0, 500)];
	[scrollView reflectScrolledClipView:scrollView.contentView];

	OAK_ASSERT_EQ(wait_for_child_windows(window, 0, 1.0), true);
}
