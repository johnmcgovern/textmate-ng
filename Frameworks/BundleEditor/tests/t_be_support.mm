#import "../src/BESupport.h"
#import <TMBundleModel/TMBundleModelCxx.h>
#import <test/bundle_index.h>
#import <plist/ascii.h>
#import <ns/ns.h>

// BESupport is the Bundle Editor's remaining ObjC++ — the engine calls specific
// to this one window. What these tests pin is the behaviour a Swift caller now
// depends on and cannot see: that the ASCII plist dialect round-trips, that a
// parse failure is reported as nil rather than as an empty object, and that the
// command popups resolve totally.

static bundles::item_ptr PlainCommand, ConfiguredCommand;

void setup_fixtures ()
{
	test::bundle_index_t index;

	PlainCommand = index.add(bundles::kItemTypeCommand,
		"{ name = 'Plain'; uuid = 'BE500000-0000-0000-0000-000000000001'; command = 'true'; }");

	ConfiguredCommand = index.add(bundles::kItemTypeCommand,
		"{	name           = 'Configured';"
		"	uuid           = 'BE500000-0000-0000-0000-000000000002';"
		"	command        = 'true';"
		"	input          = 'document';"
		"	inputFormat    = 'xml';"
		"	outputLocation = 'newWindow';"
		"	outputFormat   = 'html';"
		"	outputCaret    = 'heuristic';"
		"	beforeRunningCommand = 'saveModifiedFiles';"
		"}");

	index.commit();
}

// ===========================
// = ASCII property lists    =
// ===========================

// The editor writes a body out, the user edits it, the editor reads it back.
// Anything lost in that loop is lost from the item.
void test_plist_text_round_trips_a_dictionary ()
{
	NSDictionary* original = @{ @"name": @"Test", @"softWrap": @YES, @"fontSize": @13 };
	NSDictionary* restored = BEObjectFromPlistString(BEPlistString(original));

	OAK_ASSERT([restored isKindOfClass:NSDictionary.class]);
	OAK_ASSERT_EQ(to_s(restored[@"name"]), "Test");
	OAK_ASSERT([restored[@"softWrap"] boolValue]);
	OAK_ASSERT_EQ([restored[@"fontSize"] intValue], 13);
}

// A macro's `commands` is an array, not a dictionary. plist::convert only
// produces a dictionary_t, so this is the case the one-key wrapper in
// AnyFromObject exists for — and the case a naive implementation drops.
void test_plist_text_round_trips_a_top_level_array ()
{
	NSArray* original = @[ @"one", @{ @"two": @3 } ];
	NSArray* restored = BEObjectFromPlistString(BEPlistString(original));

	OAK_ASSERT([restored isKindOfClass:NSArray.class]);
	OAK_ASSERT_EQ(restored.count, 2);
	OAK_ASSERT_EQ(to_s(restored[0]), "one");
	OAK_ASSERT_EQ([restored[1][@"two"] intValue], 3);
}

// The sort order is user-visible: it is what stops the editor reordering every
// key of every item the first time it saves one. `name` is early in the list and
// `underline` last, so a plain alphabetical serialization reverses them.
void test_plist_text_uses_the_bundle_editor_key_order ()
{
	NSString* text = BEPlistString(@{ @"underline": @YES, @"name": @"Test", @"fontSize": @13 });

	NSRange name      = [text rangeOfString:@"name"];
	NSRange fontSize  = [text rangeOfString:@"fontSize"];
	NSRange underline = [text rangeOfString:@"underline"];

	OAK_ASSERT(name.location != NSNotFound && fontSize.location != NSNotFound && underline.location != NSNotFound);
	OAK_ASSERT(name.location < fontSize.location);
	OAK_ASSERT(fontSize.location < underline.location);
}

// A parse failure has to be distinguishable from a successfully-parsed empty
// object, or the editor silently replaces the item's body with nothing instead
// of showing its "Error Parsing Property List" alert.
void test_unparsable_plist_text_is_nil_not_empty ()
{
	OAK_ASSERT(!BEObjectFromPlistString(@"{ this is not = a plist"));
	OAK_ASSERT(BEObjectFromPlistString(@"{ }")); // …and an empty one still parses
}

// ===================
// = Command popups  =
// ===================

void test_command_popups_resolve_configured_values ()
{
	NSDictionary* values = BECommandPopupValues([TMBundleItem itemWithCxxItem:ConfiguredCommand]);

	OAK_ASSERT_EQ(to_s(values[@"beforeRunningCommand"]), "saveModifiedFiles");
	OAK_ASSERT_EQ(to_s(values[@"input"]), "document");
	OAK_ASSERT_EQ(to_s(values[@"inputFormat"]), "xml");
	OAK_ASSERT_EQ(to_s(values[@"outputLocation"]), "newWindow");
	OAK_ASSERT_EQ(to_s(values[@"outputFormat"]), "html");
	OAK_ASSERT_EQ(to_s(values[@"outputCaret"]), "heuristic");
}

// An item that configures nothing still has to produce a value for every popup —
// the xib binds all six unconditionally, and a missing key is a nil that the
// binding turns into an empty selection.
void test_command_popups_are_total_for_an_unconfigured_command ()
{
	NSDictionary* values = BECommandPopupValues([TMBundleItem itemWithCxxItem:PlainCommand]);

	for(NSString* key in @[ @"beforeRunningCommand", @"input", @"inputFormat", @"outputLocation", @"outputFormat", @"outputCaret", @"autoScrollOutput" ])
		OAK_ASSERT(values[key]);

	// parse_command's defaults, which are what an unconfigured command runs as.
	OAK_ASSERT_EQ(to_s(values[@"input"]), "selection");
	OAK_ASSERT_EQ(to_s(values[@"outputLocation"]), "replaceInput");
}

// =====================
// = Template expansion =
// =====================

// The visitor recurses, so a ${VAR} inside a nested dictionary or array expands
// too — which is where the values in the shipped item templates actually live.
void test_variable_expansion_recurses_through_the_plist ()
{
	NSDictionary* expanded = BEExpandVariables(@{
		@"name":    @"Hello ${WHO}",
		@"nested":  @{ @"deep": @"${WHO} again" },
		@"list":    @[ @"${WHO} in a list" ],
		@"number":  @42,
	}, @{ @"WHO": @"world" });

	OAK_ASSERT_EQ(to_s(expanded[@"name"]), "Hello world");
	OAK_ASSERT_EQ(to_s(expanded[@"nested"][@"deep"]), "world again");
	OAK_ASSERT_EQ(to_s(expanded[@"list"][0]), "world in a list");
	OAK_ASSERT_EQ([expanded[@"number"] intValue], 42); // non-strings pass through
}

// ==========
// = rot13  =
// ==========

void test_rot13_is_its_own_inverse ()
{
	OAK_ASSERT_EQ(to_s(BERot13(@"me@example.com")), "zr@rknzcyr.pbz");
	OAK_ASSERT_EQ(to_s(BERot13(BERot13(@"me@example.com"))), "me@example.com");
}
