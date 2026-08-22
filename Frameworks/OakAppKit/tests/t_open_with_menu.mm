#import "OakAppKitTesting.h"
#import <ns/ns.h> // to_s(NSString*)
#import <Cocoa/Cocoa.h>

// Coverage for OakOpenWithMenu, written against the ObjC++ *before* the port.
//
// The file has no C++ types at all — the only C++ in it is a range-for over an
// NSArray and a default argument on a static helper — so this is the rare port
// with no boundary to extract. What it does have is three `getter=` properties
// that are *also* used as KVC sort keys, which is exactly the shape rule 4 says
// a Swift port silently breaks: `defaultApplication` and `isDefaultApplication`
// both have to keep working, and only one of them is what Swift would generate.

static std::string describe (NSString* str)
{
	return str ? to_s(str) : std::string("«nil»");
}

// A real bundle that is guaranteed to exist wherever the tests run: the test
// bundle itself. -initWithBundleURL: only wants something +bundleWithURL: can
// open, and using the host's installed applications would make the assertions
// depend on the machine.
static NSURL* test_bundle_url ()
{
	return [NSBundle bundleForClass:OakOpenWithMenuDelegate.class].bundleURL;
}

static OakOpenWithApplicationInfo* make_info ()
{
	return [[OakOpenWithApplicationInfo alloc] initWithBundleURL:test_bundle_url()];
}

// ==================================================================
// = The surface a Swift port has to keep reachable                 =
// ==================================================================

void test_open_with_selector_surface ()
{
	Class info = OakOpenWithApplicationInfo.class;

	OAK_ASSERT_EQ((bool)[info instancesRespondToSelector:@selector(URL)],              true);
	OAK_ASSERT_EQ((bool)[info instancesRespondToSelector:@selector(bundleIdentifier)], true);
	OAK_ASSERT_EQ((bool)[info instancesRespondToSelector:@selector(name)],             true);
	OAK_ASSERT_EQ((bool)[info instancesRespondToSelector:@selector(version)],          true);
	OAK_ASSERT_EQ((bool)[info instancesRespondToSelector:@selector(displayName)],      true);

	// The three custom getters. Swift would name these isDefaultApplication,
	// multipleVersions and multipleCopies unless told otherwise, and the last two
	// would then be wrong.
	OAK_ASSERT_EQ((bool)[info instancesRespondToSelector:@selector(isDefaultApplication)], true);
	OAK_ASSERT_EQ((bool)[info instancesRespondToSelector:@selector(hasMultipleVersions)],  true);
	OAK_ASSERT_EQ((bool)[info instancesRespondToSelector:@selector(hasMultipleCopies)],    true);

	Class delegate = OakOpenWithMenuDelegate.class;
	OAK_ASSERT_EQ((bool)[delegate conformsToProtocol:@protocol(NSMenuDelegate)], true);
	OAK_ASSERT_EQ((bool)[delegate instancesRespondToSelector:@selector(initWithDocumentURLs:)],                 true);
	OAK_ASSERT_EQ((bool)[delegate instancesRespondToSelector:@selector(openDocumentURLs:withApplicationURL:)],  true);
	OAK_ASSERT_EQ((bool)[delegate instancesRespondToSelector:@selector(documentURLs)],                          true);
	OAK_ASSERT_EQ((bool)[delegate instancesRespondToSelector:@selector(applications)],                          true);
	OAK_ASSERT_EQ((bool)[delegate instancesRespondToSelector:@selector(menuNeedsUpdate:)],                      true);
	OAK_ASSERT_EQ((bool)[delegate instancesRespondToSelector:@selector(openWith:)],                             true);
	OAK_ASSERT_EQ((bool)[delegate instancesRespondToSelector:@selector(menuHasKeyEquivalent:forEvent:target:action:)], true);
}

void test_open_with_flags_are_readable_by_kvc_key_and_by_getter ()
{
	OakOpenWithApplicationInfo* info = make_info();
	info.defaultApplication = YES;

	// -menuNeedsUpdate: calls the getter...
	OAK_ASSERT_EQ((bool)info.isDefaultApplication, true);
	// ...and -applications sorts on the *property* name. Both spellings reach the
	// same value, and a port that keeps only one breaks the other silently: the
	// sort descriptor throws at runtime, not at build time.
	OAK_ASSERT_EQ((bool)[[info valueForKey:@"defaultApplication"] boolValue], true);
	OAK_ASSERT_EQ((bool)[[info valueForKey:@"name"] isEqual:info.name], true);
}

// ==================================================================
// = -displayName, which is four branches in a fixed order          =
// ==================================================================

void test_open_with_display_name_is_the_plain_name_by_default ()
{
	OakOpenWithApplicationInfo* info = make_info();
	OAK_ASSERT_EQ((bool)(info != nil), true);
	OAK_ASSERT_EQ(describe(info.displayName), describe(info.name));
}

void test_open_with_display_name_appends_in_a_fixed_order ()
{
	OakOpenWithApplicationInfo* info = make_info();
	NSString* name    = info.name;
	NSString* version = info.version;

	// Copies first: the version disambiguates two installs of the same release.
	info.multipleCopies = YES;
	OAK_ASSERT_EQ(describe(info.displayName), describe([NSString stringWithFormat:@"%@ (%@)", name, version]));

	// Then "(default)", *after* the version.
	info.defaultApplication = YES;
	OAK_ASSERT_EQ(describe(info.displayName), describe([NSString stringWithFormat:@"%@ (%@) (default)", name, version]));

	// Then the abbreviated containing directory, last, after an em dash.
	info.multipleVersions = YES;
	NSString* directory = [[info.URL.filePathURL.path stringByDeletingLastPathComponent] stringByAbbreviatingWithTildeInPath];
	OAK_ASSERT_EQ(describe(info.displayName), describe([NSString stringWithFormat:@"%@ (%@) (default) — %@", name, version, directory]));
}

