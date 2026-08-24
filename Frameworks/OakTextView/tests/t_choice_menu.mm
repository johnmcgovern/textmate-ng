#import "OakTextViewTesting.h"
#import <ns/ns.h>
#import <Cocoa/Cocoa.h>

// Coverage for OakChoiceMenu, written before the port. 252 lines, and the only
// C++ in it is `std::max/min/clamp` and one `static std::map<SEL, NSUInteger>` —
// so this is the rare file that needs **no boundary at all**.
//
// What it does need is a home for five `extern NSUInteger const` in its public
// header (rule 19). Its only consumer is OakTextView.mm, which stays ObjC++, so
// those constants can never come from Swift.
//
// The behaviour worth holding is the keyboard handling: twenty selectors folded
// into ten actions, and a movement rule that has to invent a starting point when
// nothing is selected yet.

void setup ()
{
	NSApplicationLoad();
}

static std::string describe (NSString* str)
{
	return str ? to_s(str) : std::string("«nil»");
}

static std::string describe_index (NSUInteger index)
{
	return index == NSNotFound ? std::string("«NSNotFound»") : oak_format("%zu", (size_t)index);
}

static OakChoiceMenu* make_menu (NSArray* choices)
{
	OakChoiceMenu* menu = [OakChoiceMenu new];
	menu.choices = choices;
	return menu;
}

// The table lives two levels down inside the window's visual-effect view; it is
// not exposed, and reaching it through the view tree avoids having to widen the
// class's surface just to look at it.
static NSTableView* table_of (OakChoiceMenu* menu)
{
	for(NSView* child in menu.window.contentView.subviews)
	{
		if([child isKindOfClass:NSScrollView.class])
			return (NSTableView*)[(NSScrollView*)child documentView];
	}
	return nil;
}

static NSEvent* key_event (NSString* characters, unsigned short keyCode)
{
	return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:keyCode];
}

static NSEvent* arrow_down () { return key_event([NSString stringWithFormat:@"%C", (unichar)NSDownArrowFunctionKey], 125); }
static NSEvent* arrow_up ()   { return key_event([NSString stringWithFormat:@"%C", (unichar)NSUpArrowFunctionKey],   126); }

// ==================================================================
// = The five exported constants                                    =
// ==================================================================

void test_choice_menu_key_constants_are_an_abi ()
{
	// OakTextView.mm compares against these by name, but they are plain
	// NSUIntegers with fixed values and nothing would notice a renumbering.
	OAK_ASSERT_EQ((size_t)OakChoiceMenuKeyUnused,   (size_t)0);
	OAK_ASSERT_EQ((size_t)OakChoiceMenuKeyReturn,   (size_t)1);
	OAK_ASSERT_EQ((size_t)OakChoiceMenuKeyTab,      (size_t)2);
	OAK_ASSERT_EQ((size_t)OakChoiceMenuKeyCancel,   (size_t)3);
	OAK_ASSERT_EQ((size_t)OakChoiceMenuKeyMovement, (size_t)4);
}

// ==================================================================
// = The window it builds                                           =
// ==================================================================

void test_choice_menu_window_is_a_borderless_child_panel ()
{
	OakChoiceMenu* menu = [OakChoiceMenu new];
	NSWindow* window = menu.window;

	// It hangs off the text view as a child window and must never take events —
	// the keystrokes are forwarded to it by OakTextView, not delivered to it.
	OAK_ASSERT_EQ((bool)[window isKindOfClass:NSPanel.class], true);
	OAK_ASSERT_EQ((bool)(window.styleMask == NSWindowStyleMaskBorderless), true);
	OAK_ASSERT_EQ((bool)window.ignoresMouseEvents, true);
	OAK_ASSERT_EQ((bool)window.hasShadow, true);
	OAK_ASSERT_EQ((long)window.level, (long)NSStatusWindowLevel);
}

void test_choice_menu_uses_a_menu_material_effect_view ()
{
	OakChoiceMenu* menu = [OakChoiceMenu new];

	NSVisualEffectView* effectView = (NSVisualEffectView*)menu.window.contentView;
	OAK_ASSERT_EQ((bool)[effectView isKindOfClass:NSVisualEffectView.class], true);
	// Menu material behind the window is what makes it look like a completion
	// pop-up rather than a plain panel.
	OAK_ASSERT_EQ((long)effectView.material,     (long)NSVisualEffectMaterialMenu);
	OAK_ASSERT_EQ((long)effectView.blendingMode, (long)NSVisualEffectBlendingModeBehindWindow);
}

void test_choice_menu_table_is_configured_for_display_only ()
{
	OakChoiceMenu* menu = [OakChoiceMenu new];
	NSTableView* table = table_of(menu);
	OAK_ASSERT_EQ((bool)(table != nil), true);

	OAK_ASSERT_EQ((bool)(table.headerView == nil), true);
	OAK_ASSERT_EQ((long)table.focusRingType, (long)NSFocusRingTypeNone);
	OAK_ASSERT_EQ((bool)[table.backgroundColor isEqual:NSColor.clearColor], true);
	OAK_ASSERT_EQ((size_t)table.tableColumns.count, (size_t)1);
	OAK_ASSERT_EQ(describe(table.tableColumns.firstObject.identifier), std::string("mainColumn"));
}

