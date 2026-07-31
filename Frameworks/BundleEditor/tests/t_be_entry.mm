#import "../src/BEEntry.h"
#import <TMBundleModel/TMBundleModelCxx.h>
#import <test/bundle_index.h>
#import <plist/ascii.h>
#import <ns/ns.h>

// BEEntry wraps be::entry_t, the Bundle Editor's NSBrowser model. The C++ side
// is a polymorphic hierarchy whose subclasses exist only to override a
// protected entries(); what these tests pin is that the *shape* that hierarchy
// produces survives the wrapper — the fixed group rows under a bundle, where
// items land, and the identifiers the editor restores its selection by.
//
// ObjC++ rather than Swift for the same reason as TMBundleModel's tests: the
// point is agreement with the C++, and a test that could only see the ObjC side
// could not tell agreement from a plausible lie.

static bundles::item_ptr Bundle, Grammar, Setting, MenuCommand, MenuGroup;

void setup_fixtures ()
{
	test::bundle_index_t index;

	Grammar = index.add(bundles::kItemTypeGrammar,
		"{ name = 'Test Grammar'; uuid = 'BEEBEE00-0000-0000-0000-000000000001'; scopeName = 'source.test'; }");
	Setting = index.add(bundles::kItemTypeSettings,
		"{ name = 'Test Settings'; uuid = 'BEEBEE00-0000-0000-0000-000000000002'; settings = { spellChecking = 0; }; }");
	MenuCommand = index.add(bundles::kItemTypeCommand,
		"{ name = 'Menu Command'; uuid = 'BEEBEE00-0000-0000-0000-000000000003'; command = 'true'; }");
	MenuGroup = index.add(bundles::kItemTypeMenu,
		"{ name = 'Submenu'; uuid = 'BEEBEE00-0000-0000-0000-000000000004'; }");

	Bundle = Grammar->bundle();

	std::map<oak::uuid_t, std::vector<oak::uuid_t>> menus;
	menus[Bundle->uuid()]    = { MenuGroup->uuid() };
	menus[MenuGroup->uuid()] = { MenuCommand->uuid() };

	bundles::set_index({ Bundle, Grammar, Setting, MenuCommand, MenuGroup }, menus);
}

static BEEntry* child_named (BEEntry* entry, NSString* name)
{
	for(BEEntry* child in entry.children)
	{
		if([child.name isEqualToString:name])
			return child;
	}
	return nil;
}

// =========
// = Root  =
// =========

void test_root_lists_the_installed_bundles ()
{
	BEEntry* root = BEEntry.bundlesRoot;
	OAK_ASSERT_EQ(to_s(root.name), "Bundles");
	OAK_ASSERT(root.hasChildren);

	BEEntry* bundle = child_named(root, @"Fixtures Bundle");
	OAK_ASSERT(bundle);
	OAK_ASSERT(bundle.representedItem == [TMBundleItem itemWithCxxItem:Bundle]);
}

// A bundle always expands into the same fixed group rows, in this order,
// whether or not any of them has content — the Bundle Editor's browser column
// is a fixed vocabulary, not a summary of what exists.
void test_a_bundle_expands_into_its_fixed_groups ()
{
	BEEntry* bundle = child_named(BEEntry.bundlesRoot, @"Fixtures Bundle");

	NSMutableArray<NSString*>* names = [NSMutableArray array];
	for(BEEntry* child in bundle.children)
		[names addObject:child.name];

	OAK_ASSERT_EQ(to_s([names componentsJoinedByString:@" | "]),
		"Menu Actions | Other Actions | File Drop Actions | Language Grammars | Settings | Support | Themes");
}

// ==========
// = Items  =
// ==========

void test_items_land_in_the_group_matching_their_kind ()
{
	BEEntry* bundle = child_named(BEEntry.bundlesRoot, @"Fixtures Bundle");

	BEEntry* grammar = child_named(child_named(bundle, @"Language Grammars"), @"Test Grammar");
	OAK_ASSERT(grammar);
	OAK_ASSERT(grammar.representedItem == [TMBundleItem itemWithCxxItem:Grammar]);

	BEEntry* setting = child_named(child_named(bundle, @"Settings"), @"Test Settings");
	OAK_ASSERT(setting);
	OAK_ASSERT(setting.representedItem == [TMBundleItem itemWithCxxItem:Setting]);

	// …and not in each other's.
	OAK_ASSERT(!child_named(child_named(bundle, @"Settings"), @"Test Grammar"));
}

