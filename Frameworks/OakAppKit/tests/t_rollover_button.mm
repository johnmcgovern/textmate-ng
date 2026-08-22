#import "OakAppKitTesting.h"

// Coverage for OakRolloverButton, written against the ObjC++ *before* the port,
// the order every port in this project since Find has used.
//
// This class is a six-entry image table and two booleans, which is exactly the
// shape that a port gets subtly wrong without failing to compile: `updateImage`
// substitutes into locals and then falls back through the *already substituted*
// value twice, so two of the eight combinations do not read the way the property
// names suggest. Both are pinned below, and both are called out where they sit.

void setup ()
{
	// The button reads [self.window mouseLocationOutsideOfEventStream] on every
	// -setHidden:/-updateTrackingAreas, and one test puts it in a real window.
	NSApplicationLoad();
}

// A label carried on the image itself, so a failure reads
// "regular" != "rollover" rather than comparing two pointers.
static NSImage* labelled_image (char const* label)
{
	NSImage* image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
	image.accessibilityDescription = @(label);
	return image;
}

static std::string label_of (NSImage* image)
{
	return image ? std::string(image.accessibilityDescription.UTF8String) : std::string("«nil»");
}

// The frame origin is deliberately not (0, 0), which turns out to change nothing
// at all — see test_rollover_button_hiding_clears_mouse_inside for why a
// window-less button's hit test ignores it. Kept off the origin anyway so the
// bounds/frame distinction is visible in the source.
static NSEvent* dummy_mouse_event ()
{
	// A real event, not nil. The ObjC++ ignores the argument entirely, but a Swift
	// override takes a non-optional NSEvent — a test built on nil would either trap
	// or quietly stop exercising the override after the port.
	return [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1];
}

static OakRolloverButton* make_button ()
{
	return [[OakRolloverButton alloc] initWithFrame:NSMakeRect(50, 50, 20, 20)];
}

static void set_all_six_images (OakRolloverButton* button)
{
	button.regularImage          = labelled_image("regular");
	button.pressedImage          = labelled_image("pressed");
	button.rolloverImage         = labelled_image("rollover");
	button.inactiveRegularImage  = labelled_image("inactiveRegular");
	button.inactivePressedImage  = labelled_image("inactivePressed");
	button.inactiveRolloverImage = labelled_image("inactiveRollover");
}

// ==================================================================
// = The selector surface a Swift port has to keep reachable        =
// ==================================================================

void test_rollover_button_selector_surface ()
{
	Class cls = OakRolloverButton.class;

	// The six image properties, both halves of each.
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(regularImage)],             true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setRegularImage:)],         true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(pressedImage)],             true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setPressedImage:)],         true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(rolloverImage)],            true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setRolloverImage:)],        true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(inactiveRegularImage)],     true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setInactiveRegularImage:)], true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(inactivePressedImage)],     true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setInactivePressedImage:)], true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(inactiveRolloverImage)],    true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setInactiveRolloverImage:)],true);

	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(disableWindowOrderingForFirstMouse)],    true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setDisableWindowOrderingForFirstMouse:)],true);

	// The AppKit overrides. Every one of these is inherited, so
	// -respondsToSelector: alone would pass against an empty subclass; what
	// matters is that the port keeps *overriding* them, which the behavioural
	// tests below are what actually check. Listed here so the surface is in one
	// place.
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(shouldDelayWindowOrderingForEvent:)], true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(menuForEvent:)],                      true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(mouseDown:)],                         true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setHidden:)],                         true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(viewWillMoveToWindow:)],              true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(updateTrackingAreas)],                true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(mouseEntered:)],                      true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(mouseExited:)],                       true);

	// And the class is an NSButton, not merely an NSView — OakCreateCloseButton
	// hands it to callers that set .target/.action.
	OAK_ASSERT_EQ((bool)[cls isSubclassOfClass:NSButton.class], true);
}

// The notification *names* are the strings, not the symbols. Swift renames the
// symbol on import (…MouseDidEnterNotification → .OakRolloverButtonMouseDidEnter,
// rule 28), so a port can keep every call site compiling while changing the value
// underneath and silently unsubscribing every observer.
void test_rollover_button_notification_name_values ()
{
	OAK_ASSERT_EQ((bool)[OakRolloverButtonMouseDidEnterNotification isEqualToString:@"OakRolloverButtonMouseDidEnterNotification"], true);
	OAK_ASSERT_EQ((bool)[OakRolloverButtonMouseDidLeaveNotification isEqualToString:@"OakRolloverButtonMouseDidLeaveNotification"], true);
}

