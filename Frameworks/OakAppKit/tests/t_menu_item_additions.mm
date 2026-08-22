#import "OakAppKitTesting.h"
#import "../src/NSMenuItem Additions.h"
#import "../src/NSMenuItemCxx.h"
#import <ns/ns.h> // to_s(NSString*)
#import <Cocoa/Cocoa.h>

// Coverage for NSMenuItem (FileIcon), written against the ObjC++ *before* the
// port. Seven methods, and three of them do something other than what their name
// suggests:
//
//   * -setActivationString:withFont: sets -attributedTitle and then puts the
//     plain -title back, because a menu item's title is its identity;
//   * -setDynamicTitle: does *not* change the title when the user has assigned a
//     key equivalent — it moves the requested text into -attributedTitle and
//     leaves -title alone, for the same reason;
//   * -setKeyEquivalentCxxString:'s modifier loop stops one character early, so a
//     one-character string is never a modifier.
//
// The last of those is the only remaining C++-typed selector with ObjC++ callers
// (AppController Menus, OTVStatusBar, OakTextView), so it is the one that has to
// keep working from both sides of the port.

static NSMenuItem* make_item (NSString* title)
{
	NSMenu* menu = [[NSMenu alloc] initWithTitle:@"test"];
	return [menu addItemWithTitle:title action:NULL keyEquivalent:@""];
}

static std::string describe (NSString* str)
{
	return str ? to_s(str) : std::string("«nil»");
}

// The visible text of the item's attributed title, with the newline the
// two-column layout appends turned into a marker so it shows up in a failure.
static std::string attributed_text (NSMenuItem* item)
{
	if(!item.attributedTitle)
		return "«nil»";
	return to_s([item.attributedTitle.string stringByReplacingOccurrencesOfString:@"\n" withString:@"⏎"]);
}

// ==================================================================
// = The surface a Swift port has to keep reachable                 =
// ==================================================================

void test_menu_item_additions_selector_surface ()
{
	Class cls = NSMenuItem.class;

	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(updateTitle:)],                       true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setIconForFile:)],                    true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setActivationString:withFont:)],      true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setInactiveKeyEquivalent:)],          true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setTabTrigger:)],                     true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setModifiedState:)],                  true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setDynamicTitle:)],                   true);

	// The three C++-typed ones. Swift cannot declare a method taking a
	// std::string const& at all (rule 17), so whatever happens to the rest of
	// this category, these have to keep an ObjC++ home.
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setKeyEquivalentCxxString:)],         true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setInactiveKeyEquivalentCxxString:)], true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setTabTriggerCxxString:)],            true);
}

// ==================================================================
// = -setKeyEquivalentCxxString:                                    =
// ==================================================================

void test_menu_item_key_equivalent_parses_modifier_prefixes ()
{
	NSMenuItem* item = make_item(@"Save");

	[item setKeyEquivalentCxxString:"@s"];
	OAK_ASSERT_EQ(describe(item.keyEquivalent), std::string("s"));
	OAK_ASSERT_EQ((size_t)item.keyEquivalentModifierMask, (size_t)NSEventModifierFlagCommand);

	[item setKeyEquivalentCxxString:"$^~@#x"];
	OAK_ASSERT_EQ(describe(item.keyEquivalent), std::string("x"));
	OAK_ASSERT_EQ((size_t)item.keyEquivalentModifierMask, (size_t)(NSEventModifierFlagShift|NSEventModifierFlagControl|NSEventModifierFlagOption|NSEventModifierFlagCommand|NSEventModifierFlagNumericPad));

	// Order is not significant, and a repeated flag is idempotent.
	[item setKeyEquivalentCxxString:"@@$s"];
	OAK_ASSERT_EQ(describe(item.keyEquivalent), std::string("s"));
	OAK_ASSERT_EQ((size_t)item.keyEquivalentModifierMask, (size_t)(NSEventModifierFlagCommand|NSEventModifierFlagShift));
}

