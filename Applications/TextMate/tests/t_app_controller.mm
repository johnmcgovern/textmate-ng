#import "TextMateTesting.h"
#import <MenuBuilder/MenuBuilder.h>
#import <ns/ns.h>
#import <regexp/find.h>
#import <theme/theme.h>
#import <objc/runtime.h>
#import <Cocoa/Cocoa.h>

// A pin for AppController, written against the ObjC++ and before any port of it
// (rule 18, rule 5, rule 40). AppController is the application delegate and the
// last stop on the responder chain, so two whole classes of defect here are
// invisible to the compiler and to a green suite: a menu item that quietly stops
// being built, and an action selector whose Swift spelling does not match the one
// -targetForAction: looks up. Either shows as a greyed-out or missing menu item
// and nothing else.
//
// The scale is why this is a dump comparison rather than a list of spot checks:
// -mainMenu is 335 lines of MBMenu DSL describing 248 items and naming 143
// distinct selectors. Spot-checking that is not a pin.
//
// MBDumpMenu is what makes it affordable. It renders a live NSMenu back into the
// MBMenu DSL, it was already exported from MenuBuilder, and it had no callers at
// all before this file. Two runs of the unmodified menu produce byte-identical
// output, which is what a golden needs.
//
// WHAT IS DELIBERATELY NOT PINNED HERE
//
//   * The find-option *states*. -validateMenuItem: reads
//     `OakPasteboard.findPasteboard`, which is backed by NSPasteboard(name: .find)
//     — the system-wide find pasteboard, shared with every other application on
//     the machine, plus a database. A test must not write to it (rule 53, and
//     worse than rule 53: the state is not even process-local). The tag→option
//     mapping those branches switch on is pinned instead, by value, below.
//
//   * The delegate-filled submenus — Bundles, Theme, Spelling, Wrap Column, Show
//     Tab. They are empty until -menuNeedsUpdate: runs, which needs a loaded
//     bundle index; no bundle index loads in a test process (rule 40's vacuous
//     test, already recorded in the FileBrowser work). The golden pins that they
//     are built, wired to a delegate, and empty; it cannot pin their contents.
//
//   * The two IBOutlet ivars, `goToLinePanel` and `goToLineTextField`. They are
//     ivars, not properties, so they expose no selector to assert on. They are
//     also the port hazard in this file that nothing here can catch: MainMenu.xib
//     binds them by name, and a Swift port that renames them — or declares them
//     without @IBOutlet — leaves them nil, at which point Go To Line opens
//     nothing and reports no error. Check it in the app (rule 8).

void setup ()
{
	NSApplicationLoad();
}

// MARK: - The menu shape

// One build per process, and it is not an optimisation.
//
// MBCreateMenu does not just return a menu: for `.systemMenu` items it assigns
// four **process-global** AppKit properties — NSApp.servicesMenu, .windowsMenu,
// .helpMenu and NSFontManager.sharedFontManager.fontMenu — and MBDumpMenu prints
// `.systemMenu = …` by comparing a submenu against those globals. So a second
// -mainMenu in the same process dumps differently from the first: the Services
// submenu of build #2 is no longer the one NSApp holds, and prints as a plain
// delegate-owned submenu instead. That cost a confusing failure at menu line 11.
//
// Building once also matches the app, which calls -mainMenu exactly once from
// -applicationWillFinishLaunching:. If a test ever needs a second independent
// build, the globals have to be saved and restored around it (rule 53).
static NSMenu* shared_main_menu ()
{
	static NSMenu* menu = [[AppController new] mainMenu];
	return menu;
}