// ==================================================================
// = What -initWithFrame: configures                                =
// ==================================================================

void test_rollover_button_initial_configuration ()
{
	OakRolloverButton* button = make_button();

	OAK_ASSERT_EQ((bool)button.isBordered, false);

	// NSButton has no -buttonType getter; the type is stored on the cell as the
	// highlight/state masks. NSButtonTypeMomentaryChange is "swap the image while
	// held, carry no state", which is why the class only ever sets .image and
	// .alternateImage and never touches .state.
	OAK_ASSERT_EQ((NSUInteger)((NSButtonCell*)button.cell).highlightsBy, (NSUInteger)NSContentsCellMask);
	OAK_ASSERT_EQ((NSUInteger)((NSButtonCell*)button.cell).showsStateBy, (NSUInteger)NSNoCellMask);

	// All four of these are set to Required so the button never stretches or
	// squeezes in the stack views that hold it — dropping one is invisible until
	// a tab bar gets crowded.
	OAK_ASSERT_EQ((double)[button contentCompressionResistancePriorityForOrientation:NSLayoutConstraintOrientationHorizontal], (double)NSLayoutPriorityRequired);
	OAK_ASSERT_EQ((double)[button contentCompressionResistancePriorityForOrientation:NSLayoutConstraintOrientationVertical],   (double)NSLayoutPriorityRequired);
	OAK_ASSERT_EQ((double)[button contentHuggingPriorityForOrientation:NSLayoutConstraintOrientationHorizontal],              (double)NSLayoutPriorityRequired);
	OAK_ASSERT_EQ((double)[button contentHuggingPriorityForOrientation:NSLayoutConstraintOrientationVertical],                (double)NSLayoutPriorityRequired);
}

// ==================================================================
// = The image table: six slots, two outputs                        =
// ==================================================================

void test_rollover_button_image_table_with_all_six_set ()
{
	OakRolloverButton* button = make_button();
	set_all_six_images(button);

	button.active      = YES;
	button.mouseInside = NO;
	OAK_ASSERT_EQ(label_of(button.image),          std::string("regular"));
	OAK_ASSERT_EQ(label_of(button.alternateImage), std::string("pressed"));

	button.mouseInside = YES;
	OAK_ASSERT_EQ(label_of(button.image),          std::string("rollover"));
	OAK_ASSERT_EQ(label_of(button.alternateImage), std::string("pressed"));

	button.active      = NO;
	OAK_ASSERT_EQ(label_of(button.image),          std::string("inactiveRollover"));
	// **Not "inactivePressed".** -updateImage picks the alternate inside an
	// `else if(!_active)` branch that the mouseInside branch has already claimed,
	// so an inactive button under the mouse shows the *active* pressed image. A
	// port that flattens the branches into a table will "fix" this and change
	// what the tab bar's close button looks like while it is being clicked.
	OAK_ASSERT_EQ(label_of(button.alternateImage), std::string("pressed"));

	button.mouseInside = NO;
	OAK_ASSERT_EQ(label_of(button.image),          std::string("inactiveRegular"));
	OAK_ASSERT_EQ(label_of(button.alternateImage), std::string("inactivePressed"));
}

void test_rollover_button_fallbacks_when_inactive_images_are_missing ()
{
	OakRolloverButton* button = make_button();
	button.regularImage  = labelled_image("regular");
	button.pressedImage  = labelled_image("pressed");
	button.rolloverImage = labelled_image("rollover");

	button.active      = NO;
	button.mouseInside = NO;
	OAK_ASSERT_EQ(label_of(button.image), std::string("regular"));
	// **Not "pressed".** The fallback is written `inactivePressed ?: image`, and
	// `image` has already been reassigned to the regular image on the line above
	// — so with no inactive artwork the alternate is the *regular* image, and the
	// button stops visibly reacting to a click. This is the one that reads wrong
	// in the source and is right in the shipped app: the close button in an
	// inactive window is deliberately inert-looking.
	OAK_ASSERT_EQ(label_of(button.alternateImage), std::string("regular"));

	button.mouseInside = YES;
	// Two fallbacks chained: rollover substitutes for regular, then
	// inactiveRollover is absent so the rollover image stands.
	OAK_ASSERT_EQ(label_of(button.image),          std::string("rollover"));
	OAK_ASSERT_EQ(label_of(button.alternateImage), std::string("pressed"));
}

