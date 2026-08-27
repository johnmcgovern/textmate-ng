#import "HTMLOutputTesting.h"
#import <ns/ns.h>
#import <Cocoa/Cocoa.h>

// Coverage for HOStatusBar, written before the port. 179 lines, no C++ — the bar
// along the bottom of an HTML output window: back/forward, a status line, and a
// progress indicator that is *two* controls wearing one property.
//
// The thing to understand before reading these tests: **the bar has no state of
// its own.** Every public property reads and writes a subview — statusText is the
// text field's stringValue, progress is the progress indicator's doubleValue,
// canGoBack is the button's isEnabled. A port that adds backing storage would
// pass a naive round-trip test and still be wrong, because the control and the
// property would drift apart.

void setup ()
{
	NSApplicationLoad();
}

static std::string describe (NSString* str)
{
	return str ? to_s(str) : std::string("«nil»");
}

static HOStatusBar* make_bar ()
{
	return [[HOStatusBar alloc] initWithFrame:NSMakeRect(0, 0, 500, 24)];
}

// ==================================================================
// = The surface a Swift port has to keep reachable                 =
// ==================================================================

void test_status_bar_selector_surface ()
{
	Class cls = HOStatusBar.class;

	OAK_ASSERT_EQ((bool)[cls isSubclassOfClass:NSVisualEffectView.class], true);

	for(NSString* name in @[ @"delegate", @"statusText", @"progress", @"canGoBack", @"canGoForward" ])
	{
		OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:NSSelectorFromString(name)], true);
		OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:NSSelectorFromString([NSString stringWithFormat:@"set%@%@:", [name substringToIndex:1].uppercaseString, [name substringFromIndex:1]])], true);
	}

	// rule 4: the getter is isBusy while the property and setter are busy.
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(isBusy)],   true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setBusy:)], true);

	// The two actions the delegate protocol is answered with.
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(goBack:)],    true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(goForward:)], true);
}

void test_status_bar_is_a_titlebar_effect_view ()
{
	HOStatusBar* bar = make_bar();

	OAK_ASSERT_EQ((long)bar.material,     (long)NSVisualEffectMaterialTitlebar);
	OAK_ASSERT_EQ((long)bar.blendingMode, (long)NSVisualEffectBlendingModeWithinWindow);
	OAK_ASSERT_EQ((long)bar.state,        (long)NSVisualEffectStateFollowsWindowActiveState);
	OAK_ASSERT_EQ((bool)bar.wantsLayer, true);
}

// ==================================================================
// = Every property is a facade over a subview                      =
// ==================================================================

void test_status_bar_properties_read_through_to_their_controls ()
{
	HOStatusBar* bar = make_bar();

	// Not round-trips: each assertion names the *control* the value must land on.
	// Storing these in the object instead would satisfy a round-trip and still be
	// a broken port.
	bar.statusText = @"Loading…";
	OAK_ASSERT_EQ(describe(bar.statusTextField.stringValue), std::string("Loading…"));
	OAK_ASSERT_EQ(describe(bar.statusText),                  std::string("Loading…"));

	bar.canGoBack = YES;
	OAK_ASSERT_EQ((bool)bar.goBackButton.isEnabled, true);
	OAK_ASSERT_EQ((bool)bar.canGoBack,              true);

	bar.canGoForward = YES;
	OAK_ASSERT_EQ((bool)bar.goForwardButton.isEnabled, true);
	OAK_ASSERT_EQ((bool)bar.canGoForward,              true);

	bar.canGoBack = NO;
	OAK_ASSERT_EQ((bool)bar.goBackButton.isEnabled, false);
	// Independent controls: turning one off must not touch the other.
	OAK_ASSERT_EQ((bool)bar.canGoForward, true);
}

void test_status_bar_buttons_start_disabled ()
{
	HOStatusBar* bar = make_bar();

	// A fresh output window has no history, and the buttons say so.
	OAK_ASSERT_EQ((bool)bar.canGoBack,    false);
	OAK_ASSERT_EQ((bool)bar.canGoForward, false);

	// The tooltips are the only names these two buttons have — they are image-only.
	OAK_ASSERT_EQ(describe(bar.goBackButton.toolTip),    std::string("Show the previous page"));
	OAK_ASSERT_EQ(describe(bar.goForwardButton.toolTip), std::string("Show the next page"));

	// They target the bar itself, which then forwards to the delegate.
	OAK_ASSERT_EQ((bool)(bar.goBackButton.target == bar), true);
	OAK_ASSERT_EQ((bool)(bar.goBackButton.action == @selector(goBack:)), true);
	OAK_ASSERT_EQ((bool)(bar.goForwardButton.action == @selector(goForward:)), true);
}

