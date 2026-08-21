#import "../src/FileChooserItem.h"
#import <document/OakDocument.h>

// FileChooserItem is the C++ FileChooser row model, extracted so the panel could become
// Swift. It cannot become Swift itself (std::string / std::vector ivars, rule 20), so what
// this file is really for is the batch ranker: the filtering and ordering behind Open
// Quickly, which lived inside a private method of a window controller and had no coverage
// at all. It is a pure function of (records, filter or glob, bindings), so it can simply be
// driven with documents built from paths.
//
// -[OakDocument documentWithPath:] does not touch the disk, so no fixtures are needed.

static FileChooserItem* Item (NSString* path, NSString* base)
{
	return [[FileChooserItem alloc] initWithDocument:[OakDocument documentWithPath:path] base:base isCurrent:NO];
}

static NSArray<FileChooserItem*>* Records ()
{
	return @[
		Item(@"/project/src/main.cc",       @"/project"),
		Item(@"/project/src/window.cc",     @"/project"),
		Item(@"/project/tests/t_window.cc", @"/project"),
		Item(@"/project/README.md",         @"/project"),
	];
}

static NSArray<NSString*>* Names (NSArray<FileChooserItem*>* items)
{
	NSMutableArray* res = [NSMutableArray array];
	for(FileChooserItem* item in items)
		[res addObject:item.name.string];
	return res;
}

void setup ()
{
	NSApplicationLoad();
}

void test_file_chooser_item_exposes_its_document_and_name ()
{
	FileChooserItem* item = Item(@"/project/src/main.cc", @"/project");
	OAK_ASSERT([item.document.path isEqualToString:@"/project/src/main.cc"]);
	OAK_ASSERT([item.name.string isEqualToString:@"main.cc"]);
	OAK_ASSERT([item.folder.string isEqualToString:@"src"]);  // relative to the base
	OAK_ASSERT(item.icon != nil);
	OAK_ASSERT(item.isCloseDisabled == YES);                   // not open
}

void test_file_chooser_item_empty_filter_matches_everything ()
{
	NSArray* ranked = [FileChooserItem rankedItemsFromRecords:Records() fromIndex:0 globString:nil filterString:nil bindings:nil];
	OAK_ASSERT(ranked.count == 4);
}

void test_file_chooser_item_filter_ranks_file_name_matches ()
{
	NSArray* ranked = [FileChooserItem rankedItemsFromRecords:Records() fromIndex:0 globString:nil filterString:@"window" bindings:nil];
	NSArray* names  = Names(ranked);

	OAK_ASSERT(names.count == 2);                                   // both window files
	OAK_ASSERT([names containsObject:@"window.cc"]);
	OAK_ASSERT([names containsObject:@"t_window.cc"]);
	OAK_ASSERT(![names containsObject:@"README.md"]);
}

void test_file_chooser_item_glob_matches_by_path ()
{
	NSArray* ranked = [FileChooserItem rankedItemsFromRecords:Records() fromIndex:0 globString:@"*.md" filterString:nil bindings:nil];
	OAK_ASSERT(ranked.count == 1);
	OAK_ASSERT([Names(ranked).firstObject isEqualToString:@"README.md"]);
}

void test_file_chooser_item_glob_wins_over_filter ()
{
	// The original picked the glob branch whenever globString was non-empty, and only then
	// sorted by name rather than by rank; the filter is ignored in that branch.
	NSArray* ranked = [FileChooserItem rankedItemsFromRecords:Records() fromIndex:0 globString:@"*.cc" filterString:@"readme" bindings:nil];
	OAK_ASSERT(ranked.count == 3);
	OAK_ASSERT(![Names(ranked) containsObject:@"README.md"]);
}

void test_file_chooser_item_bindings_promote_a_learned_path ()
{
	// A learned abbreviation outranks a plain name match: this is what makes typing the
	// same prefix jump to the file you picked last time.
	NSArray* records = Records();
	NSArray* plain   = [FileChooserItem rankedItemsFromRecords:records fromIndex:0 globString:nil filterString:@"window" bindings:nil];
	NSArray* learned = [FileChooserItem rankedItemsFromRecords:records fromIndex:0 globString:nil filterString:@"window" bindings:@[ @"/project/tests/t_window.cc" ]];

	OAK_ASSERT([Names(plain).firstObject isEqualToString:@"window.cc"]);
	OAK_ASSERT([Names(learned).firstObject isEqualToString:@"t_window.cc"]);
}

void test_file_chooser_item_from_index_leaves_earlier_records_alone ()
{
	// The search adds records incrementally and re-ranks only the new tail; earlier records
	// keep whatever match state they already had, which is why the result is not simply the
	// ranking of the whole array.
	NSArray* records = Records();

	// Rank the whole array against "window": the two window files match and stay matched.
	NSArray* all = [FileChooserItem rankedItemsFromRecords:records fromIndex:0 globString:nil filterString:@"window" bindings:nil];
	OAK_ASSERT(all.count == 2);

	// Now re-rank only the tail (README, index 3) against a filter it matches. The first
	// three are not re-ranked and keep the state they already had, so the two window files
	// come back alongside the newly matched README — three, not one. This is what makes the
	// incremental search work: each batch of results is ranked as it arrives, and earlier
	// batches are left alone.
	NSArray* tail = [FileChooserItem rankedItemsFromRecords:records fromIndex:3 globString:nil filterString:@"readme" bindings:nil];
	OAK_ASSERT(tail.count == 3);
	OAK_ASSERT([Names(tail) containsObject:@"README.md"]);
	OAK_ASSERT([Names(tail) containsObject:@"window.cc"]);
}