void test_rollover_button_image_properties_round_trip ()
{
	OakRolloverButton* button = make_button();
	set_all_six_images(button);

	OAK_ASSERT_EQ(label_of(button.regularImage),          std::string("regular"));
	OAK_ASSERT_EQ(label_of(button.pressedImage),          std::string("pressed"));
	OAK_ASSERT_EQ(label_of(button.rolloverImage),         std::string("rollover"));
	OAK_ASSERT_EQ(label_of(button.inactiveRegularImage),  std::string("inactiveRegular"));
	OAK_ASSERT_EQ(label_of(button.inactivePressedImage),  std::string("inactivePressed"));
	OAK_ASSERT_EQ(label_of(button.inactiveRolloverImage), std::string("inactiveRollover"));

	// Six distinct slots, not one property aliased six ways.
	OAK_ASSERT_EQ((bool)(button.regularImage == button.inactiveRegularImage), false);

	button.rolloverImage = nil;
	OAK_ASSERT_EQ(label_of(button.rolloverImage), std::string("«nil»"));
}

// ==================================================================
// = mouseInside: the notifications, and who posts them             =
// ==================================================================

void test_rollover_button_posts_on_mouse_inside_transitions ()
{
	OakRolloverButton* button = make_button();

	__block NSUInteger entered = 0, left = 0;
	__block id lastObject = nil;
	id enterToken = [NSNotificationCenter.defaultCenter addObserverForName:OakRolloverButtonMouseDidEnterNotification object:button queue:nil usingBlock:^(NSNotification* note){ ++entered; lastObject = note.object; }];
	id leaveToken = [NSNotificationCenter.defaultCenter addObserverForName:OakRolloverButtonMouseDidLeaveNotification object:button queue:nil usingBlock:^(NSNotification* note){ ++left;    lastObject = note.object; }];

	[button mouseEntered:dummy_mouse_event()];
	OAK_ASSERT_EQ((bool)button.mouseInside, true);
	OAK_ASSERT_EQ((size_t)entered, (size_t)1);
	OAK_ASSERT_EQ((bool)(lastObject == button), true); // posted with object:self, which is what lets one observer serve many buttons

	// Setting the same value again is a no-op — the setter returns before
	// posting. Observers of these notifications drive UI that flickers if the
	// pair is posted spuriously.
	[button mouseEntered:dummy_mouse_event()];
	OAK_ASSERT_EQ((size_t)entered, (size_t)1);

	[button mouseExited:dummy_mouse_event()];
	OAK_ASSERT_EQ((bool)button.mouseInside, false);
	OAK_ASSERT_EQ((size_t)left, (size_t)1);

	[button mouseExited:dummy_mouse_event()];
	OAK_ASSERT_EQ((size_t)left, (size_t)1);

	[NSNotificationCenter.defaultCenter removeObserver:enterToken];
	[NSNotificationCenter.defaultCenter removeObserver:leaveToken];
}

