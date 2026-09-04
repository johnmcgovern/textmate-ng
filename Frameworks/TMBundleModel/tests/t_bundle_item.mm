#import <TMBundleModel/TMBundleModelCxx.h>
#import <test/bundle_index.h>
#import <ns/ns.h>

// TMBundleItem is the ObjC-shaped model layer over bundles::item_ptr. Its whole
// reason to exist is that Swift cannot call the C++ free functions the `bundles`
// framework exposes, so what these tests check is that the wrapper *agrees with
// the C++ it wraps* — which is why they are ObjC++ and not Swift: a test that
// could only see the ObjC side could not tell agreement from a plausible lie.
//
// The index is process-global (bundles::set_index), so it is built once in
// setup_fixtures and every test reads it.

static bundles::item_ptr TestCommand, TestGrammar, TestProxy, TestBundle, TestPlainCommand, TestZeroUUIDCommand;

void setup_fixtures ()
{
	test::bundle_index_t index;

	// Deliberately lower-cased 'a' against 'Zebra': text::less_t is
	// case-insensitive, so a byte-wise sort would order these the other way and
	// test_sorted_by_name would catch it.
	TestCommand = index.add(bundles::kItemTypeCommand,
		"{	name         = 'apply Filter';"
		"	uuid         = 'C0FFEE00-0000-0000-0000-000000000001';"
		"	tabTrigger   = 'filt';"
		"	keyEquivalent= '^~@f';"
		"	semanticClass= 'callback.test.filter';"
		"	command      = 'true';"
		"}");

	TestPlainCommand = index.add(bundles::kItemTypeCommand,
		"{	name    = 'Zebra';"
		"	uuid    = 'C0FFEE00-0000-0000-0000-000000000002';"
		"	command = 'true';"
		"}");

	TestGrammar = index.add(bundles::kItemTypeGrammar,
		"{	name      = 'Test Grammar';"
		"	uuid      = 'C0FFEE00-0000-0000-0000-000000000003';"
		"	scopeName = 'source.test';"
		"}");

	TestProxy = index.add(bundles::kItemTypeProxy,
		"{	name    = 'Test Proxy';"
		"	uuid    = 'C0FFEE00-0000-0000-0000-000000000004';"
		"	content = 'callback.test.filter';"
		"}");

	// oak::uuid_t clears an unparseable string to all-zeroes, and a malformed
	// uuid in a real bundle's plist lands in the index exactly like this. It is
	// the collision target test_lookup_rejects_a_non_uuid exists to rule out.
	TestZeroUUIDCommand = index.add(bundles::kItemTypeCommand,
		"{	name    = 'Zero UUID';"
		"	uuid    = '00000000-0000-0000-0000-000000000000';"
		"	command = 'true';"
		"}");

	index.commit();
	TestBundle = TestCommand->bundle();
}

// ============
// = Identity =
// ============

// The property both consumers are built on. BundleMenu tracked which items it
// had already emitted in a std::set<item_ptr>, and BundleEditor keys its
// pending-edits map on the item — neither survives a wrapper that yields a
// fresh, unequal object per lookup.
void test_identity_is_interned ()
{
	TMBundleItem* a = [TMBundleItem itemWithCxxItem:TestCommand];
	TMBundleItem* b = [TMBundleItem itemWithCxxItem:TestCommand];

	OAK_ASSERT(a == b);          // same object, not merely equal
	OAK_ASSERT([a isEqual:b]);
	OAK_ASSERT_EQ(a.hash, b.hash);

	TMBundleItem* other = [TMBundleItem itemWithCxxItem:TestGrammar];
	OAK_ASSERT(a != other);
	OAK_ASSERT(![a isEqual:other]);
}

