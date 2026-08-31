#import "HTMLOutputTesting.h"
#import <ns/ns.h>
#import <Cocoa/Cocoa.h>

// Coverage for OakHTMLOutputView, written before the port. The framework's public
// face: the view OakCommand loads a command's output into.
//
// Most of it needs a window, a live web view or a running command, so what is
// pinned here is the part that does not: the surface other frameworks bind to,
// and the two paths that answer without touching the page.
//
// **This class is declared twice, with different superclasses**, and that is not
// a mistake to tidy. OakHTMLOutputView.h says `: HOBrowserView` and is imported
// only by its own implementation; <HTMLOutput/HTMLOutput.h> says `: NSView` and
// is what the four external consumers see. The narrower public declaration works
// because none of them needs anything a browser view adds. The test below pins
// the *runtime* answer so a port cannot quietly change which one is true.

void setup ()
{
	NSApplicationLoad();
}

static std::string describe (NSString* str)
{
	return str ? to_s(str) : std::string("«nil»");
}

static OakHTMLOutputView* make_view ()
{
	return [[OakHTMLOutputView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
}

// ==================================================================
// = The surface a Swift port has to keep reachable                 =
// ==================================================================

void test_html_output_view_selector_surface ()
{
	Class cls = OakHTMLOutputView.class;

	// The real superclass, whatever the public header says.
	OAK_ASSERT_EQ((bool)[cls isSubclassOfClass:HOBrowserView.class], true);
	OAK_ASSERT_EQ((bool)[cls isSubclassOfClass:NSView.class],        true);

	for(NSString* name in @[ @"mainFrameTitle", @"commandIdentifier", @"disableJavaScriptAPI" ])
		OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:NSSelectorFromString(name)], true);

	// rule 4: two getters spelled differently from their properties.
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(isRunningCommand)], true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(isReusable)],       true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setReusable:)],     true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(isVisible)],        true);

	// mainFrameTitle and runningCommand are readonly to the outside.
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:NSSelectorFromString(@"setMainFrameTitle:")], false);

	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setContent:)],                                true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(stopLoadingWithUserInteraction:completionHandler:)], true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(printDocument:)],                             true);

	// The C++-typed one. Swift cannot declare a std::map parameter (rule 17), and
	// OakCommand.mm is its only caller and is not moving — so whatever else moves,
	// this selector has to keep an ObjC++ home.
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(loadRequest:environment:autoScrolls:)], true);
}

void test_html_output_view_title_is_bound_to_the_web_view ()
{
	// The window title tracks this through KVO, so the dependency has to survive:
	// lose it and the window keeps whatever title it opened with.
	NSSet* paths = [OakHTMLOutputView keyPathsForValuesAffectingValueForKey:@"mainFrameTitle"];
	OAK_ASSERT_EQ((bool)[paths containsObject:@"webView.title"], true);
}

// ==================================================================
// = What a fresh view answers before anything is loaded            =
// ==================================================================

void test_html_output_view_starts_reusable_and_idle ()
{
	OakHTMLOutputView* view = make_view();

	// **Reusable defaults to YES**, and it is the initialiser that says so rather
	// than the ivar's zero — the whole point is that an output window is recycled
	// for the next command unless something opts out.
	OAK_ASSERT_EQ((bool)view.isReusable, true);

	OAK_ASSERT_EQ((bool)view.isRunningCommand, false);
	OAK_ASSERT_EQ((bool)(view.commandIdentifier == nil), true);
	OAK_ASSERT_EQ((bool)view.disableJavaScriptAPI, false);

	// It builds a web view and a status bar, inherited from HOBrowserView.
	OAK_ASSERT_EQ((bool)(view.webView != nil),   true);
	OAK_ASSERT_EQ((bool)(view.statusBar != nil), true);
}

void test_html_output_view_is_not_visible_without_a_window ()
{
	OakHTMLOutputView* view = make_view();

	// `visible` is driven by -viewDidMoveToWindow, so a detached view is not
	// visible — which is what stops a recycled window being handed a command it
	// would never show.
	OAK_ASSERT_EQ((bool)view.isVisible, false);
}

void test_html_output_view_title_falls_back_to_the_process_name ()
{
	OakHTMLOutputView* view = make_view();

	// With no page title and no request, the empty string — not nil. The window
	// binds to this, and nil would leave the previous title in place.
	OAK_ASSERT_EQ(describe(view.mainFrameTitle), std::string(""));
}

// ==================================================================
// = Stopping when there is nothing to stop                         =
// ==================================================================

void test_html_output_view_stop_answers_immediately_with_no_command ()
{
	OakHTMLOutputView* view = make_view();

	// No initial request means no command to interrupt, so the handler is called
	// **synchronously with YES** — "nothing was running, carry on". The caller
	// closes the window on that answer, so a port that made this asynchronous, or
	// that answered NO, would leave windows open on quit.
	__block int calls   = 0;
	__block BOOL didStop = NO;
	[view stopLoadingWithUserInteraction:YES completionHandler:^(BOOL flag){
		++calls;
		didStop = flag;
	}];

	OAK_ASSERT_EQ((long)calls, (long)1);
	OAK_ASSERT_EQ((bool)didStop, true);
}