void test_rollover_button_hiding_clears_mouse_inside ()
{
	OakRolloverButton* button = make_button();
	set_all_six_images(button);
	button.active = YES;

	[button mouseEntered:dummy_mouse_event()];
	OAK_ASSERT_EQ((bool)button.mouseInside, true);
	OAK_ASSERT_EQ(label_of(button.image), std::string("rollover"));

	__block NSUInteger left = 0, entered = 0;
	id leaveToken = [NSNotificationCenter.defaultCenter addObserverForName:OakRolloverButtonMouseDidLeaveNotification object:button queue:nil usingBlock:^(NSNotification*){ ++left;    }];
	id enterToken = [NSNotificationCenter.defaultCenter addObserverForName:OakRolloverButtonMouseDidEnterNotification object:button queue:nil usingBlock:^(NSNotification*){ ++entered; }];

	// Hiding always clears it: the recomputation is `!flag && NSMouseInRect(…)`,
	// so the hit test is not even consulted when hiding. Without this the button
	// comes back rolled-over after being hidden under the pointer.
	button.hidden = YES;
	OAK_ASSERT_EQ((bool)button.mouseInside, false);
	OAK_ASSERT_EQ((size_t)left, (size_t)1);
	OAK_ASSERT_EQ(label_of(button.image), std::string("regular"));

	// Unhiding re-runs the hit test, and the hit test says yes.
	//
	// This is not what it looks like, and the first version of this test asserted
	// the opposite and failed — which is the whole reason for writing it before
	// the port. With no window, -mouseLocationOutsideOfEventStream is NSZeroPoint
	// and -convertPoint:fromView:nil has no coordinate space to convert between,
	// so it hands back (0, 0) unchanged rather than offsetting by the frame. The
	// button's bounds always start at (0, 0), so the origin is always inside them
	// and a window-less button always comes back rolled-over.
	//
	// Pinned as it is, not as it ought to be. Nothing ships in this state — real
	// buttons have windows — but a port that "fixes" the conversion changes what
	// -setHidden: does, and this is the assertion that would notice.
	button.hidden = NO;
	OAK_ASSERT_EQ((bool)button.mouseInside, true);
	OAK_ASSERT_EQ((size_t)entered, (size_t)1); // and the re-entry is announced
	OAK_ASSERT_EQ((size_t)left, (size_t)1);

	[NSNotificationCenter.defaultCenter removeObserver:leaveToken];
	[NSNotificationCenter.defaultCenter removeObserver:enterToken];
}

// ==================================================================
// = active: derived from the window, never set by callers          =
// ==================================================================

void test_rollover_button_active_follows_window ()
{
	OakRolloverButton* button = make_button();
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
	[window.contentView addSubview:button];

	// The rule, not the outcome: -viewWillMoveToWindow: sets active from
	// fullscreen-or-main-or-key. Asserting against the window's own state keeps
	// this from depending on whether a test process can take key, which it
	// cannot do reliably.
	bool expected = (window.styleMask & NSWindowStyleMaskFullScreen) || window.isMainWindow || window.isKeyWindow;
	OAK_ASSERT_EQ((bool)button.active, expected);

	[window makeKeyAndOrderFront:nil];
	expected = (window.styleMask & NSWindowStyleMaskFullScreen) || window.isMainWindow || window.isKeyWindow;
	OAK_ASSERT_EQ((bool)button.active, expected);

	// Leaving the window is unambiguous: nil has no style mask and is neither
	// main nor key, so active must drop.
	[button removeFromSuperview];
	OAK_ASSERT_EQ((bool)button.active, false);
	OAK_ASSERT_EQ((bool)(button.window == nil), true);
}

// ==================================================================
// = First-mouse ordering, and the context-menu forward             =
// ==================================================================

void test_rollover_button_delays_window_ordering_only_when_asked ()
{
	OakRolloverButton* button = make_button();

	OAK_ASSERT_EQ((bool)button.disableWindowOrderingForFirstMouse, false);
	OAK_ASSERT_EQ((bool)[button shouldDelayWindowOrderingForEvent:dummy_mouse_event()], false);

	button.disableWindowOrderingForFirstMouse = YES;
	OAK_ASSERT_EQ((bool)[button shouldDelayWindowOrderingForEvent:dummy_mouse_event()], true);
}

void test_rollover_button_forwards_menu_to_superview ()
{
	OakRolloverButton* button = make_button();
	NSView* superview = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
	[superview addSubview:button];

	NSMenu* superviewMenu = [[NSMenu alloc] initWithTitle:@"superview"];
	NSMenu* buttonMenu    = [[NSMenu alloc] initWithTitle:@"button"];
	superview.menu = superviewMenu;
	button.menu    = buttonMenu;

	// Control-clicks are not delivered to the superview by AppKit
	// (rdar://20200363), so the button hands the whole request up rather than
	// answering with its own menu — the tab bar's context menu belongs to the
	// tab, not to the close button sitting on it.
	OAK_ASSERT_EQ((bool)([button menuForEvent:dummy_mouse_event()] == superviewMenu), true);
	OAK_ASSERT_EQ((bool)([button menuForEvent:dummy_mouse_event()] == buttonMenu),    false);
}