static std::string normalised_dump (NSMenu* menu)
{
	NSMutableString* str = [MBDumpMenu(menu) mutableCopy];

	// `.image` is not an MBMenuItem field — it cannot be authored, and AppKit
	// assigns SF Symbols to standard selectors on its own, differently by macOS
	// version. Pin what the DSL specifies; drop what the system decorates.
	for(NSString* form in @[ @", .image = «unknown»", @".image = «unknown», ", @".image = «unknown»" ])
		[str replaceOccurrencesOfString:form withString:@"" options:0 range:NSMakeRange(0, str.length)];

	// Collapse the column padding. MBDumpMenu aligns titles and selectors into
	// columns, which puts trailing spaces on some lines — and a checked-in golden
	// that depends on trailing whitespace surviving every editor is a trap. The
	// widths are derived from the titles and selectors this test already compares
	// character by character, so nothing is lost by dropping them.
	NSMutableArray* lines = [NSMutableArray array];
	for(NSString* line in [str componentsSeparatedByString:@"\n"])
	{
		NSUInteger tabs = 0;
		while(tabs < line.length && [line characterAtIndex:tabs] == '\t')
			++tabs;

		NSMutableArray* kept = [NSMutableArray array];
		for(NSString* word in [[line substringFromIndex:tabs] componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet])
		{
			if(word.length)
				[kept addObject:word];
		}

		[lines addObject:[[line substringToIndex:tabs] stringByAppendingString:[kept componentsJoinedByString:@" "]]];
	}
	return to_s([lines componentsJoinedByString:@"\n"]);
}

// Compare line by line. OAK_ASSERT_EQ on a 330-line string prints both of them
// and leaves the reader to find the difference; the first differing line is the
// whole answer.
static void assert_same_dump (std::string const& actual, std::string const& expected)
{
	NSArray* got  = [to_ns(actual)   componentsSeparatedByString:@"\n"];
	NSArray* want = [to_ns(expected) componentsSeparatedByString:@"\n"];

	for(NSUInteger i = 0; i < MIN(got.count, want.count); ++i)
	{
		if(![got[i] isEqualToString:want[i]])
			OAK_FAIL(oak_format("menu line %lu:\n  expected: %s\n  actual:   %s", (unsigned long)i+1, to_s((NSString*)want[i]).c_str(), to_s((NSString*)got[i]).c_str()));
	}
	OAK_ASSERT_EQ((size_t)got.count, (size_t)want.count);
}

// The app name is interpolated into four titles, and it comes from CFBundleName
// so that the fork's name lives in one place. In this bundle the running host is
// xctest, which is why the golden below says “About xctest” rather than “About
// TextMate-NG”. Asserting the mechanism separately means a changed test host
// shows up here, as one legible failure, rather than as 330 mystery diffs.
void test_app_controller_menu_titles_use_the_bundle_name ()
{
	NSString* appName = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"] ?: @"TextMate";
	OAK_ASSERT(([appName isEqualToString:@"xctest"]));

	NSMenu* appMenu = [shared_main_menu() itemAtIndex:0].submenu;
	OAK_ASSERT(([[appMenu itemAtIndex:0].title isEqualToString:@"About xctest"]));
	OAK_ASSERT(([appMenu.itemArray.lastObject.title isEqualToString:@"Quit xctest"]));
}


// MARK: - The goldens
//
// The dumps live in tests/fixtures/ rather than in a string literal here, and
// that is forced rather than stylistic: ide/gen_xctest.rb emits a
// `#line N "<path>"` directive before **every** line of a test file when it
// inlines it, so any multi-line literal — raw or otherwise — arrives at the
// compiler with #line directives spliced through its middle. The first attempt
// at this file failed with `expected: #line 122 "…/t_app_controller.mm"` as the
// menu's second line, which reads as nonsense until you look at the generated
// _impl.mm. Same family as rules 29 and 34: the harness rewrites test files, and
// what it does is not visible from the file you are editing.
//
// Reading them back through __FILE__ is the repo's existing fixture pattern
// (network/tests/t_download.cc), and the #line rewriting is exactly what keeps
// __FILE__ pointing at the source tree. It also makes the golden a reviewable
// file in a diff instead of 330 lines of literal.
//
// REGENERATING: run the app-target tests with the dump printed to stderr and
// paste the output in whole. Never patch a fixture line to match a failure — a
// wrong golden is worth less than no golden.
static std::string golden (NSString* name)
{
	NSString* dir  = [[NSString stringWithUTF8String:__FILE__] stringByDeletingLastPathComponent];
	NSString* path = [[dir stringByAppendingPathComponent:@"fixtures"] stringByAppendingPathComponent:name];

	NSError* error = nil;
	NSString* text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
	OAK_MASSERT(oak_format("cannot read %s: %s", to_s(path).c_str(), to_s([error localizedDescription]).c_str()), text != nil);
	return to_s(text);
}