// ==================================================================
// = choices and the selection it tries to keep                     =
// ==================================================================

void test_choice_menu_starts_empty_with_no_selection ()
{
	OakChoiceMenu* menu = [OakChoiceMenu new];

	OAK_ASSERT_EQ((size_t)menu.choices.count, (size_t)0);
	OAK_ASSERT_EQ(describe_index(menu.choiceIndex), std::string("«NSNotFound»"));
	OAK_ASSERT_EQ(describe(menu.selectedChoice), std::string("«nil»"));
}

void test_choice_menu_keeps_the_selection_by_value_not_by_index ()
{
	OakChoiceMenu* menu = make_menu(@[ @"alpha", @"beta", @"gamma" ]);
	menu.choiceIndex = 2; // gamma
	OAK_ASSERT_EQ(describe(menu.selectedChoice), std::string("gamma"));

	// A new list that still contains the selected *string* keeps it selected,
	// at whatever index it now sits — this is what makes the completion menu
	// stable while the user keeps typing.
	menu.choices = @[ @"gamma", @"delta" ];
	OAK_ASSERT_EQ(describe_index(menu.choiceIndex), std::string("0"));
	OAK_ASSERT_EQ(describe(menu.selectedChoice), std::string("gamma"));

	// And a list that does not contain it drops the selection rather than
	// clamping to a neighbour.
	menu.choices = @[ @"epsilon" ];
	OAK_ASSERT_EQ(describe_index(menu.choiceIndex), std::string("«NSNotFound»"));
}

void test_choice_menu_ignores_an_equal_list ()
{
	OakChoiceMenu* menu = make_menu(@[ @"alpha", @"beta" ]);
	menu.choiceIndex = 1;

	// Equal by value, not identical: the setter returns before touching the
	// selection, so re-supplying the same completions does not reset the user's
	// place in them.
	menu.choices = @[ @"alpha", @"beta" ];
	OAK_ASSERT_EQ(describe_index(menu.choiceIndex), std::string("1"));
}

void test_choice_menu_selection_follows_the_index ()
{
	OakChoiceMenu* menu = make_menu(@[ @"alpha", @"beta", @"gamma" ]);
	NSTableView* table = table_of(menu);

	menu.choiceIndex = 1;
	OAK_ASSERT_EQ((long)table.selectedRow, (long)1);

	menu.choiceIndex = NSNotFound;
	OAK_ASSERT_EQ((long)table.selectedRow, (long)-1);
	OAK_ASSERT_EQ(describe(menu.selectedChoice), std::string("«nil»"));
}

// ==================================================================
// = -didHandleKeyEvent:, which is the whole keyboard contract      =
// ==================================================================

void test_choice_menu_ignores_a_key_it_has_no_action_for ()
{
	OakChoiceMenu* menu = make_menu(@[ @"alpha", @"beta" ]);

	// A plain character is not a command, so the menu reports Unused and
	// OakTextView goes on to insert it.
	OAK_ASSERT_EQ((size_t)[menu didHandleKeyEvent:key_event(@"x", 7)], (size_t)OakChoiceMenuKeyUnused);
	OAK_ASSERT_EQ(describe_index(menu.choiceIndex), std::string("«NSNotFound»"));
}

void test_choice_menu_first_move_down_selects_the_first_row ()
{
	OakChoiceMenu* menu = make_menu(@[ @"alpha", @"beta", @"gamma" ]);

	// Nothing is selected yet, so the movement seeds from -1 when going down —
	// which is what makes the *first* down-arrow land on row 0 rather than row 1.
	OAK_ASSERT_EQ((size_t)[menu didHandleKeyEvent:arrow_down()], (size_t)OakChoiceMenuKeyMovement);
	OAK_ASSERT_EQ(describe_index(menu.choiceIndex), std::string("0"));

	OAK_ASSERT_EQ((size_t)[menu didHandleKeyEvent:arrow_down()], (size_t)OakChoiceMenuKeyMovement);
	OAK_ASSERT_EQ(describe_index(menu.choiceIndex), std::string("1"));
}

void test_choice_menu_first_move_up_selects_the_last_row ()
{
	OakChoiceMenu* menu = make_menu(@[ @"alpha", @"beta", @"gamma" ]);

	// The mirror image, and the reason the seed is a conditional rather than a
	// constant: going up from nothing seeds at count, so the first up-arrow lands
	// on the last row.
	OAK_ASSERT_EQ((size_t)[menu didHandleKeyEvent:arrow_up()], (size_t)OakChoiceMenuKeyMovement);
	OAK_ASSERT_EQ(describe_index(menu.choiceIndex), std::string("2"));
}

void test_choice_menu_movement_clamps_rather_than_wrapping ()
{
	OakChoiceMenu* menu = make_menu(@[ @"alpha", @"beta" ]);

	menu.choiceIndex = 1;
	[menu didHandleKeyEvent:arrow_down()];
	OAK_ASSERT_EQ(describe_index(menu.choiceIndex), std::string("1")); // stays at the end

	menu.choiceIndex = 0;
	[menu didHandleKeyEvent:arrow_up()];
	OAK_ASSERT_EQ(describe_index(menu.choiceIndex), std::string("0")); // stays at the start
}

