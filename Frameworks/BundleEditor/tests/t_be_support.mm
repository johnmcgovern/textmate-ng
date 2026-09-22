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

// ==============================
// = The new-bundle template     =
// ==============================

// `TM_ROT13_EMAIL` fills `contactEmailRot13` in the new-bundle template and is
// the only thing in the application that reads it.
//
// It came from the Address Book until 2026-09-22, which cost the whole
// application the `personal-information.addressbook` entitlement and a macOS
// permission prompt — asked of everyone, for a convenience used by the few who
// author bundles. It is `git config user.email` now.
//
// Asserted against git rather than against a fixed string, because the value is
// whatever this machine is configured with, and a test that hard-coded one would
// only pass here. On a machine with no git identity the variable is absent,
// which is also correct: the author types their address, as they would have done
// when the Address Book had no entry either.
void test_the_bundle_template_carries_a_rot13_email_when_git_has_one ()
{
	NSTask* task = [NSTask new];
	task.executableURL  = [NSURL fileURLWithPath:@"/usr/bin/git"];
	task.arguments      = @[ @"config", @"--get", @"user.email" ];
	task.standardOutput = [NSPipe pipe];
	task.standardError  = [NSFileHandle fileHandleWithNullDevice];
	[task launchAndReturnError:nullptr];
	NSString* email = [[[NSString alloc] initWithData:[[task.standardOutput fileHandleForReading] readDataToEndOfFile] encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	[task waitUntilExit];

	NSDictionary* variables = BEDefaultTemplateVariables();

	if(task.terminationStatus == 0 && email.length)
	{
		OAK_ASSERT_EQ(to_s(variables[@"TM_ROT13_EMAIL"]), to_s(BERot13(email)));
		// And it really is obscured, which is the whole point of the field.
		OAK_ASSERT_EQ((bool)[variables[@"TM_ROT13_EMAIL"] isEqualToString:email], false);
	}
	else
	{
		OAK_ASSERT_EQ((bool)(variables[@"TM_ROT13_EMAIL"] == nil), true);
	}
}

// The rest of the template variables are the environment, and must still be
// there — this is the control. Without it the test above would pass just as well
// if BEDefaultTemplateVariables had stopped returning anything at all.
void test_the_bundle_template_still_carries_the_environment ()
{
	NSDictionary* variables = BEDefaultTemplateVariables();
	OAK_ASSERT_EQ((bool)(variables.count > 1), true);
	OAK_ASSERT_EQ((bool)(variables[@"TM_FULLNAME"] != nil), true);
}
