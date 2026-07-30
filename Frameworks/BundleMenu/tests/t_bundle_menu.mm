#import <BundleMenu/BundleMenu.h>
#import "../src/BMSwiftClasses.h"
#import <TMBundleModel/TMBundleModelCxx.h>
#import <plist/ascii.h>
#import <ns/ns.h>

// BundleMenu is Swift over TMBundleItem, reached from ObjC++ through two
// hand-written declarations — BundleMenu.h (public) and BMSwiftClasses.h
// (internal). Nothing checks either against the Swift at build time, so a drift
// is an unrecognized selector at runtime. These tests are that check, and they
// import both headers for exactly that reason.
//
// They also cover the menu *structure*, which is what the accessibility tree
// cannot see: separator collapsing, submenu titles, the disabled placeholder a
// dead proxy leaves behind.

static bundles::item_ptr Bundle, CmdRun, CmdBuild, CmdNested, SubMenu, DeadProxy, LiveProxy, Target;

static bundles::item_ptr add (std::vector<bundles::item_ptr>& items, bundles::item_ptr bundle, bundles::kind_t kind, std::string const& plistString)
{
	auto const plist = boost::get<plist::dictionary_t>(plist::parse_ascii(plistString));

	oak::uuid_t uuid;
	if(!plist::get_key_path(plist, bundles::kFieldUUID, uuid))
		uuid.generate();

	auto item = std::make_shared<bundles::item_t>(uuid, bundle, kind);
	item->set_plist(plist);
	items.push_back(item);
	return item;
}

void setup_fixtures ()
{
	std::vector<bundles::item_ptr> items;

	Bundle    = add(items, bundles::item_ptr(), bundles::kItemTypeBundle,  "{ name = 'Test Bundle'; }");
	CmdRun    = add(items, Bundle, bundles::kItemTypeCommand, "{ name = 'Run'; tabTrigger = 'run'; keyEquivalent = '@r'; command = 'true'; }");
	CmdBuild  = add(items, Bundle, bundles::kItemTypeCommand, "{ name = 'Build'; command = 'true'; }");
	CmdNested = add(items, Bundle, bundles::kItemTypeCommand, "{ name = 'Nested'; command = 'true'; }");
	SubMenu   = add(items, Bundle, bundles::kItemTypeMenu,    "{ name = 'More'; }");

	// A proxy resolves to the items carrying its semanticClass. LiveProxy has a
	// target, DeadProxy names a class nothing declares. hideFromUser on the
	// target is the real idiom — an item reached only through a proxy does not
	// also want its own entry — and it keeps this fixture's menu unambiguous.
	Target    = add(items, Bundle, bundles::kItemTypeCommand, "{ name = 'Proxied'; semanticClass = 'test.reachable'; hideFromUser = 1; command = 'true'; }");
	LiveProxy = add(items, Bundle, bundles::kItemTypeProxy,   "{ name = 'Live Proxy'; content = 'test.reachable'; }");
	DeadProxy = add(items, Bundle, bundles::kItemTypeProxy,   "{ name = 'Dead Proxy'; keyEquivalent = '@d'; content = 'test.unreachable'; }");

	// The bundle's menu layout, the shape create_bundle_index produces from a
	// tmbundle's info.plist: an ordered uuid list per menu, with kSeparatorUUID
	// standing in for a separator.
	std::map<oak::uuid_t, std::vector<oak::uuid_t>> menus;
	menus[Bundle->uuid()] = {
		CmdRun->uuid(),
		bundles::kSeparatorUUID,
		SubMenu->uuid(),
		LiveProxy->uuid(),
		DeadProxy->uuid(),
	};
	menus[SubMenu->uuid()] = { CmdNested->uuid() };

	bundles::set_index(items, menus);
}

static NSMenu* built_menu (bundles::item_ptr const& umbrella)
{
	NSMenu* res = [[NSMenu alloc] initWithTitle:[TMBundleItem itemWithCxxItem:umbrella].uuidString];
	res.delegate = BundleMenuDelegate.sharedInstance;
	[BundleMenuDelegate.sharedInstance menuNeedsUpdate:res];
	return res;
}

static NSMenuItem* item_named (NSMenu* menu, NSString* title)
{
	for(NSMenuItem* item in menu.itemArray)
	{
		if([item.title isEqualToString:title])
			return item;
	}
	return nil;
}

// ===================
// = menuNeedsUpdate =
// ===================