// ==================================================================
// = -doCommandBySelector:, and why it is not testable on its own   =
// ==================================================================

void test_choice_menu_do_command_by_selector_does_nothing_on_its_own ()
{
	OakChoiceMenu* menu = make_menu(@[ @"a", @"b", @"c", @"d", @"e" ]);
	menu.choiceIndex = 2;

	// -doCommandBySelector: only records an action in a field, and
	// -didHandleKeyEvent: **resets that field before interpreting the event**. So
	// priming a command and then sending an unrelated keystroke discards the
	// primed one entirely — the down-arrow below moves by one, it does not jump.
	//
	// This is pinned because it is the difference between a port that keeps the
	// two-step shape and one that "simplifies" -doCommandBySelector: into acting
	// directly, which would make every primed command fire twice.
	[menu doCommandBySelector:@selector(moveToEndOfDocument:)];
	OAK_ASSERT_EQ((size_t)[menu didHandleKeyEvent:arrow_down()], (size_t)OakChoiceMenuKeyMovement);
	OAK_ASSERT_EQ(describe_index(menu.choiceIndex), std::string("3"));
}

// The mapping is therefore only observable end-to-end, through real keystrokes.
static std::string result_of (OakChoiceMenu* menu, NSEvent* event)
{
	NSUInteger res = [menu didHandleKeyEvent:event];
	if(res == OakChoiceMenuKeyUnused)   return "Unused";
	if(res == OakChoiceMenuKeyReturn)   return "Return";
	if(res == OakChoiceMenuKeyTab)      return "Tab";
	if(res == OakChoiceMenuKeyCancel)   return "Cancel";
	if(res == OakChoiceMenuKeyMovement) return "Movement";
	return "«unknown»";
}

static NSEvent* function_key (unichar key, unsigned short keyCode)
{
	return key_event([NSString stringWithFormat:@"%C", key], keyCode);
}

void test_choice_menu_accept_and_cancel_keys ()
{
	OakChoiceMenu* menu = make_menu(@[ @"a", @"b" ]);

	// The three that end the menu rather than moving in it. OakTextView branches
	// on exactly these, and Tab is distinct from Return because it completes
	// without inserting a newline.
	OAK_ASSERT_EQ(result_of(menu, key_event(@"\r", 36)),   std::string("Return"));
	OAK_ASSERT_EQ(result_of(menu, key_event(@"\t", 48)),   std::string("Tab"));
	OAK_ASSERT_EQ(result_of(menu, key_event(@"\033", 53)), std::string("Cancel"));
}

void test_choice_menu_page_and_document_keys_move ()
{
	OakChoiceMenu* menu = make_menu(@[ @"a", @"b", @"c", @"d", @"e" ]);
	menu.choiceIndex = 2;

	// End jumps to the last row. The offset for beginning/end is INT_MAX >> 1
	// rather than the list length, so it is the clamp that turns it into a jump —
	// a port using the count instead would be right here and wrong for a list
	// longer than the offset.
	OAK_ASSERT_EQ(result_of(menu, function_key(NSEndFunctionKey, 119)), std::string("Movement"));
	OAK_ASSERT_EQ(describe_index(menu.choiceIndex), std::string("4"));

	OAK_ASSERT_EQ(result_of(menu, function_key(NSHomeFunctionKey, 115)), std::string("Movement"));
	OAK_ASSERT_EQ(describe_index(menu.choiceIndex), std::string("0"));

	// Page keys are a movement too, whatever distance they end up covering — the
	// menu is not on screen here, so the visible-row count is not meaningful.
	OAK_ASSERT_EQ(result_of(menu, function_key(NSPageDownFunctionKey, 121)), std::string("Movement"));
	OAK_ASSERT_EQ(result_of(menu, function_key(NSPageUpFunctionKey, 116)),   std::string("Movement"));
}

void test_choice_menu_shift_arrow_moves_like_a_plain_arrow ()
{
	OakChoiceMenu* menu = make_menu(@[ @"a", @"b", @"c" ]);
	menu.choiceIndex = 0;

	// Shift-down arrives as -moveDownAndModifySelection:, because the text view
	// still owns the selection while the completion menu is up. The menu maps the
	// twin to the same action — dropping those aliases would make shift-arrow do
	// nothing while the menu is showing.
	NSEvent* shiftDown = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagShift timestamp:0 windowNumber:0 context:nil characters:[NSString stringWithFormat:@"%C", (unichar)NSDownArrowFunctionKey] charactersIgnoringModifiers:[NSString stringWithFormat:@"%C", (unichar)NSDownArrowFunctionKey] isARepeat:NO keyCode:125];

	OAK_ASSERT_EQ(result_of(menu, shiftDown), std::string("Movement"));
	OAK_ASSERT_EQ(describe_index(menu.choiceIndex), std::string("1"));
}
