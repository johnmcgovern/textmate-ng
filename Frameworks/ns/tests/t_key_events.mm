#import <ns/ns.h>
#import <text/utf8.h>
#import <Carbon/Carbon.h>

// to_s(NSEvent*) turns a key press into TextMate's event-string notation
// ("@a" = ⌘A). t_event_string.cc covers the pure-string half of that notation
// (normalize/glyphs); this covers the NSEvent -> string direction, which nothing
// else exercises even though every key binding in the app goes through it.
//
// Events are synthesized with CGEventCreateKeyboardEvent rather than captured,
// which is what to_s reads back internally (see string_for in ns.mm), so this
// needs no window, no run loop, and no NSApplication.

static NSEvent* key_event (CGKeyCode keyCode, CGEventFlags flags)
{
	CGEventRef cgEvent = CGEventCreateKeyboardEvent(NULL, keyCode, true);
	CGEventSetFlags(cgEvent, flags);
	NSEvent* res = [NSEvent eventWithCGEvent:cgEvent];
	CFRelease(cgEvent);
	return res;
}

static std::string event_string (CGKeyCode keyCode, CGEventFlags flags = 0, bool preserveNumPadFlag = false)
{
	return to_s(key_event(keyCode, flags), preserveNumPadFlag);
}

// to_s resolves a key code to a character through the *active* keyboard layout,
// so the expectations that name an ASCII key only hold on a US-ANSI layout.
static bool is_ansi_layout ()
{
	return event_string(kVK_ANSI_A) == "a" && event_string(kVK_ANSI_1) == "1";
}

// Function keys carry no layout dependency: the character is the AppKit
// constant regardless of layout, so the modifier flags stay flags.
void test_function_keys ()
{
	OAK_ASSERT_EQ(event_string(kVK_LeftArrow),  utf8::to_s(NSLeftArrowFunctionKey));
	OAK_ASSERT_EQ(event_string(kVK_RightArrow), utf8::to_s(NSRightArrowFunctionKey));
	OAK_ASSERT_EQ(event_string(kVK_UpArrow),    utf8::to_s(NSUpArrowFunctionKey));
	OAK_ASSERT_EQ(event_string(kVK_DownArrow),  utf8::to_s(NSDownArrowFunctionKey));
	OAK_ASSERT_EQ(event_string(kVK_F1),         utf8::to_s(NSF1FunctionKey));
	OAK_ASSERT_EQ(event_string(kVK_Home),       utf8::to_s(NSHomeFunctionKey));
	OAK_ASSERT_EQ(event_string(kVK_PageUp),     utf8::to_s(NSPageUpFunctionKey));

	// The two delete keys, whose AppKit constants read backwards from their
	// labels: the ⌫ key (kVK_Delete) is NSDeleteCharacter, and the ⌦ key
	// (kVK_ForwardDelete) is NSDeleteFunctionKey.
	OAK_ASSERT_EQ(event_string(kVK_Delete),        utf8::to_s(NSDeleteCharacter));
	OAK_ASSERT_EQ(event_string(kVK_ForwardDelete), utf8::to_s(NSDeleteFunctionKey));

	OAK_ASSERT_EQ(event_string(kVK_Return), utf8::to_s(NSCarriageReturnCharacter));
	OAK_ASSERT_EQ(event_string(kVK_Tab),    "\t");
	OAK_ASSERT_EQ(event_string(kVK_Escape), "\e");
	OAK_ASSERT_EQ(event_string(kVK_Space),  " ");
}

void test_modifier_prefixes ()
{
	std::string const left = utf8::to_s(NSLeftArrowFunctionKey);

	OAK_ASSERT_EQ(event_string(kVK_LeftArrow, kCGEventFlagMaskCommand),   "@" + left);
	OAK_ASSERT_EQ(event_string(kVK_LeftArrow, kCGEventFlagMaskShift),     "$" + left);
	OAK_ASSERT_EQ(event_string(kVK_LeftArrow, kCGEventFlagMaskAlternate), "~" + left);
	OAK_ASSERT_EQ(event_string(kVK_LeftArrow, kCGEventFlagMaskControl),   "^" + left);

	// Prefixes are emitted in a fixed order (# ^ ~ $ @), not in the order the
	// flags happen to arrive — the whole point of the notation being canonical.
	OAK_ASSERT_EQ(event_string(kVK_LeftArrow, kCGEventFlagMaskShift|kCGEventFlagMaskCommand), "$@" + left);
	OAK_ASSERT_EQ(event_string(kVK_LeftArrow, kCGEventFlagMaskCommand|kCGEventFlagMaskShift), "$@" + left);
	OAK_ASSERT_EQ(event_string(kVK_LeftArrow, kCGEventFlagMaskControl|kCGEventFlagMaskAlternate|kCGEventFlagMaskShift|kCGEventFlagMaskCommand), "^~$@" + left);

	// Flags outside the five it tracks are dropped.
	OAK_ASSERT_EQ(event_string(kVK_LeftArrow, kCGEventFlagMaskCommand|kCGEventFlagMaskSecondaryFn|kCGEventFlagMaskAlphaShift), "@" + left);
}

// The numeric-pad flag is only preserved on request, and then only for keys whose
// character can actually come from the pad — so ⌤ (keypad enter) never gets a '#'.
void test_numeric_pad_flag ()
{
	OAK_ASSERT_EQ(event_string(kVK_ANSI_Keypad1, kCGEventFlagMaskNumericPad, false), "1");
	OAK_ASSERT_EQ(event_string(kVK_ANSI_Keypad1, kCGEventFlagMaskNumericPad, true),  "#1");
	OAK_ASSERT_EQ(event_string(kVK_ANSI_KeypadEnter, kCGEventFlagMaskNumericPad, true), utf8::to_s(NSEnterCharacter));
}

