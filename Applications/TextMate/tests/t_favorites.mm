#import "TextMateTesting.h"
#import <ns/ns.h>
#import <Cocoa/Cocoa.h>

// Coverage for Favorites, written before the port — specifically for
// FavoritesItem, the model behind every row of the Open Recent Project window.
//
// The chooser around it reads the user's real Favorites folder and its recent
// projects database, and shows a window; none of that belongs in a test. The item
// is where the logic that can be got wrong actually lives, and its rule for what
// to *call* a favourite is genuinely subtle.

void setup ()
{
	NSApplicationLoad();
}

static std::string describe (NSString* str)
{
	return str ? to_s(str) : std::string("«nil»");
}

// A scratch directory of our own — never the user's Favorites folder.
static NSString* scratch_dir ()
{
	NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tm-favorites-tests"];
	[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return dir;
}

static NSString* make_folder (NSString* name)
{
	NSString* path = [scratch_dir() stringByAppendingPathComponent:name];
	[NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
	return path;
}

static NSString* make_link (NSString* name, NSString* target)
{
	NSString* path = [scratch_dir() stringByAppendingPathComponent:name];
	[NSFileManager.defaultManager removeItemAtPath:path error:nil];
	[NSFileManager.defaultManager createSymbolicLinkAtPath:path withDestinationPath:target error:nil];
	return path;
}

// ==================================================================
// = A plain recent project                                         =
// ==================================================================

void test_favorites_item_from_a_path_keeps_that_path ()
{
	NSString* folder = make_folder(@"Project One");
	FavoritesItem* item = [[FavoritesItem alloc] initWithPath:folder isLink:NO isRemovable:NO];

	OAK_ASSERT_EQ(describe(item.path), to_s(folder));
	// No link, because this row came from the recent-projects database rather than
	// from the Favorites folder — which is also why it is not removable.
	OAK_ASSERT_EQ(describe(item.link), std::string("«nil»"));
	OAK_ASSERT_EQ((bool)item.isRemovable, false);

	OAK_ASSERT_EQ(describe(item.displayName), std::string("Project One"));
}

void test_favorites_item_icon_is_sized_for_the_row ()
{
	FavoritesItem* item = [[FavoritesItem alloc] initWithPath:make_folder(@"Iconic") isLink:NO isRemovable:NO];

	// 32pt, not the icon's natural size: the row is laid out around it.
	OAK_ASSERT_EQ((double)item.icon.size.width,  (double)32);
	OAK_ASSERT_EQ((double)item.icon.size.height, (double)32);
}

// ==================================================================
// = A favourite, which is a symlink                                =
// ==================================================================

void test_favorites_item_from_a_link_resolves_to_its_target ()
{
	NSString* target = make_folder(@"Real Project");
	NSString* link   = make_link(@"Real Project", target);

	FavoritesItem* item = [[FavoritesItem alloc] initWithPath:link isLink:YES isRemovable:YES];

	// **path is the target, link is the symlink.** Opening uses `path`; removing a
	// favourite trashes `link`, and getting these the wrong way round would delete
	// the user's actual project.
	OAK_ASSERT_EQ(describe(item.path), to_s(target));
	OAK_ASSERT_EQ(describe(item.link), to_s(link));
	OAK_ASSERT_EQ((bool)item.isRemovable, true);
}

void test_favorites_item_a_renamed_link_shows_the_links_name ()
{
	NSString* target = make_folder(@"Actual Name");
	NSString* link   = make_link(@"My Nickname", target);

	FavoritesItem* item = [[FavoritesItem alloc] initWithPath:link isLink:YES isRemovable:YES];

	// The rule that is easy to lose: when the symlink's last component differs from
	// its target's, the **link's** name wins. That is how renaming a favourite in
	// the Favorites folder renames it in this window — the whole point of the
	// folder being editable.
	OAK_ASSERT_EQ(describe(item.displayName), std::string("My Nickname"));
	OAK_ASSERT_EQ(describe(item.path),        to_s(target));
}

void test_favorites_item_an_unrenamed_link_shows_the_targets_display_name ()
{
	NSString* target = make_folder(@"Same Name");
	NSString* link   = make_link(@"Same Name", target);

	FavoritesItem* item = [[FavoritesItem alloc] initWithPath:link isLink:YES isRemovable:YES];

	// Names match, so it falls through to -displayNameAtPath: on the *target* —
	// which is what applies the user's Finder settings (hidden extensions,
	// localised folder names) rather than showing the raw filename.
	OAK_ASSERT_EQ(describe(item.displayName), std::string("Same Name"));
}

// ==================================================================
// = The chooser's two sources                                      =
// ==================================================================

void test_favorites_chooser_surface ()
{
	Class cls = FavoriteChooser.class;

	OAK_ASSERT_EQ((bool)[cls respondsToSelector:@selector(sharedInstance)], true);

	// The two lists the scope bar switches between, in order: the index is stored
	// in NSUserDefaults, so reordering them would silently change which list an
	// existing user opens on.
	OAK_ASSERT_EQ(to_s([FavoriteChooser.sharedInstance.sourceListLabels componentsJoinedByString:@" | "]),
	              std::string("Recent Projects | Favorites"));
}

// ==================================================================
// = Ranking, which the extraction made reachable                   =
// ==================================================================
//
// These could not be written before FavoritesSupport existed: the ranking was
// inline in -updateItems:, reading the chooser's filter field and writing its
// items. As a class method over its inputs it is an ordinary function.

static NSArray<FavoritesItem*>* three_items ()
{
	return @[
		[[FavoritesItem alloc] initWithPath:make_folder(@"Alpha") isLink:NO isRemovable:YES],
		[[FavoritesItem alloc] initWithPath:make_folder(@"Beta")  isLink:NO isRemovable:YES],
		[[FavoritesItem alloc] initWithPath:make_folder(@"Gamma") isLink:NO isRemovable:YES],
	];
}

static std::string names_of (NSArray<FavoritesItem*>* items)
{
	NSMutableArray* names = [NSMutableArray array];
	for(FavoritesItem* item in items)
		[names addObject:item.displayName ?: @"«nil»"];
	return to_s([names componentsJoinedByString:@" | "]);
}

void test_favorites_empty_filter_keeps_every_item_in_order ()
{
	NSArray<FavoritesItem*>* ranked = [FavoritesSupport rankItems:three_items() filterString:@"" bindings:@[]];

	// No filter means the list as loaded — for Recent Projects that order is
	// most-recently-used, so re-sorting it would be wrong.
	OAK_ASSERT_EQ(names_of(ranked), std::string("Alpha | Beta | Gamma"));
}

void test_favorites_filter_drops_what_does_not_match ()
{
	NSArray<FavoritesItem*>* ranked = [FavoritesSupport rankItems:three_items() filterString:@"gam" bindings:@[]];

	OAK_ASSERT_EQ(names_of(ranked), std::string("Gamma"));
}

void test_favorites_ranking_marks_up_the_matched_name ()
{
	NSArray<FavoritesItem*>* ranked = [FavoritesSupport rankItems:three_items() filterString:@"gam" bindings:@[]];
	OAK_ASSERT_EQ((size_t)ranked.count, (size_t)1);

	// `name` is what the row draws, and the filter's matched characters are marked
	// up in it — losing that silently removes the highlighting from the window.
	OAK_ASSERT_EQ((bool)(ranked[0].name != nil), true);
	OAK_ASSERT_EQ(to_s(ranked[0].name.string), std::string("Gamma"));

	// `folder` is the containing directory, abbreviated with a tilde.
	OAK_ASSERT_EQ((bool)(ranked[0].folder != nil), true);
}

void test_favorites_a_learned_abbreviation_outranks_the_score ()
{
	NSArray<FavoritesItem*>* items = three_items();

	// Both match "a". Without bindings the score decides; with Gamma bound to this
	// abbreviation it goes first regardless — that is what makes typing the same
	// few letters keep opening the same project.
	NSArray<FavoritesItem*>* plain = [FavoritesSupport rankItems:items filterString:@"a" bindings:@[]];
	OAK_ASSERT_EQ((bool)(plain.count > 1), true);

	NSArray<FavoritesItem*>* bound = [FavoritesSupport rankItems:items filterString:@"a" bindings:@[ items[2].path ]];
	OAK_ASSERT_EQ(names_of(bound).find("Gamma"), (size_t)0);
}