// The consumer-level consequence of the above, asserted through the containers
// the ported code will actually use rather than through -isEqual: directly.
void test_items_deduplicate_in_cocoa_containers ()
{
	NSMutableSet* set = [NSMutableSet set];
	[set addObject:[TMBundleItem itemWithCxxItem:TestCommand]];
	[set addObject:[TMBundleItem itemWithCxxItem:TestCommand]];
	[set addObject:[TMBundleItem itemWithCxxItem:TestGrammar]];
	OAK_ASSERT_EQ(set.count, 2);

	NSMutableDictionary* map = [NSMutableDictionary dictionary];
	map[[TMBundleItem itemWithCxxItem:TestCommand]] = @"first";
	map[[TMBundleItem itemWithCxxItem:TestCommand]] = @"second";
	OAK_ASSERT_EQ(map.count, 1);
	OAK_ASSERT_EQ(to_s(map[[TMBundleItem itemWithCxxItem:TestCommand]]), "second");
}

// A null item_ptr is the C++ "no item"; it has to arrive as nil rather than as a
// live wrapper around nothing, or every consumer needs its own guard.
void test_null_item_becomes_nil ()
{
	OAK_ASSERT(![TMBundleItem itemWithCxxItem:bundles::item_ptr()]);
	OAK_ASSERT(![TMBundleItem itemWithCxxItem:TestBundle].bundle); // a bundle has no bundle
}

// ========================
// = Values and sentinels =
// ========================

// Widened to NSUInteger only so the OAK_ASSERT_EQ preamble picks its integer
// to_s overload rather than its container one; the values are the enumerators.
void test_kind_matches_the_cxx_enum ()
{
	OAK_ASSERT_EQ((NSUInteger)[TMBundleItem itemWithCxxItem:TestCommand].kind, (NSUInteger)TMBundleItemKindCommand);
	OAK_ASSERT_EQ((NSUInteger)[TMBundleItem itemWithCxxItem:TestGrammar].kind, (NSUInteger)TMBundleItemKindGrammar);
	OAK_ASSERT_EQ((NSUInteger)[TMBundleItem itemWithCxxItem:TestProxy].kind,   (NSUInteger)TMBundleItemKindProxy);
	OAK_ASSERT_EQ((NSUInteger)[TMBundleItem itemWithCxxItem:TestBundle].kind,  (NSUInteger)TMBundleItemKindBundle);
	OAK_ASSERT_EQ((NSUInteger)TMBundleItem.menuItemSeparator.kind, (NSUInteger)TMBundleItemKindMenuItemSeparator);
}

void test_values_round_trip ()
{
	TMBundleItem* item = [TMBundleItem itemWithCxxItem:TestCommand];
	OAK_ASSERT_EQ(to_s(item.name), "apply Filter");
	OAK_ASSERT_EQ(to_s(item.uuidString), "C0FFEE00-0000-0000-0000-000000000001");
	OAK_ASSERT_EQ(to_s(item.tabTrigger), "filt");
	OAK_ASSERT_EQ(to_s(item.keyEquivalent), "^~@f");
	OAK_ASSERT(item.bundle == [TMBundleItem itemWithCxxItem:TestBundle]);
}

// NULL_STR is a real string ("￿"), not an empty one, so a wrapper that
// forwarded it would hand Swift a one-character string that reads as present.
// Asserting nil is the point; asserting non-empty would pass either way.
void test_absent_fields_are_nil_not_the_sentinel ()
{
	TMBundleItem* item = [TMBundleItem itemWithCxxItem:TestPlainCommand];
	OAK_ASSERT(TestPlainCommand->value_for_field(bundles::kFieldTabTrigger) == NULL_STR); // premise
	OAK_ASSERT(item.tabTrigger == nil);
	OAK_ASSERT(item.keyEquivalent == nil);
}

// ============
// = Lookup   =
// ============

void test_lookup_by_uuid_round_trips ()
{
	TMBundleItem* item = [TMBundleItem itemWithCxxItem:TestCommand];
	OAK_ASSERT([TMBundleItem itemWithUUIDString:item.uuidString] == item);
}

