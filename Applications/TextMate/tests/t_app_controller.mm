#import "TextMateTesting.h"
#import <MenuBuilder/MenuBuilder.h>
#import <ns/ns.h>
#import <regexp/find.h>
#import <theme/theme.h>
#import <objc/runtime.h>
#import <io/path.h>
#import <Find/FindTypes.h>
#import <TMBundleModel/TMBundleModelCxx.h>
#import <OakTextView/OakDocumentView.h>
#import <scope/scope.h>
#import <text/types.h>
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
//
// The -retain is not decoration. -mainMenu returns +0 — autoreleased — and this
// file compiles with ARC off, so a bare `static NSMenu* menu = …` caches a
// pointer it does not own and the menu dies at the next pool drain. That read as
// a SIGSEGV in whichever test dumped the menu *after* the one that built it, and
// only ever in that order: build-and-dump inside a single test passes.
//
// It survived before AppController became Swift, so something was incidentally
// keeping the menu alive; I did not establish what, and it does not matter —
// caching a +0 return in a static was wrong either way. The application is
// unaffected, and for a reason worth writing down rather than assuming:
// -applicationWillFinishLaunching: assigns the result to NSApp.mainMenu, and
// NSApplication retains it.
static NSMenu* shared_main_menu ()
{
	static NSMenu* menu = [[[AppController new] mainMenu] retain];
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

// MARK: - TxMtURLSupport
//
// txmt://open?… is a real external interface — `mate`, the HTML output view and
// every bundle command that links to a file go through it — and until this
// extraction none of it was reachable from a test: it was 60 lines of C++ inside
// a method that ends in modal alerts and window ordering. This is rule 35's "the
// extraction makes it testable, take the test while it is cheap".

static std::string describe (NSString* str)
{
	return str ? to_s(str) : std::string("«nil»");
}

void test_txmt_query_parsing ()
{
	NSDictionary* p = [TxMtURLSupport parametersFromQuery:@"url=file:///tmp/x&line=12&column=4"];
	OAK_ASSERT_EQ((size_t)p.count, (size_t)3);
	OAK_ASSERT_EQ(describe(p[@"url"]),    std::string("file:///tmp/x"));
	OAK_ASSERT_EQ(describe(p[@"line"]),   std::string("12"));
	OAK_ASSERT_EQ(describe(p[@"column"]), std::string("4"));
}

void test_txmt_query_percent_decodes_both_halves ()
{
	NSDictionary* p = [TxMtURLSupport parametersFromQuery:@"url=file:///tmp/a%20b&od%64=1"];
	OAK_ASSERT_EQ(describe(p[@"url"]), std::string("file:///tmp/a b"));
	OAK_ASSERT_EQ(describe(p[@"odd"]), std::string("1"));
}

void test_txmt_query_skips_pairs_that_are_not_key_equals_value ()
{
	// The guard is `[keyValue count] == 2`, so a bare word and anything with a
	// second `=` both drop out. Worth pinning: a port that reached for
	// -componentsSeparatedByString: with a limit, or for NSURLComponents, would
	// keep them and change what a malformed link does.
	NSDictionary* p = [TxMtURLSupport parametersFromQuery:@"line=3&bare&a=b=c&x="];
	OAK_ASSERT_EQ((size_t)p.count, (size_t)2);
	OAK_ASSERT_EQ(describe(p[@"line"]), std::string("3"));
	OAK_ASSERT_EQ(describe(p[@"x"]),    std::string(""));
}

void test_txmt_query_last_duplicate_wins ()
{
	NSDictionary* p = [TxMtURLSupport parametersFromQuery:@"line=1&line=2"];
	OAK_ASSERT_EQ(describe(p[@"line"]), std::string("2"));
}

void test_txmt_query_of_a_url_with_none ()
{
	OAK_ASSERT_EQ((size_t)[TxMtURLSupport parametersFromQuery:nil].count, (size_t)0);
	OAK_ASSERT_EQ((size_t)[TxMtURLSupport parametersFromQuery:@""].count, (size_t)0);
}

// The selection string, and the ±1 that a port is most likely to get wrong: the
// URL is 1-based, text::pos_t is 0-based, and the string form adds 1 back.
void test_txmt_selection_string_is_one_based_again ()
{
	OAK_ASSERT_EQ(describe([TxMtURLSupport selectionStringForLine:@"12" column:@"4"]), std::string("12:4"));

	// No column means column 1, and pos_t prints no `:` for column 0.
	OAK_ASSERT_EQ(describe([TxMtURLSupport selectionStringForLine:@"12" column:nil]), std::string("12"));
	OAK_ASSERT_EQ(describe([TxMtURLSupport selectionStringForLine:@"1"  column:@"1"]), std::string("1"));
}

void test_txmt_selection_string_is_nil_without_a_line ()
{
	// This is the `range == text::range_t::undefined` the caller branches on, so
	// nil here is what makes a url-less, uuid-less txmt:// link show the "Missing
	// Parameter" alert rather than hunting for a text view.
	OAK_ASSERT_EQ(describe([TxMtURLSupport selectionStringForLine:nil column:@"4"]), std::string("«nil»"));
	OAK_ASSERT_EQ(describe([TxMtURLSupport selectionStringForLine:nil column:nil]),  std::string("«nil»"));
}

// RECORDED, NOT FIXED. atoi returns 0 for "0" and for anything non-numeric, and
// the -1 is applied to a size_t, so it wraps to SIZE_MAX and prints as 0 again.
// The behaviour is nonsense but it is the *shipped* nonsense, and it is exactly
// what rule 3 is about: a Swift port using Int would trap or produce -1 instead.
// Whoever changes this should mean to.
void test_txmt_selection_string_wraps_on_line_zero ()
{
	OAK_ASSERT_EQ(describe([TxMtURLSupport selectionStringForLine:@"0"   column:nil]), std::string("0"));
	OAK_ASSERT_EQ(describe([TxMtURLSupport selectionStringForLine:@"abc" column:nil]), std::string("0"));
	OAK_ASSERT_EQ(describe([TxMtURLSupport selectionStringForLine:@"5" column:@"0"]),  std::string("5:0"));
}

// The five file:// spellings, plus the bare fallback. The order matters and is
// not obvious: a tilde URL matches a root prefix *first* and is then overwritten
// by the tilde branch, so the loops cannot be reordered.
void test_txmt_file_url_prefixes ()
{
	NSString* home = to_ns(path::home());

	OAK_ASSERT_EQ(describe([TxMtURLSupport pathForFileURLString:@"file:///tmp/x"]),           std::string("/tmp/x"));
	OAK_ASSERT_EQ(describe([TxMtURLSupport pathForFileURLString:@"file://localhost/tmp/x"]),  std::string("/tmp/x"));

	OAK_ASSERT_EQ(describe([TxMtURLSupport pathForFileURLString:@"file:///~/x"]),             to_s([home stringByAppendingPathComponent:@"x"]));
	OAK_ASSERT_EQ(describe([TxMtURLSupport pathForFileURLString:@"file://~/x"]),              to_s([home stringByAppendingPathComponent:@"x"]));
	OAK_ASSERT_EQ(describe([TxMtURLSupport pathForFileURLString:@"file://localhost/~/x"]),    to_s([home stringByAppendingPathComponent:@"x"]));

	// Not one of the five, so it falls through to the bare file:// branch, which
	// joins against home rather than root.
	OAK_ASSERT_EQ(describe([TxMtURLSupport pathForFileURLString:@"file://x"]),                to_s([home stringByAppendingPathComponent:@"x"]));
}

void test_txmt_non_file_url_has_no_path ()
{
	// nil is the NULL_STR the caller passes straight into pathIsDirectory: and
	// pathExists: — both NO — and then into the "does not exist" alert.
	OAK_ASSERT_EQ(describe([TxMtURLSupport pathForFileURLString:@"http://example.com/x"]), std::string("«nil»"));
	OAK_ASSERT_EQ(describe([TxMtURLSupport pathForFileURLString:@"/tmp/x"]),               std::string("«nil»"));
}

void test_txmt_path_predicates ()
{
	NSString* dir  = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tm-txmt-tests"];
	NSString* file = [dir stringByAppendingPathComponent:@"file.txt"];
	[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	[@"x" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];

	OAK_ASSERT_EQ((bool)[TxMtURLSupport pathIsDirectory:dir],  true);
	OAK_ASSERT_EQ((bool)[TxMtURLSupport pathExists:dir],       true);
	OAK_ASSERT_EQ((bool)[TxMtURLSupport pathIsDirectory:file], false);
	OAK_ASSERT_EQ((bool)[TxMtURLSupport pathExists:file],      true);

	// nil becomes NULL_STR, which is what a non-file:// url resolves to. Both must
	// answer NO rather than crash — the caller relies on it and does not guard.
	OAK_ASSERT_EQ((bool)[TxMtURLSupport pathIsDirectory:nil], false);
	OAK_ASSERT_EQ((bool)[TxMtURLSupport pathExists:nil],      false);
}

// MARK: - The Swift menu construction

// Rule 5, the second instance in this file. MainMenu.swift writes the three Find
// menu tags as the literals 0, 3 and 5, because <Find/FindTypes.h> cannot enter
// the app's bridging header — it pulls <text/types.h> and then oak/algorithm.h,
// which needs the full prelude that header deliberately avoids. The literals are
// therefore unchecked by the compiler on the Swift side; this is the check.
static_assert(FFSearchTargetDocument == 0, "FFSearchTarget renumbered — MainMenu.swift has literals");
static_assert(FFSearchTargetProject  == 3, "FFSearchTarget renumbered — MainMenu.swift has literals");
static_assert(FFSearchTargetOther    == 5, "FFSearchTarget renumbered — MainMenu.swift has literals");

void test_find_panel_menu_tags_are_the_search_targets ()
{
	NSMutableDictionary* tags = [NSMutableDictionary dictionary];
	NSMutableArray* queue = [@[ shared_main_menu() ] mutableCopy];
	while(queue.count)
	{
		NSMenu* next = queue.firstObject;
		[queue removeObjectAtIndex:0];
		for(NSMenuItem* item in next.itemArray)
		{
			if(item.action == @selector(orderFrontFindPanel:))
				tags[item.title] = @(item.tag);
			if(item.submenu)
				[queue addObject:item.submenu];
		}
	}

	OAK_ASSERT_EQ((size_t)tags.count, (size_t)3);
	OAK_ASSERT_EQ((int)[tags[@"Find and Replace…"] intValue], (int)FFSearchTargetDocument);
	OAK_ASSERT_EQ((int)[tags[@"Find in Project…"]  intValue], (int)FFSearchTargetProject);
	OAK_ASSERT_EQ((int)[tags[@"Find in Folder…"]   intValue], (int)FFSearchTargetOther);
}

// MBMenuItem's `.submenuRef` was an `NSMenu* __strong*` that MBCreateMenu wrote
// while building; the Swift builder hands the four back in a MainMenuRefs.
// -menuNeedsUpdate: dispatches on their identity, so a nil is not an error — it
// is a menu that silently stops populating, which is the rule 18 failure shape
// one level up.
//
// The first version of this test walked the built menu by title instead, and a
// mutation proved it worthless: pointing Wrap Column's submenuRef at
// `spellingMenu` left the menu *structure* untouched, so it passed. It has to
// call the builder and read what comes back.
void test_main_menu_builder_hands_back_its_four_submenus ()
{
	// Force the cached build first, so this test's second build cannot be the one
	// the golden sees.
	(void)shared_main_menu();

	// Building a menu reassigns four process-global AppKit menus (rule 58), so
	// they are saved and put back — before the assertions, not after, because a
	// failing OAK_ASSERT throws and would skip the restore (rule 53).
	NSMenu* savedServices = NSApp.servicesMenu;
	NSMenu* savedWindows  = NSApp.windowsMenu;
	NSMenu* savedHelp     = NSApp.helpMenu;
	NSMenu* savedFont     = [NSFontManager.sharedFontManager fontMenu:NO];

	TMMainMenuRefs* refs = [TMMenus buildMainMenuInto:[[NSMenu alloc] initWithTitle:@"AMainMenu"]
	                                           target:[AppController new]
	                                          appName:@"xctest"];

	NSApp.servicesMenu = savedServices;
	NSApp.windowsMenu  = savedWindows;
	NSApp.helpMenu     = savedHelp;
	[NSFontManager.sharedFontManager setFontMenu:savedFont];

	NSMutableArray* missing = [NSMutableArray array];
	if(!refs.bundlesMenu)    [missing addObject:@"bundlesMenu"];
	if(!refs.themesMenu)     [missing addObject:@"themesMenu"];
	if(!refs.spellingMenu)   [missing addObject:@"spellingMenu"];
	if(!refs.wrapColumnMenu) [missing addObject:@"wrapColumnMenu"];
	OAK_ASSERT_EQ(sorted_lines(missing), std::string(""));

	// Four references to four different menus, not four to the same one — the
	// failure a mis-pointed submenuRef produces.
	NSSet* distinct = [NSSet setWithArray:@[ refs.bundlesMenu, refs.themesMenu, refs.spellingMenu, refs.wrapColumnMenu ]];
	OAK_ASSERT_EQ((size_t)distinct.count, (size_t)4);

	// And each is the submenu of the item it belongs to.
	OAK_ASSERT_EQ(to_s(refs.bundlesMenu.title),    std::string("Bundles"));
	OAK_ASSERT_EQ(to_s(refs.themesMenu.title),     std::string("Theme"));
	OAK_ASSERT_EQ(to_s(refs.spellingMenu.title),   std::string("Spelling"));
	OAK_ASSERT_EQ(to_s(refs.wrapColumnMenu.title), std::string("Wrap Column"));
}

// MARK: - The Theme menu

// The fixed part of the Theme menu, which -themesMenuNeedsUpdate: builds before
// filling the two per-appearance submenus from the bundle index.
//
// This had no coverage at all before the conversion and could not have had any:
// the MBMenu literal sat below `if(ordered.empty()) { … return; }`, and a test
// process loads no bundle index, so that branch always fired. Extracting the
// literal into a function that does not need the index is what makes it
// reachable — rule 35, the same dividend the C++ extractions paid.
//
// The golden was captured by running the *original* literal verbatim in a
// throwaway probe, so it is an independent check rather than a copy of the Swift.
void test_theme_menu_fixed_part_is_unchanged ()
{
	NSMenu* menu = [[NSMenu alloc] initWithTitle:@"AMainMenu"];
	[TMMenus buildThemeMenuInto:menu target:[AppController new]];
	assert_same_dump(normalised_dump(menu), golden(@"AppControllerThemeMenu.txt"));
}

// -themesMenuNeedsUpdate: sorts every theme into these two submenus by identity,
// so a nil or a shared reference silently puts every theme in one list.
void test_theme_menu_hands_back_both_appearance_submenus ()
{
	NSMenu* menu = [[NSMenu alloc] initWithTitle:@"AMainMenu"];
	TMThemeMenuRefs* refs = [TMMenus buildThemeMenuInto:menu target:[AppController new]];

	NSMutableArray* missing = [NSMutableArray array];
	if(!refs.lightMenu) [missing addObject:@"lightMenu"];
	if(!refs.darkMenu)  [missing addObject:@"darkMenu"];
	OAK_ASSERT_EQ(sorted_lines(missing), std::string(""));

	OAK_ASSERT_EQ((bool)(refs.lightMenu == refs.darkMenu), false);
	OAK_ASSERT_EQ(to_s(refs.lightMenu.title), std::string("Theme for Light Appearance"));
	OAK_ASSERT_EQ(to_s(refs.darkMenu.title),  std::string("Theme for Dark Appearance"));
}

// MARK: - The key text view's scope

// -showBundleItemChooser: asks whatever answers -scopeContext for its scope, and
// falls back to the **wildcard** when nothing does. Which fallback is not a
// detail: t_scope_context.mm records that the wildcard matches every selector
// while the empty scope matches almost none, and that BundleMenuDelegate
// deliberately falls back the other way. Conflating them here would silently
// offer every bundle item in the index regardless of the current language.
//
// nil is the normal case, not an edge one — it is what targetForAction: returns
// whenever no document window is key, and the ObjC++ relied on nil-messaging for
// it (rule 33).
void test_scope_for_no_text_view_is_the_wildcard ()
{
	scope::selector_t const selector("source.ruby");
	TMScopeContext* scope = [AppControllerSupport scopeContextForTarget:nil];

	OAK_ASSERT(selector.does_match(scope.cxxContext).has_value());          // wildcard matches
	OAK_ASSERT(!selector.does_match(TMScopeContext.emptyScope.cxxContext).has_value()); // empty does not
}

// [nil hasSelection] answered NO, and the chooser reads it to decide whether to
// offer selection-dependent items. A Swift port that force-unwrapped instead
// would trap here on every invocation with no key window (rules 33 and 44).
void test_no_text_view_has_no_selection ()
{
	OAK_ASSERT_EQ((bool)[AppControllerSupport targetHasSelection:nil], false);
}

// A real text view, to prove the non-nil branch is not merely the nil branch
// spelled differently: an OakTextView with no document still answers
// -scopeContext, and the answer is not the wildcard.
void test_a_live_text_view_reports_its_own_scope ()
{
	OakDocumentView* documentView = [[OakDocumentView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
	OakTextView* textView = documentView.textView;
	OAK_ASSERT(textView != nil);

	TMScopeContext* scope = [AppControllerSupport scopeContextForTarget:textView];
	OAK_ASSERT(scope != nil);

	// Whatever it is, it came from the view rather than from the fallback.
	scope::selector_t const anything("source.ruby");
	OAK_ASSERT(!anything.does_match(scope.cxxContext).has_value());
}

// MARK: - Position strings

// -editBundleItem: used to hand a text::range_t to
// -showDocument:andSelect:inProject:bringToFront:; it now sets
// OakDocument.selection, which is that method's only use of the range anyway.
// The conversion is only safe because the string is normalised on the way
// through — these tests are what says so.
void test_position_string_round_trips_a_point ()
{
	OAK_ASSERT_EQ(describe([AppControllerSupport selectionStringForPositionString:@"5"]),   std::string("5"));
	OAK_ASSERT_EQ(describe([AppControllerSupport selectionStringForPositionString:@"5:3"]), std::string("5:3"));
	OAK_ASSERT_EQ(describe([AppControllerSupport selectionStringForPositionString:@"1"]),   std::string("1"));
}

// THE case the boundary exists for. text::pos_t parses "%zu:%zu+%zu" and stops
// at the dash, so "5-7" is the *point* 5. OakDocument.selection is eventually
// read as a text::range_t, which splits on "-x" first and would make the same
// string the *range* 5 to 7 — a different selection, silently.
//
// Asserted against the C++ both ways, so the test states the difference rather
// than just the answer.
void test_position_string_is_not_forwarded_verbatim ()
{
	NSString* normalised = [AppControllerSupport selectionStringForPositionString:@"5-7"];

	OAK_ASSERT_EQ(describe(normalised), std::string("5"));
	OAK_ASSERT_EQ(describe(normalised), (std::string)text::range_t(text::pos_t("5-7")));

	// What forwarding the raw string would have meant instead.
	OAK_ASSERT_EQ((std::string)text::range_t("5-7"), std::string("5-7"));
	OAK_ASSERT(text::range_t("5-7") != text::range_t(text::pos_t("5-7")));
}

// nil is how -editBundleItem: says "no line", and it must leave the document's
// selection alone. The ObjC++ expressed that as text::pos_t::undefined, which
// -showDocument:andSelect: checked for before assigning.
void test_position_string_of_nil_is_nil ()
{
	OAK_ASSERT([AppControllerSupport selectionStringForPositionString:nil] == nil);
	OAK_ASSERT(text::range_t(text::pos_t::undefined) == text::range_t::undefined);
}