// 248 items, 12 top-level menus, 143 distinct selectors.
void test_app_controller_main_menu_is_unchanged ()
{
	assert_same_dump(normalised_dump(shared_main_menu()), golden(@"AppControllerMainMenu.txt"));
}

// Two items, and the only place in AppController that sets `.target` — the dock
// menu is shown with no key window, so the responder chain cannot be relied on.
// `«unknown»` is the controller itself: MBDumpMenu names NSApp, the font manager
// and NSApp.delegate, and this controller is none of those under test.
void test_app_controller_dock_menu_is_unchanged ()
{
	assert_same_dump(normalised_dump([[AppController new] applicationDockMenu:NSApp]), golden(@"AppControllerDockMenu.txt"));
}

// MARK: - The selector surface (rule 18)

static void collect_selectors (NSMenu* menu, NSMutableSet* into)
{
	for(NSMenuItem* item in menu.itemArray)
	{
		if(item.action)
			[into addObject:NSStringFromSelector(item.action)];
		if(item.submenu)
			collect_selectors(item.submenu, into);
	}
}

static std::string sorted_lines (NSArray* strings)
{
	return to_s([[strings sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"\n"]);
}

// Of the 143 selectors the menu names, AppController answers exactly these 15;
// the other 128 are dispatched down the responder chain to OakTextView,
// DocumentWindowController, the file browser and NSApp.
//
// Set *equality* rather than a respondsToSelector: loop, because both directions
// are defects. One fewer and a menu item greys out. One more and AppController
// has started swallowing an action that belonged to the document window — which
// is the harder bug to find, because the item stays enabled and does the wrong
// thing.
void test_app_controller_answers_exactly_its_menu_selectors ()
{
	NSMutableSet* all = [NSMutableSet set];
	collect_selectors(shared_main_menu(), all);
	collect_selectors([[AppController new] applicationDockMenu:NSApp], all);
	OAK_ASSERT_EQ((size_t)all.count, (size_t)143);

	NSMutableArray* answered = [NSMutableArray array];
	for(NSString* name in all)
	{
		if([AppController instancesRespondToSelector:NSSelectorFromString(name)])
			[answered addObject:name];
	}

	OAK_ASSERT_EQ(sorted_lines(answered), sorted_lines(@[
		@"newDocument:",
		@"newDocumentAndActivate:",
		@"newFileBrowser:",
		@"openDocument:",
		@"openDocumentAndActivate:",
		@"openFavorites:",
		@"orderFrontAboutPanel:",
		@"orderFrontFindPanel:",
		@"orderFrontGoToLinePanel:",
		@"performSoftwareUpdateCheck:",
		@"runPageLayout:",
		@"showBundleEditor:",
		@"showBundleItemChooser:",
		@"showPreferences:",
		@"toggleFindOption:",
	]));
}

// The other half of rule 18, and the half no menu dump can reach: selectors sent
// to AppController by name from somewhere else. Every one of these is an
// -[NSApp sendAction:] from another framework, a target/action assigned at run
// time, a nib connection, or a delegate/protocol method AppKit calls. None of
// them appears in any menu, so the test above would not miss one.
//
// Where each comes from:
//   handleTxMtURL:                       GetURLScriptCommand.mm, OakHTMLOutputView.swift
//   editBundleItemWithUUIDString:        OakTextView.mm, InstallBundleItems.mm
//   performBundleItemWithUUIDStringFrom: OakMainMenu.mm, BundleItemChooserSupport.mm
//   performBundleItem:                   the responder chain, C++-typed
//   didSelectFavorite:                   assigned to FavoriteChooser.action
//   bundleItemChooserDidSelectItems:     assigned to BundleItemChooser.action
//   editBundleItem:                      assigned to BundleItemChooser.editAction
//   performGoToLine:                     MainMenu.xib
//   take*ThemeUUIDFrom: / takeThemeAppearanceFrom:
//                                        built by -themesMenuNeedsUpdate:, so
//                                        they exist only once a bundle index has
//                                        loaded — which never happens in a test
//   the application*/menu* families      NSApplicationDelegate, NSMenuDelegate
//   userDefaultsDidChange:               OakUserDefaultsObserver
void test_app_controller_answers_the_selectors_reached_by_name ()
{
	NSMutableArray* missing = [NSMutableArray array];
	for(NSString* name in @[
		@"handleTxMtURL:",
		@"editBundleItem:",
		@"editBundleItemWithUUIDString:",
		@"performBundleItemWithUUIDStringFrom:",
		@"performBundleItem:",
		@"didSelectFavorite:",
		@"bundleItemChooserDidSelectItems:",
		@"performGoToLine:",
		@"takeThemeAppearanceFrom:",
		@"takeUniversalThemeUUIDFrom:",
		@"takeDarkThemeUUIDFrom:",
		@"validateMenuItem:",
		@"validateThemeMenuItem:",
		@"applicationWillFinishLaunching:",
		@"applicationDidFinishLaunching:",
		@"applicationShouldTerminate:",
		@"applicationDidUpdate:",
		@"applicationWillResignActive:",
		@"applicationWillBecomeActive:",
		@"applicationDidResignActive:",
		@"applicationDockMenu:",
		@"applicationOpenUntitledFile:",
		@"applicationShouldOpenUntitledFile:",
		@"applicationShouldHandleReopen:hasVisibleWindows:",
		@"application:openFile:",
		@"application:openFiles:",
		@"menuNeedsUpdate:",
		@"menuHasKeyEquivalent:forEvent:target:action:",
		@"bundlesMenuNeedsUpdate:",
		@"themesMenuNeedsUpdate:",
		@"spellingMenuNeedsUpdate:",
		@"wrapColumnMenuNeedsUpdate:",
		@"userDefaultsDidChange:",
	])
	{
		if(![AppController instancesRespondToSelector:NSSelectorFromString(name)])
			[missing addObject:name];
	}
	OAK_ASSERT_EQ(sorted_lines(missing), std::string(""));
}

// MARK: - The find-option tags (rule 5)

// The Find menu writes these tags as bare integer literals and -validateMenuItem:
// reads them back as find::options_t. That divergence is live today — it predates
// the port (upstream 7e69f5bb wrote the literals) and nothing has ever checked it.
// A renumbering of the C++ enum silently re-points four menu items at the wrong
// option, with no compiler error and no failing test.
static_assert(find::full_words         ==   1, "find::options_t renumbered");
static_assert(find::ignore_case        ==   2, "find::options_t renumbered");
static_assert(find::ignore_whitespace  ==   4, "find::options_t renumbered");
static_assert(find::regular_expression ==   8, "find::options_t renumbered");
static_assert(find::wrap_around        == 128, "find::options_t renumbered");

void test_find_option_menu_tags_are_the_cxx_enum_values ()
{
	NSMutableDictionary* tags = [NSMutableDictionary dictionary];
	NSMutableSet* items = [NSMutableSet set];
	NSMenu* menu = shared_main_menu();

	// Walk to the Find submenu rather than assuming an index.
	NSMutableArray* queue = [@[ menu ] mutableCopy];
	while(queue.count)
	{
		NSMenu* next = queue.firstObject;
		[queue removeObjectAtIndex:0];
		for(NSMenuItem* item in next.itemArray)
		{
			if(item.action == @selector(toggleFindOption:))
			{
				tags[item.title] = @(item.tag);
				[items addObject:item.title];
			}
			if(item.submenu)
				[queue addObject:item.submenu];
		}
	}

	OAK_ASSERT_EQ((size_t)tags.count, (size_t)4);
	OAK_ASSERT_EQ((int)[tags[@"Ignore Case"]        intValue], (int)find::ignore_case);
	OAK_ASSERT_EQ((int)[tags[@"Regular Expression"] intValue], (int)find::regular_expression);
	OAK_ASSERT_EQ((int)[tags[@"Ignore Whitespace"]  intValue], (int)find::ignore_whitespace);
	OAK_ASSERT_EQ((int)[tags[@"Wrap Around"]        intValue], (int)find::wrap_around);

	// find::full_words is the fifth case -validateMenuItem: handles and no menu
	// item carries it. Recorded rather than "fixed": the branch is reachable from
	// the Find window's own controls, and adding a Whole Word menu item is a
	// product decision, not a port one.
	for(NSNumber* tag in tags.allValues)
		OAK_ASSERT_NE((int)[tag intValue], (int)find::full_words);
}

// MARK: - Menu validation

// The branch of -validateMenuItem: that needs no process-global state. With no
// text view in the responder chain nothing answers -setSelectionString:, so Go To
// Line must be disabled — the item is in the Edit menu with no target, and it is
// AppController that decides.
void test_go_to_line_is_disabled_without_a_text_view ()
{
	AppController* controller = [AppController new];
	NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"Go to Line…" action:@selector(orderFrontGoToLinePanel:) keyEquivalent:@""];

	OAK_ASSERT_EQ((bool)([NSApp targetForAction:@selector(setSelectionString:)] != nil), false);
	OAK_ASSERT_EQ((bool)[controller validateMenuItem:item], false);
}