// oak::uuid_t logs and then CLEARS an unparseable string to all-zeroes, so
// without the is_valid guard every non-UUID string resolves to whatever item
// holds the zero UUID — which a bundle with a malformed uuid in its plist
// really does produce. The zero-UUID fixture is what makes this test able to
// fail: with the guard removed, each of these finds 'Zero UUID' instead of nil.
void test_lookup_rejects_a_non_uuid ()
{
	OAK_ASSERT([TMBundleItem itemWithUUIDString:@"00000000-0000-0000-0000-000000000000"] == [TMBundleItem itemWithCxxItem:TestZeroUUIDCommand]); // premise

	OAK_ASSERT(![TMBundleItem itemWithUUIDString:@"not a uuid"]);
	OAK_ASSERT(![TMBundleItem itemWithUUIDString:@""]);
	OAK_ASSERT(![TMBundleItem itemWithUUIDString:nil]);
	OAK_ASSERT(![TMBundleItem itemWithUUIDString:@"C0FFEE00-0000-0000-0000-00000000FFFF"]); // valid, unknown
}

void test_separator_item_is_a_singleton ()
{
	OAK_ASSERT(TMBundleItem.menuItemSeparator == TMBundleItem.menuItemSeparator);
}

// =====================
// = Menus and proxies =
// =====================

void test_bundle_menu_lists_its_items ()
{
	NSArray<TMBundleItem*>* menu = [TMBundleItem itemWithCxxItem:TestBundle].menu;

	NSMutableSet* names = [NSMutableSet set];
	for(TMBundleItem* item in menu)
		[names addObject:item.name];

	// Grammars are not menu items, so the bundle's menu holds the three commands
	// and the proxy — matching what item_t::menu() returns.
	OAK_ASSERT_EQ(menu.count, 4);
	OAK_ASSERT([names containsObject:@"apply Filter"]);
	OAK_ASSERT([names containsObject:@"Zebra"]);
	OAK_ASSERT(![names containsObject:@"Test Grammar"]);
}

void test_proxy_expands_to_its_semantic_class ()
{
	NSArray<TMBundleItem*>* items = [TMBundleItem itemsForProxy:[TMBundleItem itemWithCxxItem:TestProxy] scope:nil];
	OAK_ASSERT_EQ(items.count, 1);
	OAK_ASSERT(items.firstObject == [TMBundleItem itemWithCxxItem:TestCommand]);
}

// text::less_t is case-insensitive, which is why 'apply Filter' sorts before
// 'Zebra'. A default NSString comparison would order these the other way.
void test_sorted_by_name_is_case_insensitive ()
{
	NSArray<TMBundleItem*>* unsorted = @[
		[TMBundleItem itemWithCxxItem:TestPlainCommand], // Zebra
		[TMBundleItem itemWithCxxItem:TestCommand],      // apply Filter
	];
	NSArray<TMBundleItem*>* sorted = [TMBundleItem itemsSortedByName:unsorted];

	OAK_ASSERT_EQ(sorted.count, 2);
	OAK_ASSERT_EQ(to_s(sorted[0].name), "apply Filter");
	OAK_ASSERT_EQ(to_s(sorted[1].name), "Zebra");
}

// ==================================
// = The editor's query and proxies =
// ==================================

// -itemsInBundle:ofKinds: says "with proxies left unresolved" and, until
// 2026-09-03, did not do it: bundles::query's eighth argument was left at its
// default of true, so the query expanded each proxy into what it stands for and
// never returned the proxy itself.
//
// That is not a documentation nit. The method's one caller is the Bundle
// Editor's **Export Bundle**, which asks for every kind except menu and
// separator — proxies included — and saves each item to the export directory.
// A bundle with proxy items exported without them.
void test_editor_query_returns_proxies_unresolved ()
{
	NSArray* items = [TMBundleItem itemsInBundle:nil ofKinds:TMBundleItemKindProxy];
	OAK_ASSERT([items containsObject:[TMBundleItem itemWithCxxItem:TestProxy]]);
}

