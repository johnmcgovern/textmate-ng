#import "../src/BMSwiftClasses.h"
#import <TMBundleModel/TMBundleModelCxx.h>
#import <plist/ascii.h>
#import <ns/ns.h>

// The grouping half of BundleMenuBuilder: how items from more than one bundle
// are laid out, and the flat-list special case for grammars. A separate file
// from t_bundle_menu.mm because bundles::set_index is process-global — one
// index per test class, and this one needs two bundles.

static bundles::item_ptr Alpha, Zulu, AlphaOne, AlphaTwo, ZuluOne, GrammarB, GrammarA;

static bundles::item_ptr add (std::vector<bundles::item_ptr>& items, bundles::item_ptr bundle, bundles::kind_t kind, std::string const& plistString)
{
	auto const plist = boost::get<plist::dictionary_t>(plist::parse_ascii(plistString));
	auto item = std::make_shared<bundles::item_t>(oak::uuid_t().generate(), bundle, kind);
	item->set_plist(plist);
	items.push_back(item);
	return item;
}

void setup_fixtures ()
{
	std::vector<bundles::item_ptr> items;

	// 'Zulu' added first, so a test that passes only because the input order
	// already matched the output order would be caught.
	Zulu     = add(items, bundles::item_ptr(), bundles::kItemTypeBundle, "{ name = 'Zulu'; }");
	Alpha    = add(items, bundles::item_ptr(), bundles::kItemTypeBundle, "{ name = 'Alpha'; }");

	ZuluOne  = add(items, Zulu,  bundles::kItemTypeCommand, "{ name = 'Zulu Command'; command = 'true'; }");
	AlphaOne = add(items, Alpha, bundles::kItemTypeCommand, "{ name = 'Alpha One'; command = 'true'; }");
	AlphaTwo = add(items, Alpha, bundles::kItemTypeCommand, "{ name = 'Alpha Two'; command = 'true'; }");

	GrammarB = add(items, Zulu,  bundles::kItemTypeGrammar, "{ name = 'beta'; scopeName = 'source.beta'; }");
	GrammarA = add(items, Alpha, bundles::kItemTypeGrammar, "{ name = 'Alpha Lang'; scopeName = 'source.alpha'; }");

	bundles::set_index(items);
}

static NSMenu* menu_for (std::vector<bundles::item_ptr> const& items)
{
	NSMenu* res = [NSMenu new];
	[BundleMenuBuilder addItems:[TMBundleItem itemsWithCxxItems:items] toMenu:res setKeys:NO];
	return res;
}

static std::string layout_of (NSMenu* menu)
{
	NSMutableArray<NSString*>* parts = [NSMutableArray array];
	for(NSMenuItem* item in menu.itemArray)
	{
		if(item.isSeparatorItem)
			[parts addObject:@"<separator>"];
		else if(!item.action)
			[parts addObject:[NSString stringWithFormat:@"[%@]", item.title]]; // heading
		else
			[parts addObject:[NSString stringWithFormat:@"%@%@", item.indentationLevel ? @"  " : @"", item.title]];
	}
	return to_s([parts componentsJoinedByString:@" | "]);
}

// Items drawn from more than one bundle get a heading per bundle and their
// entries indented under it, with the sections ordered by bundle name.
void test_multiple_bundles_get_ordered_headings ()
{
	OAK_ASSERT_EQ(layout_of(menu_for({ ZuluOne, AlphaTwo, AlphaOne })),
		"[Alpha] |   Alpha One |   Alpha Two | [Zulu] |   Zulu Command");
}

// One bundle means the section is the whole menu: no heading, no indentation.
void test_a_single_bundle_gets_no_heading ()
{
	OAK_ASSERT_EQ(layout_of(menu_for({ AlphaTwo, AlphaOne })), "Alpha One | Alpha Two");
}

// Grammars are a flat, name-sorted list whatever bundle they came from — this is
// the language chooser, where bundle headings would be noise. The sort is
// case-insensitive (text::less_t), so 'Alpha Lang' precedes 'beta'; a byte-wise
// sort would put the lower-cased name last.
void test_grammars_are_a_flat_case_insensitive_list ()
{
	OAK_ASSERT_EQ(layout_of(menu_for({ GrammarB, GrammarA })), "Alpha Lang | beta");
}

// A grammar mixed with anything else is not the flat case, and falls back to
// the grouped layout — the guard is `every item is a grammar`, not `any`.
void test_one_non_grammar_disables_the_flat_list ()
{
	OAK_ASSERT_EQ(layout_of(menu_for({ GrammarB, AlphaOne })),
		"[Alpha] |   Alpha One | [Zulu] |   beta");
}

void test_an_empty_item_list_yields_an_empty_menu ()
{
	OAK_ASSERT_EQ(menu_for({}).numberOfItems, 0);
}