void test_open_with_display_name_shows_the_directory_without_the_version ()
{
	// multipleVersions alone: no "(…)" from multipleCopies, but the directory is
	// still appended. The three flags are independent, not a ladder.
	OakOpenWithApplicationInfo* info = make_info();
	info.multipleVersions = YES;

	NSString* directory = [[info.URL.filePathURL.path stringByDeletingLastPathComponent] stringByAbbreviatingWithTildeInPath];
	OAK_ASSERT_EQ(describe(info.displayName), describe([NSString stringWithFormat:@"%@ — %@", info.name, directory]));
}

void test_open_with_info_is_nil_for_a_url_that_is_not_a_bundle ()
{
	// The initialiser returns nil rather than a half-built object, and
	// -applications relies on that to skip URLs it cannot describe.
	OakOpenWithApplicationInfo* info = [[OakOpenWithApplicationInfo alloc] initWithBundleURL:[NSURL fileURLWithPath:@"/usr/bin/true"]];
	OAK_ASSERT_EQ((bool)(info == nil), true);
}

// ==================================================================
// = The delegate                                                   =
// ==================================================================

void test_open_with_delegate_keeps_its_document_urls ()
{
	NSArray<NSURL*>* urls = @[ [NSURL fileURLWithPath:@"/tmp/a.txt"], [NSURL fileURLWithPath:@"/tmp/b.txt"] ];
	OakOpenWithMenuDelegate* delegate = [[OakOpenWithMenuDelegate alloc] initWithDocumentURLs:urls];

	OAK_ASSERT_EQ((size_t)delegate.documentURLs.count, (size_t)2);
	OAK_ASSERT_EQ((bool)[delegate.documentURLs isEqualToArray:urls], true);
}

void test_open_with_applications_is_computed_once ()
{
	OakOpenWithMenuDelegate* delegate = [[OakOpenWithMenuDelegate alloc] initWithDocumentURLs:@[ [NSURL fileURLWithPath:@"/usr/share/dict/words"] ]];

	NSArray* first  = delegate.applications;
	NSArray* second = delegate.applications;

	// LSCopyApplicationURLsForURL is expensive and the menu asks for this on every
	// update, so the result is cached in an ivar — the *same* array, not an equal
	// one.
	OAK_ASSERT_EQ((bool)(first == second), true);
}

void test_open_with_empty_menu_says_so ()
{
	// No documents means the intersection of "applications that can open them" is
	// empty, which is the branch that has to produce a disabled explanatory item
	// rather than an empty menu.
	OakOpenWithMenuDelegate* delegate = [[OakOpenWithMenuDelegate alloc] initWithDocumentURLs:@[]];
	NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Open With"];

	[delegate menuNeedsUpdate:menu];

	OAK_ASSERT_EQ((size_t)menu.numberOfItems, (size_t)1);
	OAK_ASSERT_EQ(describe(menu.itemArray.firstObject.title), std::string("No Suitable Applications Found"));
	// -nop: is the project's "present but does nothing" action; it is what leaves
	// the item visibly disabled.
	OAK_ASSERT_EQ((bool)(menu.itemArray.firstObject.action == @selector(nop:)), true);
	OAK_ASSERT_EQ((bool)(menu.itemArray.firstObject.target == nil), true);
}

void test_open_with_menu_never_claims_a_key_equivalent ()
{
	OakOpenWithMenuDelegate* delegate = [[OakOpenWithMenuDelegate alloc] initWithDocumentURLs:@[]];
	NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Open With"];

	// Returning NO here is what keeps the Open With submenu from being walked on
	// every key press — it is a performance guarantee, not a behavioural one, and
	// it is invisible if a port drops it.
	id target = nil;
	SEL action = NULL;
	OAK_ASSERT_EQ((bool)[delegate menuHasKeyEquivalent:menu forEvent:[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1] target:&target action:&action], false);
}

void test_open_with_menu_lists_applications_with_icons ()
{
	// A real document, so this exercises the populated branch: LSCopyApplicationURLsForURL
	// on a plain text file returns something on any Mac with an editor installed.
	OakOpenWithMenuDelegate* delegate = [[OakOpenWithMenuDelegate alloc] initWithDocumentURLs:@[ [NSURL fileURLWithPath:@"/usr/share/dict/words"] ]];
	NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Open With"];

	[delegate menuNeedsUpdate:menu];

	if(delegate.applications.count == 0)
		return; // nothing installed that claims the file; the empty branch is covered above

	OAK_ASSERT_GT((size_t)menu.numberOfItems, (size_t)0);
	for(NSMenuItem* item in menu.itemArray)
	{
		if(item.isSeparatorItem)
			continue;

		// Every application item carries its URL as the represented object — that
		// is what -openWith: reads — and a 16×16 icon.
		OAK_ASSERT_EQ((bool)[item.representedObject isKindOfClass:NSURL.class], true);
		OAK_ASSERT_EQ((bool)(item.target == delegate), true);
		OAK_ASSERT_EQ((bool)(item.action == @selector(openWith:)), true);
		OAK_ASSERT_EQ((bool)(item.image != nil), true);
		OAK_ASSERT_EQ((double)item.image.size.width, (double)16);
	}
}
