#import "DocumentWindowTesting.h"

// The Filter Through Command window. Two things in it are worth pinning before
// the port, and both are about state that outlives the window:
//
//  - the output type is written to and read from user defaults, with zero
//    meaning "remove the key", so a round trip has to land where it started;
//  - the Execute button is enabled by a predicate over the command field that
//    treats whitespace as empty.
//
// Everything else is layout. The window is built in code — no nib — so the
// controller stands up in a test process, which is asserted below rather than
// assumed.

static NSString* const kFilterOutputTypeKey = @"filterOutputType";

// Each test starts from a known default, since -init reads the stored value and
// several of these write it.
static OakRunCommandWindowController* FreshController ()
{
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kFilterOutputTypeKey];
	return [OakRunCommandWindowController new];
}

void test_run_command_controller_is_constructible ()
{
	OakRunCommandWindowController* controller = FreshController();
	OAK_ASSERT(controller != nil);
	OAK_ASSERT(controller.window != nil);
}

// With no stored preference the output type is replace-input, which is both the
// C++ default and what an absent key means.
void test_output_type_defaults_to_replace_input ()
{
	OakRunCommandWindowController* controller = FreshController();
	OAK_ASSERT_EQ((NSInteger)controller.outputType, (NSInteger)DWOutputTypeReplaceInput);
}

// The round trip that matters: set it, and a controller built afterwards reads
// the same value back. This is the behaviour the DWOutputType/output::type
// pinning exists to protect.
void test_output_type_survives_a_round_trip_through_user_defaults ()
{
	OakRunCommandWindowController* first = FreshController();
	first.outputType = DWOutputTypeNewWindow;

	OAK_ASSERT_EQ([NSUserDefaults.standardUserDefaults integerForKey:kFilterOutputTypeKey], (NSInteger)DWOutputTypeNewWindow);

	OakRunCommandWindowController* second = [OakRunCommandWindowController new];
	OAK_ASSERT_EQ((NSInteger)second.outputType, (NSInteger)DWOutputTypeNewWindow);

	[NSUserDefaults.standardUserDefaults removeObjectForKey:kFilterOutputTypeKey];
}

// Zero *removes* the key rather than storing 0 — the asymmetry that makes
// "replace input" and "no preference" the same state. A port that stores it
// unconditionally leaves a key behind that means the same thing, which is
// harmless; one that treats the absent key as anything else is not.
void test_setting_replace_input_removes_the_stored_preference ()
{
	OakRunCommandWindowController* controller = FreshController();
	controller.outputType = DWOutputTypeToolTip;
	OAK_ASSERT([NSUserDefaults.standardUserDefaults objectForKey:kFilterOutputTypeKey] != nil);

	controller.outputType = DWOutputTypeReplaceInput;
	OAK_ASSERT([NSUserDefaults.standardUserDefaults objectForKey:kFilterOutputTypeKey] == nil);
}

// The pop-up follows the property, since the menu item tags are the output-type
// values. That is what lets the four items share one action.
void test_setting_the_output_type_selects_the_matching_menu_item ()
{
	OakRunCommandWindowController* controller = FreshController();
	controller.outputType = DWOutputTypeAfterInput;
	OAK_ASSERT_EQ(controller.resultPopUpButton.selectedTag, (NSInteger)DWOutputTypeAfterInput);

	[NSUserDefaults.standardUserDefaults removeObjectForKey:kFilterOutputTypeKey];
}

// Execute is disabled for an empty command and for one that is only whitespace —
// the trimming is the part a port drops, and running an empty command through a
// shell is not harmless.
void test_execute_is_disabled_until_the_command_is_non_blank ()
{
	OakRunCommandWindowController* controller = FreshController();

	controller.commandComboBox.stringValue = @"";
	[controller commandChanged:nil];
	OAK_ASSERT(!controller.executeButton.enabled);

	controller.commandComboBox.stringValue = @"   \t\n  ";
	[controller commandChanged:nil];
	OAK_ASSERT(!controller.executeButton.enabled);

	controller.commandComboBox.stringValue = @"sort";
	[controller commandChanged:nil];
	OAK_ASSERT(controller.executeButton.enabled);

	// Leading and trailing space around real content is still a real command.
	controller.commandComboBox.stringValue = @"  sort | uniq -c  ";
	[controller commandChanged:nil];
	OAK_ASSERT(controller.executeButton.enabled);
}

// The four destinations the menu offers, and their tags. Pinned because the tags
// are what -takeOutputTypeFrom: reads, so a menu built in a different order with
// hard-coded tags would quietly send output to the wrong place.
void test_the_result_menu_offers_the_four_destinations ()
{
	OakRunCommandWindowController* controller = FreshController();
	NSMenu* menu = controller.resultPopUpButton.menu;

	OAK_ASSERT_EQ(menu.numberOfItems, 4);
	OAK_ASSERT_EQ([menu itemAtIndex:0].tag, (NSInteger)DWOutputTypeReplaceInput);
	OAK_ASSERT_EQ([menu itemAtIndex:1].tag, (NSInteger)DWOutputTypeAfterInput);
	OAK_ASSERT_EQ([menu itemAtIndex:2].tag, (NSInteger)DWOutputTypeNewWindow);
	OAK_ASSERT_EQ([menu itemAtIndex:3].tag, (NSInteger)DWOutputTypeToolTip);

	// ⌘1–⌘4, in menu order. The extra parentheses are not style: OAK_ASSERT is a
	// one-argument macro and the preprocessor does not treat [] as grouping, so
	// the comma inside -stringWithFormat: would otherwise split the argument.
	for(NSInteger i = 0; i < 4; ++i)
		OAK_ASSERT(([[menu itemAtIndex:i].keyEquivalent isEqualToString:[NSString stringWithFormat:@"%ld", (long)(i + 1)]]));
}