// The other half, so the fix cannot be "return everything": an unresolved query
// must still not hand back the items the proxy stands for in place of it.
// TestProxy's content is 'callback.test.filter', which is TestCommand's semantic
// class — that is what resolution would have substituted.
void test_editor_query_does_not_substitute_what_a_proxy_stands_for ()
{
	NSArray* items = [TMBundleItem itemsInBundle:nil ofKinds:TMBundleItemKindProxy];

	OAK_ASSERT_EQ((size_t)items.count, (size_t)1);
	OAK_ASSERT(![items containsObject:[TMBundleItem itemWithCxxItem:TestCommand]]);
}

// ======================================
// = semanticClass and the menus' query =
// ======================================
//
// Both arrived for AppController's menus (2026-09-03): -bundlesMenuNeedsUpdate:
// and -themesMenuNeedsUpdate: are `bundles::query(kFieldAny, NULL_STR,
// scope::wildcard, kind)` plus a semantic-class split, and neither was reachable
// without C++ before.

void test_semantic_class_is_the_field_verbatim ()
{
	// The C++ is the oracle: the wrapper has to agree with what it wraps, not
	// merely return something plausible.
	TMBundleItem* item = [TMBundleItem itemWithCxxItem:TestCommand];
	OAK_ASSERT_EQ(to_s(item.semanticClass), TestCommand->value_for_field(bundles::kFieldSemanticClass));
	OAK_ASSERT_EQ(to_s(item.semanticClass), std::string("callback.test.filter"));
}

// NULL_STR becomes nil at the boundary, once, so it can never reach a caller —
// the contract -name and -tabTrigger already have. It matters here because
// -themesMenuNeedsUpdate: splits this string to classify a theme as light or
// dark, and a caller handed "(null)" or the sentinel would quietly classify
// every theme as "unspecified" without anything failing.
void test_semantic_class_is_nil_when_absent ()
{
	TMBundleItem* item = [TMBundleItem itemWithCxxItem:TestPlainCommand];
	OAK_ASSERT(TestPlainCommand->value_for_field(bundles::kFieldSemanticClass) == NULL_STR);
	OAK_ASSERT(item.semanticClass == nil);
}

// The menus' query: every trailing argument at its default. Asserted against the
// C++ call it stands for rather than a hand-written expectation.
void test_items_of_kinds_in_scope_matches_the_cxx_query ()
{
	NSArray* got = [TMBundleItem itemsOfKinds:TMBundleItemKindCommand inScope:nil];

	std::vector<bundles::item_ptr> want = bundles::query(bundles::kFieldAny, NULL_STR, scope::wildcard, bundles::kItemTypeCommand);
	OAK_ASSERT_EQ((size_t)got.count, want.size());

	std::string missing;
	for(auto const& item : want)
	{
		if(![got containsObject:[TMBundleItem itemWithCxxItem:item]])
			missing += item->name() + " ";
	}
	OAK_ASSERT_EQ(missing, std::string(""));
}

// It asks a different question from -itemsInBundle:ofKinds:, which is why they
// are two methods rather than one with flags. That one answers "what exists" —
// unfiltered, disabled items included, proxies left alone; this one answers
// "what would apply here". A proxy separates them: the editor's query returns
// the proxy itself, the menus' resolves it into what it stands for.
void test_the_two_queries_answer_different_questions ()
{
	TMBundleItem* proxy = [TMBundleItem itemWithCxxItem:TestProxy];

	OAK_ASSERT([[TMBundleItem itemsInBundle:nil ofKinds:TMBundleItemKindProxy] containsObject:proxy]);
	OAK_ASSERT(![[TMBundleItem itemsOfKinds:TMBundleItemKindProxy inScope:nil] containsObject:proxy]);
}

// Bundles, which is exactly what -bundlesMenuNeedsUpdate: asks for.
void test_items_of_kinds_finds_the_bundle ()
{
	NSArray* bundles = [TMBundleItem itemsOfKinds:TMBundleItemKindBundle inScope:nil];
	OAK_ASSERT_GT((size_t)bundles.count, (size_t)0);
	OAK_ASSERT([bundles containsObject:[TMBundleItem itemWithCxxItem:TestBundle]]);
}
