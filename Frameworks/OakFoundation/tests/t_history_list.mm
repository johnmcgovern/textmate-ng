#import "OakFoundationTesting.h"
#import <Cocoa/Cocoa.h>

// Pins for OakHistoryList, written against the ObjC++ and before any port of it
// (rule 18, rule 40). The framework had no tests at all.
//
// It is a most-recently-used stack persisted in NSUserDefaults: Find's glob
// history and recent folders, and the Run Command window's command history.
// Both consumers are Swift already and reach it through bindings —
// `globHistoryList.head` and `globHistoryList.list` — so what a port breaks
// silently is a key path or a persistence rule, not a value. Each pin below
// names one of those rules.
//
// Every list here stores under the `t_history_list_` prefix, cleared before
// each test, so nothing reads or writes the user's own history. No dot in the
// prefix: a dot is what splits a name into a dictionary key and an entry (the
// pin below), and a fixture prefix with one would push every key into a
// dictionary — the first run of these did exactly that.

static NSString* const kPrefix = @"t_history_list_";

static NSString* key (NSString* suffix)
{
	return [kPrefix stringByAppendingString:suffix];
}

void setup ()
{
	NSDictionary* all = NSUserDefaults.standardUserDefaults.dictionaryRepresentation;
	for(NSString* k in all)
	{
		if([k hasPrefix:kPrefix])
			[NSUserDefaults.standardUserDefaults removeObjectForKey:k];
	}
}

static std::string joined (OakHistoryList* list)
{
	NSMutableArray* items = [NSMutableArray array];
	for(id item in [list objectEnumerator])
		[items addObject:[item description]];
	return items.count ? std::string([[items componentsJoinedByString:@" | "] UTF8String]) : std::string("«empty»");
}

// ==================================================================
// = Construction                                                   =
// ==================================================================

void test_history_list_starts_empty_and_reports_its_stack_size ()
{
	OakHistoryList* list = [[OakHistoryList alloc] initWithName:key(@"fresh") stackSize:3];
	OAK_ASSERT_EQ((size_t)list.stackSize, (size_t)3);
	OAK_ASSERT_EQ((size_t)list.count, (size_t)0);
	OAK_ASSERT_EQ((bool)(list.head == nil), true);
	OAK_ASSERT_EQ(joined(list), std::string("«empty»"));
}

void test_history_list_loads_what_was_stored_and_truncates_to_the_stack_size ()
{
	[NSUserDefaults.standardUserDefaults setObject:@[ @"a", @"b", @"c", @"d", @"e" ] forKey:key(@"stored")];

	OakHistoryList* list = [[OakHistoryList alloc] initWithName:key(@"stored") stackSize:3];
	// The stored array is longer than the stack; only the first stackSize
	// survive, most recent first — the order the array was written in.
	OAK_ASSERT_EQ(joined(list), std::string("a | b | c"));
	OAK_ASSERT_EQ(std::string([[list objectAtIndex:1] UTF8String]), std::string("b"));
	OAK_ASSERT_EQ(std::string([list.head UTF8String]), std::string("a"));
}

void test_history_list_a_dotted_name_lives_inside_a_dictionary ()
{
	// Find stores one glob history per project as "Find in Folder Globs.<path>":
	// one key path component before the dot is the defaults key of a dictionary,
	// the rest is the entry in it. Sibling entries in that dictionary survive a
	// write to this one.
	[NSUserDefaults.standardUserDefaults setObject:@{ @"other": @[ @"x" ] } forKey:key(@"Globs")];

	OakHistoryList* list = [[OakHistoryList alloc] initWithName:key(@"Globs.mine") stackSize:5];
	OAK_ASSERT_EQ(list.count, (NSUInteger)0);

	[list addObject:@"*.swift"];

	NSDictionary* dict = [NSUserDefaults.standardUserDefaults dictionaryForKey:key(@"Globs")];
	OAK_ASSERT_EQ(std::string([[dict[@"mine"] componentsJoinedByString:@","] UTF8String]), std::string("*.swift"));
	OAK_ASSERT_EQ(std::string([[dict[@"other"] componentsJoinedByString:@","] UTF8String]), std::string("x"));

	// And it reads back through the same path.
	OakHistoryList* again = [[OakHistoryList alloc] initWithName:key(@"Globs.mine") stackSize:5];
	OAK_ASSERT_EQ(joined(again), std::string("*.swift"));
}

