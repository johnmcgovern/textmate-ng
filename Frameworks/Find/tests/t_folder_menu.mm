#import "FindTesting.h"
#import <Cocoa/Cocoa.h>
#import <sys/stat.h>

// Pins for FFFolderMenu, written against the ObjC++ and before its port (rule
// 18, rule 5, rule 40).
//
// FFFolderMenu is the delegate behind the folder rows of Find's "In:" pop-up:
// a lazily-populated submenu of a directory's subfolders, each of which gets a
// submenu of its own if it has subfolders, and — on the root menu only — an
// "Enclosing Folders" section walking up to "/". It had no test. What it does
// is filesystem filtering and sort order, which is exactly the kind of thing a
// port changes silently: the sort is Finder-like (case-insensitive, numeric-
// aware, on the *stem*), and four kinds of entry are skipped for four different
// reasons. Every one of those has a directory in the fixture below.
//
// Everything here is driven through the delegate method directly, on menus
// that never open. NSMenu does not need a window for any of it.

void setup ()
{
	NSApplicationLoad();
}

// =============
// = Fixture   =
// =============

// A fresh directory tree per call. The names are chosen so that each sort
// rule and each skip rule has exactly one witness:
//
//   alpha, Beta       — case-insensitive ordering puts alpha first; a plain
//                       compare would put Beta first
//   item2, item10     — numeric-aware ordering; a plain compare reverses them
//   same.zzz, same-1  — sorted on the stem ("same" < "same-1"); the full name
//                       would order them the other way ('-' < '.')
//   Beta/inner        — the one subfolder, so Beta alone gets a submenu
//   notes.txt         — a file
//   .git              — a dot-directory (the "*" glob skips these)
//   flagged           — UF_HIDDEN
//   Bundle.app        — a package
//   link              — a symlink to a directory
static NSString* Fixture ()
{
	NSString* base = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"tm-find-folder-menu-%d", getpid()]];
	NSString* root = [base stringByAppendingPathComponent:@"root"];

	NSFileManager* fm = NSFileManager.defaultManager;
	[fm removeItemAtPath:base error:nil];

	for(NSString* dir in @[ @"alpha", @"Beta", @"Beta/inner", @"item2", @"item10", @"same.zzz", @"same-1", @".git", @"flagged", @"Bundle.app" ])
		[fm createDirectoryAtPath:[root stringByAppendingPathComponent:dir] withIntermediateDirectories:YES attributes:nil error:nil];

	[@"x" writeToFile:[root stringByAppendingPathComponent:@"notes.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
	[fm createSymbolicLinkAtPath:[root stringByAppendingPathComponent:@"link"] withDestinationPath:@"alpha" error:nil];
	chflags([root stringByAppendingPathComponent:@"flagged"].fileSystemRepresentation, UF_HIDDEN);

	return root;
}

// A root menu with one item whose submenu FFFolderMenu owns, the way Find.swift
// builds the "In:" pop-up: the item carries an action and a target, and the
// submenu's entries are expected to inherit both.
static NSMenuItem* FolderItem (NSString* path, id target)
{
	NSMenu* root = [[NSMenu alloc] initWithTitle:@"Where"];
	NSMenuItem* item = [root addItemWithTitle:@"Folder" action:@selector(orderFront:) keyEquivalent:@""];
	item.target = target;
	[FFFolderMenu addSubmenuForDirectoryAtPath:path toMenuItem:item];
	return item;
}

static NSArray<NSString*>* RepresentedPaths (NSMenu* menu, NSRange range)
{
	NSMutableArray* res = [NSMutableArray array];
	for(NSUInteger i = range.location; i < NSMaxRange(range); ++i)
		[res addObject:[menu itemAtIndex:i].representedObject ?: @""];
	return res;
}

static NSUInteger IndexOfSeparator (NSMenu* menu)
{
	for(NSInteger i = 0; i < menu.numberOfItems; ++i)
	{
		if([menu itemAtIndex:i].isSeparatorItem)
			return i;
	}
	return NSNotFound;
}

// MARK: - Selector surface (rule 18)

void test_folder_menu_answers_its_public_selectors ()
{
	OAK_ASSERT([FFFolderMenu respondsToSelector:@selector(sharedInstance)]);
	OAK_ASSERT([FFFolderMenu respondsToSelector:@selector(addSubmenuForDirectoryAtPath:toMenuItem:)]);

	NSArray<NSString*>* const required = @[
		@"addSubmenuForDirectoryAtPath:toMenuItem:",
		@"menuNeedsUpdate:",
		@"menuHasKeyEquivalent:forEvent:target:action:",
	];

	NSMutableArray* missing = [NSMutableArray array];
	for(NSString* name in required)
	{
		if(![FFFolderMenu instancesRespondToSelector:NSSelectorFromString(name)])
			[missing addObject:name];
	}
	OAK_ASSERT_EQ(std::string([missing componentsJoinedByString:@", "].UTF8String), std::string(""));
}

void test_shared_instance_is_one_object ()
{
	OAK_ASSERT(FFFolderMenu.sharedInstance != nil);
	OAK_ASSERT(FFFolderMenu.sharedInstance == FFFolderMenu.sharedInstance);
}

// MARK: - Attaching a submenu

// Attaching is cheap and lazy: the item learns its path, gets an empty submenu,
// and the shared instance becomes that submenu's delegate. Nothing is listed
// until AppKit asks.
void test_attaching_sets_path_and_an_empty_delegated_submenu ()
{
	NSString* root = Fixture();
	NSMenuItem* item = FolderItem(root, nil);

	OAK_ASSERT([item.representedObject isEqualToString:root]);
	OAK_ASSERT(item.submenu != nil);
	OAK_ASSERT(item.submenu.delegate == FFFolderMenu.sharedInstance);
	OAK_ASSERT_EQ((size_t)item.submenu.numberOfItems, (size_t)0);
}

// MARK: - Listing subfolders

void test_subfolders_are_listed_in_finder_order ()
{
	NSString* root = Fixture();
	NSMenuItem* item = FolderItem(root, nil);
	[FFFolderMenu.sharedInstance menuNeedsUpdate:item.submenu];

	NSArray<NSString*>* expected = @[
		[root stringByAppendingPathComponent:@"alpha"],
		[root stringByAppendingPathComponent:@"Beta"],
		[root stringByAppendingPathComponent:@"item2"],
		[root stringByAppendingPathComponent:@"item10"],
		[root stringByAppendingPathComponent:@"same.zzz"],
		[root stringByAppendingPathComponent:@"same-1"],
	];

	NSUInteger separator = IndexOfSeparator(item.submenu);
	OAK_ASSERT(separator != NSNotFound);
	NSArray<NSString*>* actual = RepresentedPaths(item.submenu, NSMakeRange(0, separator));
	OAK_ASSERT_EQ(std::string([actual componentsJoinedByString:@"\n"].UTF8String), std::string([expected componentsJoinedByString:@"\n"].UTF8String));
}

// The four skip rules, each by name. Listed separately from the order test so a
// failure names the entry that leaked rather than diffing a whole list.
void test_files_dot_directories_hidden_flags_packages_and_symlinks_are_skipped ()
{
	NSString* root = Fixture();
	NSMenuItem* item = FolderItem(root, nil);
	[FFFolderMenu.sharedInstance menuNeedsUpdate:item.submenu];

	NSMutableArray* names = [NSMutableArray array];
	for(NSMenuItem* entry in item.submenu.itemArray)
	{
		if(entry.representedObject)
			[names addObject:[entry.representedObject lastPathComponent]];
	}

	for(NSString* skipped in @[ @"notes.txt", @".git", @"flagged", @"Bundle.app", @"link" ])
		OAK_ASSERT_EQ(std::string([[names filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF == %@", skipped]] componentsJoinedByString:@","].UTF8String), std::string(""));
}

// Each entry shows the folder's display name, carries an icon, and inherits the
// parent item's action and target — that is how selecting one of them fires the
// same handler as the parent row does.
void test_entries_inherit_action_and_target_and_carry_an_icon ()
{
	NSString* root = Fixture();
	NSObject* target = [NSObject new];
	NSMenuItem* item = FolderItem(root, target);
	[FFFolderMenu.sharedInstance menuNeedsUpdate:item.submenu];

	NSMenuItem* first = [item.submenu itemAtIndex:0];
	OAK_ASSERT([first.title isEqualToString:@"alpha"]);
	OAK_ASSERT(first.action == @selector(orderFront:));
	OAK_ASSERT(first.target == target);
	OAK_ASSERT(first.image != nil);
	OAK_ASSERT([first.keyEquivalent isEqualToString:@""]);
}

// Only a folder that itself has subfolders gets a submenu — and that submenu is
// again lazy, delegated, and empty until asked.
void test_only_folders_with_subfolders_get_a_submenu ()
{
	NSString* root = Fixture();
	NSMenuItem* item = FolderItem(root, nil);
	[FFFolderMenu.sharedInstance menuNeedsUpdate:item.submenu];

	NSMenuItem* alpha = [item.submenu itemAtIndex:0];
	NSMenuItem* beta  = [item.submenu itemAtIndex:1];
	OAK_ASSERT([beta.title isEqualToString:@"Beta"]);

	OAK_ASSERT(alpha.submenu == nil);
	OAK_ASSERT(beta.submenu != nil);
	OAK_ASSERT(beta.submenu.delegate == FFFolderMenu.sharedInstance);
	OAK_ASSERT_EQ((size_t)beta.submenu.numberOfItems, (size_t)0);
}

// A nested submenu lists its folder's subfolders and nothing else: no
// separator and no "Enclosing Folders" — those belong to the root menu only.
void test_a_nested_submenu_has_no_enclosing_folders_section ()
{
	NSString* root = Fixture();
	NSObject* target = [NSObject new];
	NSMenuItem* item = FolderItem(root, target);
	[FFFolderMenu.sharedInstance menuNeedsUpdate:item.submenu];

	NSMenuItem* beta = [item.submenu itemAtIndex:1];
	[FFFolderMenu.sharedInstance menuNeedsUpdate:beta.submenu];

	OAK_ASSERT_EQ((size_t)beta.submenu.numberOfItems, (size_t)1);
	NSMenuItem* inner = [beta.submenu itemAtIndex:0];
	OAK_ASSERT([inner.representedObject isEqualToString:[root stringByAppendingPathComponent:@"Beta/inner"]]);
	OAK_ASSERT(inner.action == @selector(orderFront:));
	OAK_ASSERT(inner.target == target);
	OAK_ASSERT(inner.submenu == nil);
}

// AppKit calls -menuNeedsUpdate: every time the menu opens. The listing is done
// once; a second call must not double the entries.
void test_a_populated_menu_is_not_repopulated ()
{
	NSString* root = Fixture();
	NSMenuItem* item = FolderItem(root, nil);
	[FFFolderMenu.sharedInstance menuNeedsUpdate:item.submenu];
	NSInteger count = item.submenu.numberOfItems;
	[FFFolderMenu.sharedInstance menuNeedsUpdate:item.submenu];
	OAK_ASSERT_EQ((size_t)item.submenu.numberOfItems, (size_t)count);
}

// MARK: - Enclosing folders

// Below the subfolders: a separator, a disabled-by-selector "Enclosing Folders"
// caption, then every ancestor up to and including "/". The immediate parent is
// the only one with a key equivalent (↑) and it goes through -goToParentFolder:
// with a nil target — the responder chain finds Find — while the rest fire the
// parent item's own action and target like the subfolder rows do.
void test_root_menu_ends_with_the_enclosing_folders ()
{
	NSString* root = Fixture();
	NSObject* target = [NSObject new];
	NSMenuItem* item = FolderItem(root, target);
	[FFFolderMenu.sharedInstance menuNeedsUpdate:item.submenu];

	NSUInteger separator = IndexOfSeparator(item.submenu);
	OAK_ASSERT(separator != NSNotFound);

	NSMenuItem* caption = [item.submenu itemAtIndex:separator+1];
	OAK_ASSERT([caption.title isEqualToString:@"Enclosing Folders"]);
	OAK_ASSERT(caption.action == NSSelectorFromString(@"nop:"));
	OAK_ASSERT(caption.representedObject == nil);

	NSMutableArray<NSString*>* expected = [NSMutableArray array];
	for(NSString* path = root.stringByDeletingLastPathComponent; ; path = path.stringByDeletingLastPathComponent)
	{
		[expected addObject:path];
		if([path isEqualToString:@"/"])
			break;
	}
	OAK_ASSERT(expected.count >= 3); // a temp dir is never directly under /

	NSArray<NSString*>* actual = RepresentedPaths(item.submenu, NSMakeRange(separator+2, item.submenu.numberOfItems - (separator+2)));
	OAK_ASSERT_EQ(std::string([actual componentsJoinedByString:@"\n"].UTF8String), std::string([expected componentsJoinedByString:@"\n"].UTF8String));

	NSMenuItem* parent = [item.submenu itemAtIndex:separator+2];
	OAK_ASSERT([parent.keyEquivalent isEqualToString:@""]);
	OAK_ASSERT(parent.action == NSSelectorFromString(@"goToParentFolder:"));
	OAK_ASSERT(parent.target == nil);
	OAK_ASSERT(parent.image != nil);

	NSMenuItem* grandparent = [item.submenu itemAtIndex:separator+3];
	OAK_ASSERT([grandparent.keyEquivalent isEqualToString:@""]);
	OAK_ASSERT(grandparent.action == @selector(orderFront:));
	OAK_ASSERT(grandparent.target == target);

	NSMenuItem* last = item.submenu.itemArray.lastObject;
	OAK_ASSERT([last.representedObject isEqualToString:@"/"]);
}

// A folder that cannot be listed still gets its enclosing folders — that is
// how a stale "last folder" stays navigable — and, with no entries above it,
// no separator either.
void test_an_unlistable_folder_yields_only_its_enclosing_folders ()
{
	NSMenuItem* item = FolderItem(@"/tm-find-tests-absent/gone", nil);
	[FFFolderMenu.sharedInstance menuNeedsUpdate:item.submenu];

	OAK_ASSERT_EQ((size_t)item.submenu.numberOfItems, (size_t)3);
	OAK_ASSERT(IndexOfSeparator(item.submenu) == NSNotFound);
	OAK_ASSERT([[item.submenu itemAtIndex:0].title isEqualToString:@"Enclosing Folders"]);
	OAK_ASSERT([[item.submenu itemAtIndex:1].representedObject isEqualToString:@"/tm-find-tests-absent"]);
	OAK_ASSERT([[item.submenu itemAtIndex:2].representedObject isEqualToString:@"/"]);
}

// Deliberately not pinned: the fallback to NSHomeDirectory() when the parent
// item carries no path. Exercising it lists the home directory, and on this
// macOS that can raise a privacy prompt inside the test runner for Desktop or
// Documents. The port carries the fallback; nothing in the app reaches it,
// because -addSubmenuForDirectoryAtPath:toMenuItem: always sets the path.

// MARK: - Key equivalents

// Answering NO is what keeps AppKit from populating every folder submenu on
// each key press to look for a matching key equivalent.
void test_key_equivalent_lookup_is_declined ()
{
	NSEvent* event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"a" charactersIgnoringModifiers:@"a" isARepeat:NO keyCode:0];
	id target = nil;
	SEL action = NULL;
	OAK_ASSERT([FFFolderMenu.sharedInstance menuHasKeyEquivalent:[NSMenu new] forEvent:event target:&target action:&action] == NO);
}