// The whole contract in one assertion: a menu titled with a bundle's UUID
// populates itself from that bundle's declared layout, in order.
void test_menu_is_built_from_the_bundle_layout ()
{
	NSMenu* menu = built_menu(Bundle);

	NSMutableArray<NSString*>* titles = [NSMutableArray array];
	for(NSMenuItem* item in menu.itemArray)
		[titles addObject:item.isSeparatorItem ? @"<separator>" : item.title];

	// 'Build' is absent from the layout, so it is appended after everything the
	// layout named — which is what leaves it last rather than beside 'Run'.
	// 'More' is a submenu, 'Live Proxy' has been replaced by what it resolves
	// to, and 'Dead Proxy' survives as its own disabled entry.
	OAK_ASSERT_EQ(to_s([titles componentsJoinedByString:@" | "]),
		"Run | <separator> | More | Proxied | Dead Proxy | Build");
}

// A title that is not a known UUID must leave the menu empty rather than throw
// — every submenu is created with a UUID title, so a stale one is reachable.
void test_unknown_menu_title_yields_an_empty_menu ()
{
	NSMenu* menu = [[NSMenu alloc] initWithTitle:@"not a uuid"];
	[BundleMenuDelegate.sharedInstance menuNeedsUpdate:menu];
	OAK_ASSERT_EQ(menu.numberOfItems, 0);
}

// The UUID in representedObject is the entire payload: AppController's
// -performBundleItemWithUUIDStringFrom: reads it back and looks the item up.
void test_represented_object_is_the_item_uuid ()
{
	NSMenuItem* run = item_named(built_menu(Bundle), @"Run");
	OAK_ASSERT(run);
	OAK_ASSERT_EQ(to_s((NSString*)run.representedObject), to_s(CmdRun->uuid()));
	OAK_ASSERT(run.action == NSSelectorFromString(@"performBundleItemWithUUIDStringFrom:"));
}

// A submenu is created empty, carrying its own item's UUID as its title and the
// shared delegate. That pair is the only thing it has to populate itself with
// when the user opens it, so both halves matter: a missing delegate means the
// submenu never fills in, a wrong title means it fills in with someone else's
// items.
void test_submenu_carries_its_uuid_and_the_shared_delegate ()
{
	NSMenuItem* more = item_named(built_menu(Bundle), @"More");
	OAK_ASSERT(more.submenu);
	OAK_ASSERT_EQ(to_s(more.submenu.title), to_s(SubMenu->uuid()));
	OAK_ASSERT(more.submenu.delegate == BundleMenuDelegate.sharedInstance);

	// …and opening it does resolve to the submenu's own layout.
	OAK_ASSERT(item_named(built_menu(SubMenu), @"Nested"));
}

// A proxy that resolves to nothing still shows its own name, disabled, so a key
// equivalent the user has memorised does not silently vanish from the menu.
void test_dead_proxy_leaves_a_disabled_placeholder ()
{
	NSMenuItem* dead = item_named(built_menu(Bundle), @"Dead Proxy");
	OAK_ASSERT(dead);
	OAK_ASSERT(dead.action == NSSelectorFromString(@"nop:"));
	OAK_ASSERT(!dead.representedObject);
}

// A live proxy is replaced by what it resolves to — the proxy's own name never
// appears.
void test_live_proxy_is_replaced_by_its_items ()
{
	NSMenu* menu = built_menu(Bundle);
	OAK_ASSERT(item_named(menu, @"Proxied"));
	OAK_ASSERT(!item_named(menu, @"Live Proxy"));
}

// =========
// = Popup =
// =========

// OakShowMenuForBundleItems short-circuits below two items, and OakTextView
// routes EVERY key-equivalent match through it — so this is the path a single
// bundle key press takes, and the one that proves BMSwiftClasses.h's selector
// still matches the Swift.
void test_popup_short_circuits_below_two_items ()
{
	TMBundleItem* run = [TMBundleItem itemWithCxxItem:CmdRun];

	OAK_ASSERT([BundleMenuPopup showMenuForItems:@[ run ] inView:nil atPoint:NSZeroPoint] == run);
	OAK_ASSERT(![BundleMenuPopup showMenuForItems:@[] inView:nil atPoint:NSZeroPoint]);
}

// The C++-typed entry point the unported ObjC++ consumers still call. Exercises
// the item_ptr -> TMBundleItem -> item_ptr round trip in BundleMenuSupport.mm,
// including that an empty result comes back as a null item_ptr and not as a
// wrapper around nothing.
void test_cxx_entry_point_round_trips_an_item_ptr ()
{
	OAK_ASSERT(OakShowMenuForBundleItems({ CmdRun }, nil, NSZeroPoint) == CmdRun);
	OAK_ASSERT(!OakShowMenuForBundleItems({}, nil, NSZeroPoint));
}