void test_history_list_only_the_first_dot_splits_the_name ()
{
	// A project path contains dots ("Globs./Users/x/site.example"); everything
	// after the first dot is one entry name, not a deeper path.
	OakHistoryList* list = [[OakHistoryList alloc] initWithName:key(@"Dotted./a/b.c/d") stackSize:5];
	[list addObject:@"one"];

	NSDictionary* dict = [NSUserDefaults.standardUserDefaults dictionaryForKey:key(@"Dotted")];
	OAK_ASSERT_EQ((bool)(dict[@"/a/b.c/d"] != nil), true);
}

void test_history_list_fallback_key_is_read_only_when_the_list_is_empty ()
{
	[NSUserDefaults.standardUserDefaults setObject:@[ @"old-1", @"old-2" ] forKey:key(@"legacy")];

	// Nothing under the new name: the fallback's items become the list.
	OakHistoryList* migrated = [[OakHistoryList alloc] initWithName:key(@"Globs.p") stackSize:5 fallbackUserDefaultsKey:key(@"legacy")];
	OAK_ASSERT_EQ(joined(migrated), std::string("old-1 | old-2"));

	// Something under the new name: the fallback is ignored.
	[migrated addObject:@"new"];
	OakHistoryList* settled = [[OakHistoryList alloc] initWithName:key(@"Globs.p") stackSize:5 fallbackUserDefaultsKey:key(@"legacy")];
	OAK_ASSERT_EQ(joined(settled), std::string("new | old-1 | old-2"));
}

void test_history_list_default_items_seed_an_empty_list_and_are_not_stored ()
{
	OakHistoryList* seeded = [[OakHistoryList alloc] initWithName:key(@"cmds") stackSize:5 defaultItemsArray:@[ @"sort", @"uniq" ]];
	OAK_ASSERT_EQ(joined(seeded), std::string("sort | uniq"));

	// Seeding does not write: a second list without defaults is empty.
	OakHistoryList* bare = [[OakHistoryList alloc] initWithName:key(@"cmds") stackSize:5];
	OAK_ASSERT_EQ(joined(bare), std::string("«empty»"));
}

void test_history_list_stored_history_wins_over_default_items ()
{
	[NSUserDefaults.standardUserDefaults setObject:@[ @"mine" ] forKey:key(@"cmds2")];
	OakHistoryList* list = [[OakHistoryList alloc] initWithName:key(@"cmds2") stackSize:5 defaultItemsArray:@[ @"sort", @"uniq" ]];
	OAK_ASSERT_EQ(joined(list), std::string("mine"));
}

// ==================================================================
// = Adding                                                         =
// ==================================================================

void test_history_list_add_puts_the_item_first_and_persists ()
{
	OakHistoryList* list = [[OakHistoryList alloc] initWithName:key(@"add") stackSize:5];
	[list addObject:@"one"];
	[list addObject:@"two"];
	OAK_ASSERT_EQ(joined(list), std::string("two | one"));

	NSArray* stored = [NSUserDefaults.standardUserDefaults arrayForKey:key(@"add")];
	OAK_ASSERT_EQ(std::string([[stored componentsJoinedByString:@" | "] UTF8String]), std::string("two | one"));
}

void test_history_list_adding_an_existing_item_moves_it_to_the_top ()
{
	OakHistoryList* list = [[OakHistoryList alloc] initWithName:key(@"move") stackSize:5];
	[list addObject:@"one"];
	[list addObject:@"two"];
	[list addObject:@"three"];
	[list addObject:@"one"];
	OAK_ASSERT_EQ(joined(list), std::string("one | three | two"));
	OAK_ASSERT_EQ((size_t)list.count, (size_t)3);
}

void test_history_list_overflow_drops_the_oldest ()
{
	OakHistoryList* list = [[OakHistoryList alloc] initWithName:key(@"overflow") stackSize:2];
	[list addObject:@"one"];
	[list addObject:@"two"];
	[list addObject:@"three"];
	// The last (oldest) goes, not the first.
	OAK_ASSERT_EQ(joined(list), std::string("three | two"));
}

