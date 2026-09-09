#import "FindTesting.h"
#import <Cocoa/Cocoa.h>

// Pins for Find's two remaining portable view controllers, written against the
// ObjC++ and before any port of them (rule 18, rule 5, rule 40).
//
// Neither had a test. Between them they are 372 lines, and what they do is not
// the sort of thing a suite notices going wrong: one formats a status line with
// two invisible joiner characters, the other pushes a value backwards through a
// Cocoa binding by hand. Both would keep compiling if a port dropped them.
//
// Deliberately *not* pinned: anything needing a window or a field editor.
// -viewDidAppear installs a firstResponder observer, -control:textView:
// doCommandBySelector: needs a live editor, and -showHistory: needs a
// pasteboard selector panel. Those are the parts a human has to click, and this
// environment cannot bring the app frontmost.
//
// The selector lists spell the **ObjC** names, not the Swift ones. That is rule
// 64: a Swift port renames `getter = isX` properties silently, and the pin only
// catches it if it asks for the selector.

void setup ()
{
	NSApplicationLoad();
}

// The status bar's stack view, in the order -loadView builds it. Asserted rather
// than assumed so a reordering fails here, loudly, instead of silently handing a
// later test the wrong view.
static NSButton* StatusButtonOf (FFStatusBarViewController* controller)
{
	NSStackView* stackView = (NSStackView*)controller.view;
	OAK_ASSERT_EQ((size_t)stackView.views.count, (size_t)3);
	return (NSButton*)stackView.views[2];
}

// MARK: - Selector surface (rule 18)

void test_status_bar_answers_its_public_selectors ()
{
	NSArray<NSString*>* const required = @[
		@"statusText", @"setStatusText:",
		@"alternateStatusText", @"setAlternateStatusText:",
		@"progressIndicatorVisible", @"setProgressIndicatorVisible:",
		@"stopAction", @"setStopAction:",
		@"stopTarget", @"setStopTarget:",
	];

	NSMutableArray* missing = [NSMutableArray array];
	for(NSString* name in required)
	{
		if(![FFStatusBarViewController instancesRespondToSelector:NSSelectorFromString(name)])
			[missing addObject:name];
	}
	OAK_ASSERT_EQ(std::string([missing componentsJoinedByString:@", "].UTF8String), std::string(""));
}

void test_text_field_answers_its_public_selectors ()
{
	NSArray<NSString*>* const required = @[
		@"initWithPasteboard:grammarName:",
		@"showHistory:",
		@"showPopoverWithString:",
		@"stringValue", @"setStringValue:",
		@"hasFocus", @"setHasFocus:",
		@"syntaxHighlightEnabled", @"setSyntaxHighlightEnabled:",
	];

	NSMutableArray* missing = [NSMutableArray array];
	for(NSString* name in required)
	{
		if(![FFTextFieldViewController instancesRespondToSelector:NSSelectorFromString(name)])
			[missing addObject:name];
	}
	OAK_ASSERT_EQ(std::string([missing componentsJoinedByString:@", "].UTF8String), std::string(""));
}

// MARK: - The status line's two joiners

// A search string containing a newline is shown on one line, with the break
// drawn as ¬. Get this wrong and a multi-line search silently renders as a
// single run-together string — legible enough that nobody files it.
void test_status_text_draws_newlines_as_a_not_sign ()
{
	FFStatusBarViewController* controller = [[FFStatusBarViewController alloc] init];
	controller.statusText = @"first\nsecond";

	NSString* shown = StatusButtonOf(controller).attributedTitle.string;
	OAK_ASSERT_EQ(std::string(shown.UTF8String), std::string("first¬second"));
}

// Tabs get their own joiner, and a different one.
void test_status_text_draws_tabs_as_a_triangle ()
{
	FFStatusBarViewController* controller = [[FFStatusBarViewController alloc] init];
	controller.statusText = @"left\tright";

	NSString* shown = StatusButtonOf(controller).attributedTitle.string;
	OAK_ASSERT_EQ(std::string(shown.UTF8String), std::string("left‣right"));
}

// Both at once, because the line walk and the tab walk are nested and a port
// could plausibly flatten them into one pass with the wrong separator.
void test_status_text_draws_lines_and_tabs_together ()
{
	FFStatusBarViewController* controller = [[FFStatusBarViewController alloc] init];
	controller.statusText = @"a\tb\nc\td";

	NSString* shown = StatusButtonOf(controller).attributedTitle.string;
	OAK_ASSERT_EQ(std::string(shown.UTF8String), std::string("a‣b¬c‣d"));
}

// Set before -loadView runs. The ObjC setter writes to an ivar and messages a
// nil button, then the lazy -statusTextButton getter formats the stored value
// when the view is finally built (rule 33). A port that only formats in the
// setter shows an empty status bar, and only for a caller that sets the text
// early — which is every real caller.
void test_status_text_set_before_the_view_loads_still_shows ()
{
	FFStatusBarViewController* controller = [[FFStatusBarViewController alloc] init];
	controller.statusText = @"set first";   // no -view access yet

	NSString* shown = StatusButtonOf(controller).attributedTitle.string;
	OAK_ASSERT_EQ(std::string(shown.UTF8String), std::string("set first"));
}

