#import "../src/OakAbbreviations.h"

// Written against the ObjC++ OakAbbreviations, before the Swift port (rule 18). Unlike
// the ui/ widgets this is a plain store with no UI, so the port is judged on real
// behaviour, not just its selector surface: the per-name singleton, the exact-before-
// prefix ordering, most-recent-first within a group, and the empty-query short-circuit.
//
// Each test uses its own binding name so the process-wide singleton cache doesn't carry
// state between them. The names are test-only keys, and learn* only mutates in memory
// (the flush to NSUserDefaults happens on NSApplicationWillTerminate, which these tests
// never post), so nothing here touches the real defaults a chooser would read.

void setup ()
{
	NSApplicationLoad();
}

void test_abbreviations_is_a_per_name_singleton ()
{
	OakAbbreviations* a = [OakAbbreviations abbreviationsForName:@"t_abbrev_singleton"];
	OAK_ASSERT(a != nil);
	OAK_ASSERT(a == [OakAbbreviations abbreviationsForName:@"t_abbrev_singleton"]);
	OAK_ASSERT(a != [OakAbbreviations abbreviationsForName:@"t_abbrev_other"]);
}

void test_abbreviations_learns_and_returns_a_match ()
{
	OakAbbreviations* a = [OakAbbreviations abbreviationsForName:@"t_abbrev_learn"];
	[a learnAbbreviation:@"fb" forString:@"/foo/bar"];
	OAK_ASSERT([[a stringsForAbbreviation:@"fb"] containsObject:@"/foo/bar"]);
}

void test_abbreviations_orders_exact_before_prefix ()
{
	OakAbbreviations* a = [OakAbbreviations abbreviationsForName:@"t_abbrev_order"];
	[a learnAbbreviation:@"foobar" forString:@"/prefix"]; // only a prefix match for "foo"
	[a learnAbbreviation:@"foo" forString:@"/exact"];     // an exact match for "foo"

	NSArray* r = [a stringsForAbbreviation:@"foo"];
	NSUInteger exact  = [r indexOfObject:@"/exact"];
	NSUInteger prefix = [r indexOfObject:@"/prefix"];
	OAK_ASSERT(exact != NSNotFound && prefix != NSNotFound);
	OAK_ASSERT(exact < prefix);
}

void test_abbreviations_returns_most_recent_first ()
{
	OakAbbreviations* a = [OakAbbreviations abbreviationsForName:@"t_abbrev_recent"];
	[a learnAbbreviation:@"fb" forString:@"/first"];
	[a learnAbbreviation:@"fb" forString:@"/second"];

	NSArray* r = [a stringsForAbbreviation:@"fb"];
	OAK_ASSERT([r indexOfObject:@"/second"] < [r indexOfObject:@"/first"]);
}

void test_abbreviations_empty_query_returns_nothing ()
{
	OakAbbreviations* a = [OakAbbreviations abbreviationsForName:@"t_abbrev_empty"];
	[a learnAbbreviation:@"fb" forString:@"/foo/bar"];
	OAK_ASSERT([[a stringsForAbbreviation:@""] count] == 0);
}