void test_history_list_ignores_empty_strings_and_the_current_head ()
{
	OakHistoryList* list = [[OakHistoryList alloc] initWithName:key(@"ignore") stackSize:5];
	[list addObject:@"one"];
	[list addObject:@""];
	[list addObject:nil];
	[list addObject:@"one"];
	OAK_ASSERT_EQ(joined(list), std::string("one"));

	// Nothing was written for the ignored adds either: exactly one entry stored.
	OAK_ASSERT_EQ((size_t)[[NSUserDefaults.standardUserDefaults arrayForKey:key(@"ignore")] count], (size_t)1);
}

// ==================================================================
// = The binding surface                                            =
// ==================================================================

// HistoryObserver is declared in OakFoundationTesting.h: an ObjC class cannot
// be declared inside the namespace gen_xctest wraps this file in.

void test_history_list_head_setter_adds_and_notifies_head_and_list ()
{
	OakHistoryList* list = [[OakHistoryList alloc] initWithName:key(@"kvo") stackSize:5];

	HistoryObserver* observer = [HistoryObserver new];
	observer.keys = [NSMutableArray array];
	[list addObserver:observer forKeyPath:@"head" options:0 context:NULL];
	[list addObserver:observer forKeyPath:@"list" options:0 context:NULL];

	// The glob field binds its value to `head`: typing a glob and pressing return
	// sets it, which is an add.
	list.head = @"*.m";
	OAK_ASSERT_EQ(joined(list), std::string("*.m"));
	// `head` is reported twice, measured against the ObjC++: -addObject: sends
	// its own will/didChange for head (and list), and the runtime wraps -setHead:
	// in another pair because the setter is KVO-compliant by name. A binding
	// does not mind hearing it twice; a port that dropped the setter's automatic
	// notification, or the explicit one, would change the count.
	OAK_ASSERT_EQ(std::string([[observer.keys componentsJoinedByString:@","] UTF8String]), std::string("list,head,head"));

	// Setting the head to what it already is changes nothing in the list, and
	// only the setter's automatic notification fires — the explicit pair does not.
	list.head = @"*.m";
	OAK_ASSERT_EQ(std::string([[observer.keys componentsJoinedByString:@","] UTF8String]), std::string("list,head,head,head"));
	OAK_ASSERT_EQ(joined(list), std::string("*.m"));

	[list removeObserver:observer forKeyPath:@"head"];
	[list removeObserver:observer forKeyPath:@"list"];
}

void test_history_list_list_key_path_is_the_stored_order ()
{
	// The combo box binds its content values to `list`. It is reached by KVC and
	// is the same array the enumerator walks.
	OakHistoryList* list = [[OakHistoryList alloc] initWithName:key(@"kvc") stackSize:5];
	[list addObject:@"b"];
	[list addObject:@"a"];
	NSArray* viaKVC = [list valueForKey:@"list"];
	OAK_ASSERT_EQ(std::string([[viaKVC componentsJoinedByString:@" | "] UTF8String]), std::string("a | b"));
}

void test_history_list_selector_surface ()
{
	// Everything the two Swift consumers and the bindings reach. The variadic
	// -initWithName:stackSize:defaultItems: is deliberately not here: it cannot
	// be written in Swift, nothing calls it since the array spelling was added,
	// and the port drops it.
	OakHistoryList* list = [[OakHistoryList alloc] initWithName:key(@"sel") stackSize:1];
	OAK_ASSERT_EQ((bool)[list respondsToSelector:@selector(initWithName:stackSize:)], true);
	OAK_ASSERT_EQ((bool)[list respondsToSelector:@selector(initWithName:stackSize:fallbackUserDefaultsKey:)], true);
	OAK_ASSERT_EQ((bool)[list respondsToSelector:@selector(initWithName:stackSize:defaultItemsArray:)], true);
	OAK_ASSERT_EQ((bool)[list respondsToSelector:@selector(addObject:)], true);
	OAK_ASSERT_EQ((bool)[list respondsToSelector:@selector(objectEnumerator)], true);
	OAK_ASSERT_EQ((bool)[list respondsToSelector:@selector(objectAtIndex:)], true);
	OAK_ASSERT_EQ((bool)[list respondsToSelector:@selector(count)], true);
	OAK_ASSERT_EQ((bool)[list respondsToSelector:@selector(head)], true);
	OAK_ASSERT_EQ((bool)[list respondsToSelector:@selector(setHead:)], true);
	OAK_ASSERT_EQ((bool)[list respondsToSelector:@selector(stackSize)], true);
}