// A menu structure nests: "Menu Actions" mirrors the bundle's declared layout
// rather than flattening it the way the Bundles *menu* does.
void test_menu_actions_preserve_the_declared_nesting ()
{
	BEEntry* bundle  = child_named(BEEntry.bundlesRoot, @"Fixtures Bundle");
	BEEntry* submenu = child_named(child_named(bundle, @"Menu Actions"), @"Submenu");

	OAK_ASSERT(submenu);
	OAK_ASSERT(submenu.hasChildren);
	OAK_ASSERT(child_named(submenu, @"Menu Command"));
}

// A group row stands for no item and no file. The Bundle Editor branches on
// exactly this to decide whether a row is editable.
void test_group_rows_represent_neither_item_nor_path ()
{
	BEEntry* group = child_named(child_named(BEEntry.bundlesRoot, @"Fixtures Bundle"), @"Settings");
	OAK_ASSERT(!group.representedItem);
	OAK_ASSERT(!group.representedPath);
}

// -hasChildren means "is not a leaf", NOT "has at least one child", and the two
// come apart here: a bundle with no Support directory still gets a Support row,
// and that row reports itself expandable while returning nothing.
//
// This is not an accident of the wrapper — be::entry_t's base entries() returns
// a one-null-element sentinel meaning "leaf", so a subclass returning a
// genuinely empty vector is expandable-but-empty. NSBrowser sets its cells'
// leaf flag straight off this, so "simplifying" it to children.count > 0 would
// change which rows show a disclosure triangle. Asserted so that stays true.
void test_an_expandable_row_can_have_no_children ()
{
	BEEntry* support = child_named(child_named(BEEntry.bundlesRoot, @"Fixtures Bundle"), @"Support");
	OAK_ASSERT(support);
	OAK_ASSERT(support.hasChildren);        // not a leaf…
	OAK_ASSERT_EQ(support.children.count, 0); // …and yet empty

	// A row that really is a leaf answers NO, so the two are genuinely distinct
	// and this test cannot pass by everything being expandable.
	BEEntry* grammar = child_named(child_named(BEEntry.bundlesRoot, @"Fixtures Bundle"), @"Language Grammars");
	OAK_ASSERT(!child_named(grammar, @"Test Grammar").hasChildren);
}

// ================
// = Identifiers  =
// ================

// The identifier is what the editor re-finds a selection by after the tree is
// rebuilt, and it is deliberately NOT the name: an item identifies by UUID so a
// rename does not lose the selection, while a menu entry identifies by name
// because it has no identity of its own.
void test_identifiers_are_uuid_for_items_and_name_for_menus ()
{
	BEEntry* bundle = child_named(BEEntry.bundlesRoot, @"Fixtures Bundle");

	BEEntry* grammar = child_named(child_named(bundle, @"Language Grammars"), @"Test Grammar");
	OAK_ASSERT_EQ(to_s(grammar.identifier), to_s(Grammar->uuid()));

	OAK_ASSERT_EQ(to_s(child_named(bundle, @"Menu Actions").identifier), "Menu Actions");
}

// Two separately-built trees describe the same rows. The Bundle Editor rebuilds
// wholesale on every index change and restores the selection by identifier, so
// this is the property that makes that work — and it is why BEEntry is not
// interned: the objects deliberately do not survive, only the identifiers do.
void test_identifiers_are_stable_across_a_rebuild ()
{
	BEEntry* first  = child_named(BEEntry.bundlesRoot, @"Fixtures Bundle");
	BEEntry* second = child_named(BEEntry.bundlesRoot, @"Fixtures Bundle");

	OAK_ASSERT(first != second); // genuinely distinct objects
	OAK_ASSERT_EQ(to_s(first.identifier), to_s(second.identifier));

	OAK_ASSERT_EQ(to_s(child_named(first, @"Settings").identifier),
	              to_s(child_named(second, @"Settings").identifier));
}