// Everything -validateMenuItem: does not recognise falls through to
// -validateThemeMenuItem:, which enables it. A port that inverts that default
// disables most of the menu bar at once, so it is worth one line.
void test_unrecognised_actions_stay_enabled ()
{
	AppController* controller = [AppController new];
	NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"Save" action:@selector(saveDocument:) keyEquivalent:@""];
	OAK_ASSERT_EQ((bool)[controller validateMenuItem:item], true);
}

// MARK: - The +initialize conversion (rule 24)

// A Swift class cannot provide +initialize, so this class must not regain one.
// The check is deliberately against AppController's *own* metaclass rather than
// +respondsToSelector:, which would answer YES for NSObject's implementation and
// pass no matter what.
void test_app_controller_declares_no_class_initialize ()
{
	unsigned int count = 0;
	Method* methods = class_copyMethodList(object_getClass([AppController class]), &count);

	NSMutableArray* names = [NSMutableArray array];
	for(unsigned int i = 0; i < count; ++i)
		[names addObject:NSStringFromSelector(method_getName(methods[i]))];
	free(methods);

	OAK_ASSERT_EQ((bool)[names containsObject:@"initialize"], false);
	OAK_ASSERT_EQ((bool)[names containsObject:@"setupThemeDefaultsAndObservers"], true);
}