void test_menu_item_key_equivalent_never_consumes_the_last_character ()
{
	NSMenuItem* item = make_item(@"Save");

	// The loop guard is `i+1 >= size`, so the final character is always the key
	// and never a modifier. "@" on its own is the *character* @, unmodified —
	// which is what makes "⌘@" expressible as "@@".
	[item setKeyEquivalentCxxString:"@"];
	OAK_ASSERT_EQ(describe(item.keyEquivalent), std::string("@"));
	OAK_ASSERT_EQ((size_t)item.keyEquivalentModifierMask, (size_t)0);

	[item setKeyEquivalentCxxString:"@@"];
	OAK_ASSERT_EQ(describe(item.keyEquivalent), std::string("@"));
	OAK_ASSERT_EQ((size_t)item.keyEquivalentModifierMask, (size_t)NSEventModifierFlagCommand);
}

void test_menu_item_key_equivalent_clears_on_empty_and_null ()
{
	NSMenuItem* item = make_item(@"Save");
	[item setKeyEquivalentCxxString:"@s"];

	[item setKeyEquivalentCxxString:""];
	OAK_ASSERT_EQ(describe(item.keyEquivalent), std::string(""));
	OAK_ASSERT_EQ((size_t)item.keyEquivalentModifierMask, (size_t)0);

	[item setKeyEquivalentCxxString:"@s"];
	[item setKeyEquivalentCxxString:NULL_STR];
	OAK_ASSERT_EQ(describe(item.keyEquivalent), std::string(""));
	OAK_ASSERT_EQ((size_t)item.keyEquivalentModifierMask, (size_t)0);
}

void test_menu_item_key_equivalent_stops_at_a_non_modifier ()
{
	NSMenuItem* item = make_item(@"Save");

	// A character that is not one of "$^~@#" ends the prefix, and everything from
	// there is the key equivalent — including further modifier characters.
	[item setKeyEquivalentCxxString:"@x@"];
	OAK_ASSERT_EQ(describe(item.keyEquivalent), std::string("x@"));
	OAK_ASSERT_EQ((size_t)item.keyEquivalentModifierMask, (size_t)NSEventModifierFlagCommand);
}

// ==================================================================
// = -setActivationString:withFont:                                 =
// ==================================================================

void test_menu_item_activation_string_preserves_the_plain_title ()
{
	NSMenuItem* item = make_item(@"Toggle Column Selection");

	[item setActivationString:@"⌥" withFont:nil];

	// The title is the item's identity — user key equivalents are keyed by it, and
	// -itemWithTitle: finds items by it — so the method puts it back after
	// setting the attributed one. Losing this line makes menu items unfindable.
	OAK_ASSERT_EQ(describe(item.title), std::string("Toggle Column Selection"));

	// The attributed title is the two-column layout: the title, the newline that
	// forces it to the menu's full width, then the activation string.
	OAK_ASSERT_EQ(attributed_text(item), std::string("Toggle Column Selection⏎⌥"));
}

// ==================================================================
// = Tab triggers and inactive key equivalents                      =
// ==================================================================

void test_menu_item_tab_trigger_renders_with_the_tab_glyph ()
{
	NSMenuItem* item = make_item(@"Insert Method");

	[item setTabTrigger:@"meth"];

	OAK_ASSERT_EQ(describe(item.title), std::string("Insert Method"));
	OAK_ASSERT_EQ(attributed_text(item), std::string("Insert Method⏎ meth⇥"));
}

void test_menu_item_inactive_key_equivalent_renders_as_glyphs ()
{
	NSMenuItem* item = make_item(@"Save");

	// "Inactive" means shown but not bound: the glyphs go in the attributed
	// title, and -keyEquivalent stays empty so the item does not actually fire.
	[item setInactiveKeyEquivalent:@"@s"];

	OAK_ASSERT_EQ(describe(item.keyEquivalent), std::string(""));
	OAK_ASSERT_EQ(attributed_text(item), std::string("Save⏎ ⌘S"));
}

