#import <OakAppKit/OakKeyEquivalentView.h>
#import <OakAppKit/OakView.h>
#import <ns/ns.h>
#import <Carbon/Carbon.h>

// OakKeyEquivalentView is the key-equivalent recorder in the Bundle Editor and in
// Preferences → Keyboard: click it, press a chord, and it stores the chord as an
// event string while showing the ⌘-style glyphs. The stored string and the shown
// glyphs are two different representations, and keeping them in step is the whole
// job of this class, so that is what is asserted here.
//
// The displayed text is read back through the accessibility value rather than the
// private displayString property — same value, and it is a shipped interface, so
// a regression here is one a screen-reader user would actually hit.

static OakKeyEquivalentView* new_view ()
{
	OakKeyEquivalentView* res = [[OakKeyEquivalentView alloc] initWithFrame:NSMakeRect(0, 0, 120, 22)];
	// -setRecording:YES otherwise calls PushSymbolicHotKeyMode, which disables
	// every system hot key for as long as the test process lives.
	res.disableGlobalHotkeys = NO;
	return res;
}

// "" means the field shows nothing. The two ways of getting there differ in the
// raw value — cleared reports nil, recording reports an empty string — but both
// read out as no key equivalent, which is what these tests are about.
static std::string displayed (OakKeyEquivalentView* view)
{
	NSString* value = [view accessibilityAttributeValue:NSAccessibilityValueAttribute];
	return value ? to_s(value) : "";
}

static NSEvent* key_event (CGKeyCode keyCode, CGEventFlags flags = 0)
{
	CGEventRef cgEvent = CGEventCreateKeyboardEvent(NULL, keyCode, true);
	CGEventSetFlags(cgEvent, flags);
	NSEvent* res = [NSEvent eventWithCGEvent:cgEvent];
	CFRelease(cgEvent);
	return res;
}

void setup ()
{
	NSApplicationLoad();
}

void test_default_state ()
{
	OakKeyEquivalentView* view = new_view();

	OAK_ASSERT_EQ(view.eventString == nil, true);
	OAK_ASSERT_EQ((bool)view.recording, false);
	OAK_ASSERT_EQ(to_s((NSString*)[view accessibilityAttributeValue:NSAccessibilityRoleAttribute]), to_s(NSAccessibilityTextFieldRole));
	OAK_ASSERT_EQ(to_s((NSString*)[view accessibilityAttributeValue:NSAccessibilityDescriptionAttribute]), "Key Equivalent");
	OAK_ASSERT_EQ((bool)[view accessibilityIsIgnored], false);
}

// The stored event string stays in TextMate's notation; only the display is
// translated to glyphs. A binding round-trips through a plist as "@a", so the two
// must not be conflated.
void test_event_string_is_shown_as_glyphs ()
{
	OakKeyEquivalentView* view = new_view();

	view.eventString = @"@a";
	OAK_ASSERT_EQ(to_s(view.eventString), "@a");
	OAK_ASSERT_EQ(displayed(view), "⌘A");

	view.eventString = @"^~$@a";
	OAK_ASSERT_EQ(displayed(view), "⌃⌥⇧⌘a");

	view.eventString = @"@A";
	OAK_ASSERT_EQ(displayed(view), "⇧⌘A");
}

// value/setValue: are what Cocoa bindings drive the control through, so they must
// be the event string and not the glyphs.
void test_value_is_the_event_string ()
{
	OakKeyEquivalentView* view = new_view();

	[view setValue:@"@s"];
	OAK_ASSERT_EQ(to_s(view.eventString), "@s");
	OAK_ASSERT_EQ(to_s((NSString*)[view value]), "@s");
	OAK_ASSERT_EQ(displayed(view), "⌘S");
}

// While recording, the field shows a placeholder rather than the old chord — and
// reports itself as empty to accessibility, so it is not read out as "…".
void test_recording_shows_placeholder ()
{
	OakKeyEquivalentView* view = new_view();
	view.eventString = @"@a";

	view.recording = YES;
	OAK_ASSERT_EQ(displayed(view), "");
	OAK_ASSERT_EQ([[view accessibilityAttributeValue:NSAccessibilityNumberOfCharactersAttribute] integerValue], 0);
	// Recording does not clear what is already stored — abandoning the recording
	// has to leave the old chord in place.
	OAK_ASSERT_EQ(to_s(view.eventString), "@a");

	view.recording = NO;
	OAK_ASSERT_EQ(displayed(view), "⌘A");
}

// ⌫, ⌦ and ⎋ remove the binding rather than being recorded as one.
void test_clear_keys_clear_the_binding ()
{
	CGKeyCode const clearKeys[] = { kVK_Delete, kVK_ForwardDelete, kVK_Escape };
	for(CGKeyCode keyCode : clearKeys)
	{
		OakKeyEquivalentView* view = new_view();
		view.eventString = @"@a";

		[view keyDown:key_event(keyCode)];
		OAK_ASSERT_EQ(view.eventString == nil, true);
		OAK_ASSERT_EQ(displayed(view), "");
		OAK_ASSERT_EQ((bool)view.recording, false);
	}
}

// With nothing stored there is nothing to clear, so a clear key must not be
// swallowed — it falls through to the next responder instead.
void test_clear_key_with_no_binding_is_not_swallowed ()
{
	OakKeyEquivalentView* view = new_view();
	NSView* container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
	[container addSubview:view];

	[view keyDown:key_event(kVK_Delete)];
	OAK_ASSERT_EQ(view.eventString == nil, true);
	OAK_ASSERT_EQ((bool)view.recording, false);
}

void test_space_starts_recording ()
{
	OakKeyEquivalentView* view = new_view();
	view.eventString = @"@a";

	[view keyDown:key_event(kVK_Space)];
	OAK_ASSERT_EQ((bool)view.recording, true);
	OAK_ASSERT_EQ(displayed(view), "");

	view.recording = NO;
}

// Losing focus has to stop recording, or the local event monitor keeps eating key
// presses meant for whatever the user moved on to.
void test_losing_focus_stops_recording ()
{
	OakKeyEquivalentView* view = new_view();

	view.keyState = OakViewViewIsFirstResponderMask|OakViewWindowIsKeyMask|OakViewApplicationIsActiveMask;
	view.recording = YES;
	OAK_ASSERT_EQ((bool)view.recording, true);

	view.keyState = OakViewWindowIsKeyMask|OakViewApplicationIsActiveMask;   // no longer first responder
	OAK_ASSERT_EQ((bool)view.recording, false);
}

// Assigning the value it already holds must not churn the display — the setter
// short-circuits, and the bindings round-trip depends on that.
void test_setting_same_value_is_a_noop ()
{
	OakKeyEquivalentView* view = new_view();

	view.eventString = @"@a";
	OAK_ASSERT_EQ(displayed(view), "⌘A");
	view.eventString = [NSString stringWithFormat:@"%@%@", @"@", @"a"];   // equal, not identical
	OAK_ASSERT_EQ(to_s(view.eventString), "@a");
	OAK_ASSERT_EQ(displayed(view), "⌘A");
}