// What +initialize used to do at nib-load time, now done explicitly from
// -applicationWillFinishLaunching:. Without these two registrations a machine
// whose owner never picked a theme opens documents with no highlighting — the
// same failure TMQLRender.mm spells its own fallbacks out to avoid, since a
// registration domain is private to the process that registers it.
//
// This writes NSRegistrationDomain, which is per-process and never persisted, so
// it cannot reach the user's real defaults (rule 53). It is also what +initialize
// already did in every test process that touched this class.
void test_setup_registers_the_theme_defaults ()
{
	[AppController setupThemeDefaultsAndObservers];

	OAK_ASSERT_EQ(to_s([NSUserDefaults.standardUserDefaults stringForKey:@"universalThemeUUID"]), std::string(kMacClassicThemeUUID));
	OAK_ASSERT_EQ(to_s([NSUserDefaults.standardUserDefaults stringForKey:@"darkModeThemeUUID"]),  std::string(kTwilightThemeUUID));

	// dispatch_once, so a second call must not re-register the observers. Nothing
	// here can count them; what it can check is that calling twice is not an error
	// and leaves the values alone.
	[AppController setupThemeDefaultsAndObservers];
	OAK_ASSERT_EQ(to_s([NSUserDefaults.standardUserDefaults stringForKey:@"universalThemeUUID"]), std::string(kMacClassicThemeUUID));
}