// Modifiers that change which character the key produces are folded into the
// character instead of surviving as a prefix; ones that do not stay prefixes.
void test_ascii_keys ()
{
	if(!is_ansi_layout())
		return OAK_WARN("skipped: active keyboard layout is not US-ANSI");

	OAK_ASSERT_EQ(event_string(kVK_ANSI_A), "a");
	OAK_ASSERT_EQ(event_string(kVK_ANSI_A, kCGEventFlagMaskShift),   "A");   // shift folded in
	OAK_ASSERT_EQ(event_string(kVK_ANSI_1, kCGEventFlagMaskShift),   "!");   // and for punctuation
	OAK_ASSERT_EQ(event_string(kVK_ANSI_A, kCGEventFlagMaskControl), "^a");  // control never folds
	OAK_ASSERT_EQ(event_string(kVK_ANSI_1, kCGEventFlagMaskControl), "^1");

	// ⌥A produces "å", which is not ASCII, so option stays a prefix and the
	// unmodified character is used.
	OAK_ASSERT_EQ(event_string(kVK_ANSI_A, kCGEventFlagMaskAlternate), "~a");

	OAK_ASSERT_EQ(event_string(kVK_ANSI_A, kCGEventFlagMaskCommand), "@a");
	OAK_ASSERT_EQ(event_string(kVK_ANSI_A, kCGEventFlagMaskCommand|kCGEventFlagMaskAlternate), "~@a");
	// Shift keeps folding in when command is held, so neither of these grows a
	// '$' — they reach it by different routes though: ⇧⌘A is uppercased by the
	// command branch, ⇧⌘1 by the ordinary shifted-character branch.
	OAK_ASSERT_EQ(event_string(kVK_ANSI_A, kCGEventFlagMaskCommand|kCGEventFlagMaskShift), "@A");
	OAK_ASSERT_EQ(event_string(kVK_ANSI_1, kCGEventFlagMaskCommand|kCGEventFlagMaskShift), "@!");
}

// Every event string to_s produces must be a fixed point of normalize_event_string
// — otherwise a binding recorded from a key press would not match the same binding
// written by hand in a bundle.
void test_normalized_output ()
{
	CGEventFlags const flagSets[] = {
		0,
		kCGEventFlagMaskCommand,
		kCGEventFlagMaskShift,
		kCGEventFlagMaskAlternate,
		kCGEventFlagMaskControl,
		kCGEventFlagMaskControl|kCGEventFlagMaskAlternate|kCGEventFlagMaskShift|kCGEventFlagMaskCommand,
	};
	CGKeyCode const keyCodes[] = {
		kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_F1,
		kVK_Delete, kVK_ForwardDelete, kVK_Home, kVK_Tab, kVK_Space,
		kVK_ANSI_A, kVK_ANSI_Z, kVK_ANSI_1, kVK_ANSI_Slash, kVK_ANSI_Period,
	};

	for(CGKeyCode keyCode : keyCodes)
	{
		for(CGEventFlags flags : flagSets)
		{
			std::string const str = event_string(keyCode, flags);
			OAK_ASSERT_NE(str, "");
			OAK_MASSERT_EQ("not normalized: " + str, ns::normalize_event_string(str), str);
			// And it must render to something non-empty for a menu item.
			OAK_MASSERT_NE("no glyphs for: " + str, ns::glyphs_for_event_string(str), std::string(""));
		}
	}
}

// The other direction: building an event string from a key plus AppKit modifier
// flags, which is how bindings arriving from menus and plists are canonicalized.
void test_create_event_string ()
{
	OAK_ASSERT_EQ(ns::create_event_string(@"a", 0), "a");
	OAK_ASSERT_EQ(ns::create_event_string(@"a", NSEventModifierFlagCommand), "@a");
	OAK_ASSERT_EQ(ns::create_event_string(@"a", NSEventModifierFlagCommand|NSEventModifierFlagShift), "$@a");
	OAK_ASSERT_EQ(ns::create_event_string(@"a", NSEventModifierFlagControl|NSEventModifierFlagOption|NSEventModifierFlagShift|NSEventModifierFlagCommand), "^~$@a");
	OAK_ASSERT_EQ(ns::create_event_string(@"1", NSEventModifierFlagNumericPad), "#1");
	// Unrelated flags are ignored rather than mapped to a prefix.
	OAK_ASSERT_EQ(ns::create_event_string(@"a", NSEventModifierFlagCapsLock|NSEventModifierFlagFunction), "a");
}

void test_glyphs_for_flags ()
{
	OAK_ASSERT_EQ(ns::glyphs_for_flags(0), "");
	OAK_ASSERT_EQ(ns::glyphs_for_flags(NSEventModifierFlagCommand), "⌘");
	OAK_ASSERT_EQ(ns::glyphs_for_flags(NSEventModifierFlagOption), "⌥");
	OAK_ASSERT_EQ(ns::glyphs_for_flags(NSEventModifierFlagShift), "⇧");
	OAK_ASSERT_EQ(ns::glyphs_for_flags(NSEventModifierFlagControl), "⌃");
	// Glyph order is ⌃⌥⇧⌘ — Apple's convention, and independent of flag order.
	OAK_ASSERT_EQ(ns::glyphs_for_flags(NSEventModifierFlagCommand|NSEventModifierFlagOption), "⌥⌘");
	OAK_ASSERT_EQ(ns::glyphs_for_flags(NSEventModifierFlagControl|NSEventModifierFlagOption|NSEventModifierFlagShift|NSEventModifierFlagCommand), "⌃⌥⇧⌘");
}