void test_menu_item_nil_tab_trigger_leaves_the_title_alone ()
{
	NSMenuItem* item = make_item(@"Insert Method");

	// nil means NULL_STR, and the guard is `!= NULL_STR` — so the association is
	// recorded but no activation string is drawn. This is how a menu item that
	// *may* gain a trigger later is initialised without flashing one.
	[item setTabTrigger:nil];
	OAK_ASSERT_EQ(attributed_text(item), std::string("«nil»"));
	OAK_ASSERT_EQ(describe(item.title), std::string("Insert Method"));
}

void test_menu_item_update_title_reapplies_the_stored_activation ()
{
	NSMenuItem* item = make_item(@"Insert Method");
	[item setTabTrigger:@"meth"];

	// -updateTitle: is the reason the trigger and the inactive key equivalent are
	// kept as associated objects: changing the title throws the attributed title
	// away, and they have to be redrawn onto the new one.
	[item updateTitle:@"Insert Function"];

	OAK_ASSERT_EQ(describe(item.title), std::string("Insert Function"));
	OAK_ASSERT_EQ(attributed_text(item), std::string("Insert Function⏎ meth⇥"));
}

void test_menu_item_update_title_returns_early_when_unchanged ()
{
	NSMenuItem* item = make_item(@"Insert Method");
	[item setTabTrigger:@"meth"];

	NSAttributedString* before = item.attributedTitle;
	[item updateTitle:@"Insert Method"];

	// Same title, so nothing is rebuilt — the attributed title is the very same
	// object, not an equal one.
	OAK_ASSERT_EQ((bool)(item.attributedTitle == before), true);
}

// ==================================================================
// = The two small ones                                             =
// ==================================================================

void test_menu_item_modified_state_uses_the_mixed_state ()
{
	NSMenuItem* item = make_item(@"Document");

	[item setModifiedState:YES];
	OAK_ASSERT_EQ((long)item.state, (long)NSControlStateValueMixed);
	OAK_ASSERT_EQ((bool)(item.mixedStateImage != nil), true);

	[item setModifiedState:NO];
	OAK_ASSERT_EQ((long)item.state, (long)NSControlStateValueOff);
}

void test_menu_item_dynamic_title_sets_the_title_without_a_user_key_equivalent ()
{
	NSMenuItem* item = make_item(@"New File");

	// With no user key equivalent the whole userKeyEquivalent branch is skipped
	// and this is an ordinary title assignment.
	//
	// The other branch — where the title is deliberately *not* changed and the
	// text goes into -attributedTitle instead — needs an NSUserKeyEquivalents
	// entry to reach, and is **not covered here**: that default is read when the
	// menu is loaded, so a test cannot set it after the fact without writing to
	// the host's defaults for the whole process (rule 53).
	OAK_ASSERT_EQ(describe(item.userKeyEquivalent), std::string(""));

	[item setDynamicTitle:@"New File in “Documents”"];
	OAK_ASSERT_EQ(describe(item.title), std::string("New File in “Documents”"));
}

void test_menu_item_icon_for_file_is_sized_for_a_menu ()
{
	NSMenuItem* item = make_item(@"Open");

	[item setIconForFile:@"/usr/bin/true"]; // exists
	OAK_ASSERT_EQ((bool)(item.image != nil), true);
	OAK_ASSERT_EQ((double)item.image.size.width,  (double)16);
	OAK_ASSERT_EQ((double)item.image.size.height, (double)16);

	// A path that does not exist falls back to the extension...
	[item setIconForFile:@"/nowhere/at/all/file.rb"];
	OAK_ASSERT_EQ((bool)(item.image != nil), true);
	OAK_ASSERT_EQ((double)item.image.size.width, (double)16);

	// ...and a path with neither file nor extension falls back to the generic
	// unknown-object icon rather than leaving the previous image in place.
	[item setIconForFile:@"/nowhere/at/all/file"];
	OAK_ASSERT_EQ((bool)(item.image != nil), true);
	OAK_ASSERT_EQ((double)item.image.size.width, (double)16);
}