// MARK: - AppControllerSupport (rule 25's extraction, and rule 35's free test)

// A scratch marker of our own. Never AppControllerSupport.sessionRestoreMarkerPath:
// that is a fixed path shared with the running app, and a test that created one
// and then failed before cleaning up would make the next real launch offer to
// skip session restore (rule 53).
static NSString* scratch_marker (NSString* name)
{
	return [NSTemporaryDirectory() stringByAppendingPathComponent:[@"tm-marker-tests-" stringByAppendingString:name]];
}

void test_session_restore_marker_path_is_named_in_the_temp_directory ()
{
	NSString* path = AppControllerSupport.sessionRestoreMarkerPath;

	OAK_ASSERT_EQ(to_s(path.lastPathComponent), std::string("textmate_session_restore"));

	// path::temp() is confstr(_CS_DARWIN_USER_TEMP_DIR); the directory has to be
	// there already, since nothing creates it before the marker is written.
	BOOL isDirectory = NO;
	OAK_ASSERT_EQ((bool)[NSFileManager.defaultManager fileExistsAtPath:path.stringByDeletingLastPathComponent isDirectory:&isDirectory], true);
	OAK_ASSERT_EQ((bool)isDirectory, true);

	// The original computed it once into a local and used it three times, so the
	// three primitives recomputing it must give the same answer every call.
	OAK_ASSERT_EQ(to_s(AppControllerSupport.sessionRestoreMarkerPath), to_s(path));
}

void test_marker_round_trip ()
{
	NSString* path = scratch_marker(@"round-trip");
	[NSFileManager.defaultManager removeItemAtPath:path error:nil];

	OAK_ASSERT_EQ((bool)[AppControllerSupport markerExistsAtPath:path], false);
	[AppControllerSupport createMarkerAtPath:path];
	OAK_ASSERT_EQ((bool)[AppControllerSupport markerExistsAtPath:path], true);
	[AppControllerSupport removeMarkerAtPath:path];
	OAK_ASSERT_EQ((bool)[AppControllerSupport markerExistsAtPath:path], false);

	// Removing one that is not there is a plain unlink() failure, ignored — which
	// is what the caller relies on: it unlinks unconditionally, including on the
	// path where it never created one.
	[AppControllerSupport removeMarkerAtPath:path];
	OAK_ASSERT_EQ((bool)[AppControllerSupport markerExistsAtPath:path], false);
}

// O_TRUNC, and it is load-bearing rather than incidental: the marker survives a
// crash, so the next launch creates it again over a file that is already there.
void test_creating_a_marker_truncates_an_existing_one ()
{
	NSString* path = scratch_marker(@"truncate");
	[@"left over from a previous run" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
	OAK_ASSERT_GT((size_t)[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileSize, (size_t)0);

	[AppControllerSupport createMarkerAtPath:path];
	OAK_ASSERT_EQ((size_t)[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileSize, (size_t)0);

	[AppControllerSupport removeMarkerAtPath:path];
}
