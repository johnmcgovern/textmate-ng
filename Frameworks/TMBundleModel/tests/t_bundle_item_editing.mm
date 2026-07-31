#import <TMBundleModel/TMBundleModelCxx.h>
#import <test/bundle_index.h>
#import <test/jail.h>
#import <plist/ascii.h>
#import <io/path.h>
#import <ns/ns.h>

// The half of TMBundleItem the Bundle Editor needs: the property bag, item
// creation and removal, the bundle-scoped query behind the browser tree, and
// the bundles::callback_t bridge.
//
// -moveToTrash is deliberately NOT covered here. Its local-item branch calls
// path::move_to_trash, which would put fixtures in the running user's Trash;
// a test is not worth that. It is exercised in the app instead.

static bundles::item_ptr Bundle, Grammar, Snippet, Hidden, Disabled;

void setup_fixtures ()
{
	test::bundle_index_t index;

	Grammar = index.add(bundles::kItemTypeGrammar,
		"{	name      = 'Test Grammar';"
		"	uuid      = 'DEC0DE00-0000-0000-0000-000000000001';"
		"	scopeName = 'source.test';"
		"	fileTypes = ( 'ttt', 'tst' );"
		"}");

	Snippet = index.add(bundles::kItemTypeSnippet,
		"{	name    = 'Test Snippet';"
		"	uuid    = 'DEC0DE00-0000-0000-0000-000000000002';"
		"	content = 'hello';"
		"}");

	// Both of these are invisible to an ordinary bundles::query and must still
	// appear in the Bundle Editor — that is the whole point of the query
	// -itemsInBundle:ofKinds: wraps.
	Hidden = index.add(bundles::kItemTypeCommand,
		"{	name = 'Hidden'; uuid = 'DEC0DE00-0000-0000-0000-000000000003'; hideFromUser = 1; command = 'true'; }");
	Disabled = index.add(bundles::kItemTypeCommand,
		"{	name = 'Disabled'; uuid = 'DEC0DE00-0000-0000-0000-000000000004'; isDisabled = 1; command = 'true'; }");

	index.commit();
	Bundle = Grammar->bundle();
}

static TMBundleItem* wrap (bundles::item_ptr const& item)
{
	return [TMBundleItem itemWithCxxItem:item];
}

// plist::get_key_path, not to_s: boost's to_s(plist::any_t) renders a plist
// *literal*, so a string comes back wrapped in quotes and compares unequal to
// its own value.
static std::string string_at (plist::dictionary_t const& plist, std::string const& key)
{
	std::string res = NULL_STR;
	plist::get_key_path(plist, key, res);
	return res;
}

// ================
// = Property bag =
// ================

void test_properties_expose_the_plist ()
{
	NSDictionary* properties = wrap(Snippet).properties;
	OAK_ASSERT_EQ(to_s(properties[@"name"]), "Test Snippet");
	OAK_ASSERT_EQ(to_s(properties[@"content"]), "hello");
}

void test_properties_round_trip_through_the_plist_variant ()
{
	TMBundleItem* item = wrap(Snippet);

	NSMutableDictionary* edited = [item.properties mutableCopy];
	edited[@"content"] = @"goodbye";
	item.properties = edited;

	OAK_ASSERT_EQ(to_s(item.properties[@"content"]), "goodbye");
	OAK_ASSERT_EQ(string_at(Snippet->plist(), "content"), "goodbye"); // reached the C++, not just the wrapper

	// Restored, because the index is shared across every test in this class.
	edited[@"content"] = @"hello";
	item.properties = edited;
	OAK_ASSERT_EQ(string_at(Snippet->plist(), "content"), "hello");
}

// The pending-edits decision: the Bundle Editor keeps an edit only while it
// differs from what is stored. Comparing the Foundation dictionaries directly
// would not do — the round trip through plist::any_t does not preserve every
// class — so this has to go through plist::equal.
void test_stored_properties_comparison_ignores_foundation_class ()
{
	TMBundleItem* item = wrap(Grammar);

	OAK_ASSERT([item storedPropertiesEqual:item.properties]);

	NSMutableDictionary* edited = [item.properties mutableCopy];
	edited[@"scopeName"] = @"source.changed";
	OAK_ASSERT(![item storedPropertiesEqual:edited]);
}