// ==================================================================
// = One property, two controls                                     =
// ==================================================================

void test_status_bar_starts_indeterminate_with_only_the_spinner_installed ()
{
	HOStatusBar* bar = make_bar();

	// The bar opens in the spinning state, and **only the spinner is a subview** —
	// the determinate bar is created but deliberately left out of the hierarchy.
	OAK_ASSERT_EQ((bool)bar.indeterminateProgress, true);
	OAK_ASSERT_EQ((bool)(bar.spinner.superview == bar), true);
	OAK_ASSERT_EQ((bool)(bar.progressIndicator.superview == bar), false);
}

void test_status_bar_setting_progress_swaps_the_indicator ()
{
	HOStatusBar* bar = make_bar();

	// **-setProgress: is not just a setter.** Any non-zero value switches the bar
	// from the spinner to the determinate indicator, and zero switches it back.
	// That is how a command that reports progress replaces the spinner, and it is
	// the single most portable-looking line in the file that is not.
	bar.progress = 0.5;
	OAK_ASSERT_EQ((double)bar.progress, (double)0.5);
	OAK_ASSERT_EQ((bool)bar.indeterminateProgress, false);
	OAK_ASSERT_EQ((bool)(bar.progressIndicator.superview == bar), true);
	OAK_ASSERT_EQ((bool)(bar.spinner.superview == bar), false);

	bar.progress = 0;
	OAK_ASSERT_EQ((bool)bar.indeterminateProgress, true);
	OAK_ASSERT_EQ((bool)(bar.spinner.superview == bar), true);
	OAK_ASSERT_EQ((bool)(bar.progressIndicator.superview == bar), false);

	// The value still reads back from the determinate control even while the
	// spinner is the one on screen — the two are not kept in step.
	OAK_ASSERT_EQ((double)bar.progress, (double)0);
}

void test_status_bar_indeterminate_setter_ignores_an_equal_value ()
{
	HOStatusBar* bar = make_bar();

	// The guard matters: without it, setting YES on an already-spinning bar would
	// re-add the spinner and, while busy, restart the animation on every progress
	// report that happened to be zero.
	NSProgressIndicator* spinner = bar.spinner;
	bar.indeterminateProgress = YES;
	OAK_ASSERT_EQ((bool)(bar.spinner == spinner), true);
	OAK_ASSERT_EQ((bool)(bar.spinner.superview == bar), true);
}

void test_status_bar_busy_only_animates_while_indeterminate ()
{
	HOStatusBar* bar = make_bar();

	// -setBusy: drives the spinner only. In the determinate state it records the
	// flag and does nothing visible, because the progress bar shows the value
	// rather than motion.
	bar.busy = YES;
	OAK_ASSERT_EQ((bool)bar.isBusy, true);

	bar.progress = 0.25; // -> determinate
	bar.busy = NO;
	OAK_ASSERT_EQ((bool)bar.isBusy, false);
	OAK_ASSERT_EQ((bool)bar.indeterminateProgress, false);
}

// ==================================================================
// = Layout                                                         =
// ==================================================================

void test_status_bar_constraints_follow_the_installed_indicator ()
{
	HOStatusBar* bar = make_bar();

	[bar updateConstraints];
	NSUInteger indeterminateCount = bar.constraints.count;
	OAK_ASSERT_EQ((bool)(indeterminateCount > 0), true);

	// -updateConstraints removes what it added last time before adding again;
	// running it twice must not accumulate. This is the leak a port loses by
	// forgetting the removeConstraints: at the top.
	[bar updateConstraints];
	OAK_ASSERT_EQ((size_t)bar.constraints.count, (size_t)indeterminateCount);

	// The determinate branch is a different set — the spinner gets a width range
	// and a 6pt bottom inset where the spinning one has neither and sits at 5pt.
	bar.progress = 0.5;
	[bar updateConstraints];
	OAK_ASSERT_EQ((bool)(bar.constraints.count != indeterminateCount), true);
}