// -setStatusText: assigns the alternate title as well; -setAlternateStatusText:
// then overrides only the alternate. The order is the whole behaviour: a button
// with no alternate set shows the status text when pressed, not an empty string.
void test_status_text_sets_both_titles_and_the_alternate_overrides_one ()
{
	FFStatusBarViewController* controller = [[FFStatusBarViewController alloc] init];
	NSButton* button = StatusButtonOf(controller);

	controller.statusText = @"regular";
	OAK_ASSERT_EQ(std::string(button.attributedTitle.string.UTF8String),          std::string("regular"));
	OAK_ASSERT_EQ(std::string(button.attributedAlternateTitle.string.UTF8String), std::string("regular"));

	controller.alternateStatusText = @"pressed";
	OAK_ASSERT_EQ(std::string(button.attributedTitle.string.UTF8String),          std::string("regular"));
	OAK_ASSERT_EQ(std::string(button.attributedAlternateTitle.string.UTF8String), std::string("pressed"));
}

// MARK: - Progress

// The stop button and the spinner appear and disappear together, and start
// hidden. A port that forgets one leaves a dead stop button on screen for the
// whole search.
void test_progress_visibility_moves_the_stop_button_and_the_spinner ()
{
	FFStatusBarViewController* controller = [[FFStatusBarViewController alloc] init];
	NSStackView* stackView = (NSStackView*)controller.view;
	NSView* stopButton        = stackView.views[0];
	NSView* progressIndicator = stackView.views[1];

	OAK_ASSERT_EQ((bool)stopButton.isHidden, true);
	OAK_ASSERT_EQ((bool)progressIndicator.isHidden, true);

	controller.progressIndicatorVisible = YES;
	OAK_ASSERT_EQ((bool)stopButton.isHidden, false);
	OAK_ASSERT_EQ((bool)progressIndicator.isHidden, false);

	controller.progressIndicatorVisible = NO;
	OAK_ASSERT_EQ((bool)stopButton.isHidden, true);
	OAK_ASSERT_EQ((bool)progressIndicator.isHidden, true);
}

// MARK: - The text field's hand-written reverse binding

// -setStringValue: pushes the new value back out through the `stringValue`
// binding itself, by reading -infoForBinding: and calling -setValue:forKeyPath:
// on the observed controller. That is not something bindings do on their own for
// a plain property, and it is the reason typing in the find field updates the
// window's model. Silent if a port drops it: the field still displays fine.
void test_string_value_pushes_back_through_its_binding ()
{
	FFTextFieldViewController* controller = [[FFTextFieldViewController alloc] initWithPasteboard:nil grammarName:@"text.plain"];
	(void)controller.view; // build the text field

	NSObjectController* objectController = [[NSObjectController alloc] initWithContent:[NSMutableDictionary dictionary]];
	[controller bind:@"stringValue" toObject:objectController withKeyPath:@"content.text" options:nil];

	controller.stringValue = @"pushed";

	NSString* propagated = [objectController valueForKeyPath:@"content.text"];
	OAK_ASSERT(propagated != nil);
	OAK_ASSERT_EQ(std::string(propagated.UTF8String), std::string("pushed"));

	[controller unbind:@"stringValue"];
}

void test_string_value_round_trips ()
{
	FFTextFieldViewController* controller = [[FFTextFieldViewController alloc] initWithPasteboard:nil grammarName:@"text.plain"];
	(void)controller.view;

	controller.stringValue = @"needle";
	OAK_ASSERT_EQ(std::string(controller.stringValue.UTF8String), std::string("needle"));
}

// The two flags the Find window drives. Plain round trips, but both have
// side-effecting setters that a port could accidentally make no-ops.
void test_flags_round_trip ()
{
	FFTextFieldViewController* controller = [[FFTextFieldViewController alloc] initWithPasteboard:nil grammarName:@"text.plain"];
	(void)controller.view;

	OAK_ASSERT_EQ((bool)controller.syntaxHighlightEnabled, false);
	controller.syntaxHighlightEnabled = YES;
	OAK_ASSERT_EQ((bool)controller.syntaxHighlightEnabled, true);

	OAK_ASSERT_EQ((bool)controller.hasFocus, false);
	controller.hasFocus = YES;
	OAK_ASSERT_EQ((bool)controller.hasFocus, true);
}

// MARK: - The bindings Find installs on the text field controller

// Find.swift binds its results controller to *both* of these:
//
//     resultsViewController.bind("replaceString",           to: replaceTextFieldViewController, withKeyPath: "stringValue")
//     resultsViewController.bind("showReplacementPreviews", to: replaceTextFieldViewController, withKeyPath: "hasFocus")
//
// so both have to stay KVO-compliant. If a port leaves them without the `dynamic`
// KVO needs, nothing fails to compile and no other test notices — the replace
// preview simply stops following the field. That is rule 64's failure mode, and
// it is why these are pinned through Cocoa Bindings rather than as round trips.

void test_has_focus_drives_a_cocoa_binding ()
{
	FFTextFieldViewController* controller = [[FFTextFieldViewController alloc] initWithPasteboard:nil grammarName:@"text.plain"];
	(void)controller.view;

	NSButton* button = [NSButton buttonWithTitle:@"x" target:nil action:NULL];
	[button bind:NSEnabledBinding toObject:controller withKeyPath:@"hasFocus" options:nil];

	controller.hasFocus = YES;
	OAK_ASSERT_EQ((bool)button.enabled, true);

	controller.hasFocus = NO;
	OAK_ASSERT_EQ((bool)button.enabled, false);

	[button unbind:NSEnabledBinding];
}

void test_string_value_drives_a_cocoa_binding ()
{
	FFTextFieldViewController* controller = [[FFTextFieldViewController alloc] initWithPasteboard:nil grammarName:@"text.plain"];
	(void)controller.view;

	NSTextField* mirror = [NSTextField labelWithString:@""];
	[mirror bind:NSValueBinding toObject:controller withKeyPath:@"stringValue" options:nil];

	controller.stringValue = @"needle";
	OAK_ASSERT_EQ(std::string(mirror.stringValue.UTF8String), std::string("needle"));

	[mirror unbind:NSValueBinding];
}