// item_t flattens multi-valued fields, so a grammar's file types are reachable
// only through values_for_field — not through `properties`.
void test_values_for_field_returns_every_value ()
{
	NSArray<NSString*>* types = [wrap(Grammar) valuesForField:@"fileTypes"];
	OAK_ASSERT_EQ(types.count, 2);
	OAK_ASSERT([types containsObject:@"ttt"]);
	OAK_ASSERT([types containsObject:@"tst"]);
}

void test_values_for_field_is_empty_for_an_absent_field ()
{
	OAK_ASSERT_EQ([wrap(Snippet) valuesForField:@"fileTypes"].count, 0);
}

// ==========================
// = Creation and the index =
// ==========================

void test_created_item_is_in_the_index_and_carries_its_uuid ()
{
	TMBundleItem* created = [TMBundleItem createItemOfKind:TMBundleItemKindCommand inBundle:wrap(Bundle) properties:@{ @"name": @"Created", @"command": @"true" }];

	OAK_ASSERT(created);
	OAK_ASSERT_EQ(to_s(created.name), "Created");
	OAK_ASSERT(created.bundle == wrap(Bundle));

	// The generated UUID has to reach the plist as well as the item — it is what
	// the item is looked up by once saved.
	OAK_ASSERT_EQ(to_s(created.properties[@"uuid"]), to_s(created.uuidString));

	OAK_ASSERT([TMBundleItem itemWithUUIDString:created.uuidString] == created);

	[created removeFromIndex];
	OAK_ASSERT(![TMBundleItem itemWithUUIDString:created.uuidString]);
}

// ============================
// = The Bundle Editor query  =
// ============================

// A plain bundles::query hides both of these. The Bundle Editor lists what is
// there, so its query must not filter — a disabled item is precisely what a user
// opens the editor to re-enable.
void test_items_in_bundle_include_hidden_and_disabled ()
{
	NSArray<TMBundleItem*>* items = [TMBundleItem itemsInBundle:wrap(Bundle) ofKinds:TMBundleItemKindCommand];

	NSMutableSet<NSString*>* names = [NSMutableSet set];
	for(TMBundleItem* item in items)
		[names addObject:item.name];

	OAK_ASSERT([names containsObject:@"Hidden"]);
	OAK_ASSERT([names containsObject:@"Disabled"]);
}

void test_items_in_bundle_filters_by_kind ()
{
	NSArray<TMBundleItem*>* grammars = [TMBundleItem itemsInBundle:wrap(Bundle) ofKinds:TMBundleItemKindGrammar];
	OAK_ASSERT_EQ(grammars.count, 1);
	OAK_ASSERT(grammars.firstObject == wrap(Grammar));
}

// ===============
// = Persistence =
// ===============

void test_save_to_directory_writes_a_readable_plist ()
{
	test::jail_t jail;
	OAK_ASSERT([wrap(Snippet) saveToDirectory:[NSString stringWithCxxString:jail.path()]]);

	// The file lands under the kind's conventional subdirectory, which is why
	// this searches rather than naming a path — the layout is item_t's business.
	__block NSString* found = nil;
	NSString* root = [NSString stringWithCxxString:jail.path()];
	for(NSString* rel in [NSFileManager.defaultManager subpathsAtPath:root])
	{
		if([rel.pathExtension isEqualToString:@"tmSnippet"])
			found = [root stringByAppendingPathComponent:rel];
	}

	OAK_ASSERT(found);
	OAK_ASSERT_EQ(string_at(plist::load(to_s(found)), "name"), "Test Snippet");
}

// ==================================
// = The bundles::callback_t bridge =
// ==================================

// Swift cannot subclass bundles::callback_t, so the wrapper owns the one
// subscriber and re-broadcasts. The post is dispatched to the main queue (the
// index can be rebuilt off-main), so the run loop has to turn for it to arrive —
// which is also what a real AppKit observer relies on.
void test_index_changes_post_a_notification ()
{
	__block BOOL observed = NO;
	id token = [NSNotificationCenter.defaultCenter addObserverForName:TMBundleItemsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification*){
		observed = YES;
	}];

	TMBundleItem* created = [TMBundleItem createItemOfKind:TMBundleItemKindCommand inBundle:wrap(Bundle) properties:@{ @"name": @"Transient", @"command": @"true" }];

	NSDate* giveUp = [NSDate dateWithTimeIntervalSinceNow:5.0];
	while(!observed && [giveUp timeIntervalSinceNow] > 0)
		[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];

	[created removeFromIndex];
	[NSNotificationCenter.defaultCenter removeObserver:token];

	OAK_ASSERT(observed);
}
