#import "TextMateTesting.h"
#import <ns/ns.h>
#import <Cocoa/Cocoa.h>

// Coverage for TMPlugInController, written before the port (rule 18).
//
// The class does two things: it decides *whether* to load a plug-in bundle, and
// it installs one. Only the first half is testable — every branch of
// -installPlugInAtPath: ends in -runModal — so this pins the decision, which is
// also where the behaviour that can be got wrong lives.
//
// Nothing here loads real code. Each test builds a directory with an Info.plist
// and lets NSBundle read it; a bundle with no executable can never reach the
// principal class, so the tests observe what the controller decided rather than
// what a plug-in did.

void setup ()
{
	NSApplicationLoad();
}

static NSString* scratch_dir ()
{
	NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tm-plugin-tests"];
	[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return dir;
}

// A .tmplugin that NSBundle will open and read Info.dictionary from. No
// executable, so -loadAndReturnError: can never produce an instance.
static NSString* make_plugin (NSString* name, NSString* identifier, id apiVersion)
{
	NSString* path = [scratch_dir() stringByAppendingPathComponent:name];
	[NSFileManager.defaultManager removeItemAtPath:path error:nil];

	NSString* contents = [path stringByAppendingPathComponent:@"Contents"];
	[NSFileManager.defaultManager createDirectoryAtPath:contents withIntermediateDirectories:YES attributes:nil error:nil];

	NSMutableDictionary* info = [@{
		@"CFBundleIdentifier": identifier,
		@"CFBundleName":       [name stringByDeletingPathExtension],
		@"CFBundlePackageType": @"BNDL",
	} mutableCopy];
	if(apiVersion)
		info[@"TMPlugInAPIVersion"] = apiVersion;

	[info writeToURL:[NSURL fileURLWithPath:[contents stringByAppendingPathComponent:@"Info.plist"]] error:nil];
	return path;
}

// A controller of our own. -sharedInstance is the app's, and seeding its
// loadedPlugIns would outlive the test.
static TMPlugInController* fresh_controller ()
{
	return [[TMPlugInController alloc] init];
}

// ==================================================================
// = The class surface                                              =
// ==================================================================

void test_plugin_shared_instance_is_a_singleton ()
{
	OAK_ASSERT_EQ((bool)(TMPlugInController.sharedInstance == TMPlugInController.sharedInstance), true);
	OAK_ASSERT_EQ((bool)(TMPlugInController.sharedInstance != nil), true);
}

// The plug-in API version the controller answers with, and the one it demands of
// a bundle, are the same number written twice in the original — 2.0 here and
// kPlugInAPIVersion = 2 in the check below. A port that changed either would let
// incompatible plug-ins in.
void test_plugin_version_is_two ()
{
	OAK_ASSERT_EQ((double)TMPlugInController.sharedInstance.version, 2.0);
}

// Registered by +initialize in the original. Emmet crashes this fork, so the
// default is load-bearing rather than cosmetic.
void test_plugin_emmet_is_disabled_by_default ()
{
	(void)TMPlugInController.sharedInstance;
	NSArray* disabled = [NSUserDefaults.standardUserDefaults stringArrayForKey:@"disabledPlugIns"];
	OAK_ASSERT_EQ((bool)[disabled containsObject:@"io.emmet.EmmetTextmate"], true);
}

// ==================================================================
// = What -loadPlugInAtPath: refuses                                =
// ==================================================================

void test_plugin_a_path_that_is_not_a_bundle_loads_nothing ()
{
	TMPlugInController* controller = fresh_controller();
	[controller loadPlugInAtPath:[scratch_dir() stringByAppendingPathComponent:@"NoSuchThing.tmplugin"]];
	OAK_ASSERT_EQ((size_t)controller.loadedPlugIns.count, (size_t)0);
}

void test_plugin_a_blacklisted_identifier_is_skipped ()
{
	TMPlugInController* controller = fresh_controller();
	[controller loadPlugInAtPath:make_plugin(@"Emmet.tmplugin", @"io.emmet.EmmetTextmate", @2)];
	OAK_ASSERT_EQ((size_t)controller.loadedPlugIns.count, (size_t)0);
}

void test_plugin_a_wrong_api_version_is_skipped ()
{
	TMPlugInController* controller = fresh_controller();
	[controller loadPlugInAtPath:make_plugin(@"Old.tmplugin", @"com.example.old", @1)];
	OAK_ASSERT_EQ((size_t)controller.loadedPlugIns.count, (size_t)0);
}

// No TMPlugInAPIVersion at all reads as 0 through -intValue, which is not 2.
void test_plugin_a_missing_api_version_is_skipped ()
{
	TMPlugInController* controller = fresh_controller();
	[controller loadPlugInAtPath:make_plugin(@"Unversioned.tmplugin", @"com.example.unversioned", nil)];
	OAK_ASSERT_EQ((size_t)controller.loadedPlugIns.count, (size_t)0);
}

// The already-loaded check is on the identifier, and it keeps what is there —
// it does not reload and it does not replace.
void test_plugin_an_already_loaded_identifier_keeps_the_first_instance ()
{
	TMPlugInController* controller = fresh_controller();
	NSObject* first = [NSObject new];
	controller.loadedPlugIns[@"com.example.twice"] = first;

	[controller loadPlugInAtPath:make_plugin(@"Twice.tmplugin", @"com.example.twice", @2)];

	OAK_ASSERT_EQ((size_t)controller.loadedPlugIns.count, (size_t)1);
	OAK_ASSERT_EQ((bool)(controller.loadedPlugIns[@"com.example.twice"] == first), true);
}

// ==================================================================
// = The crash marker                                               =
// ==================================================================

// A bundle that passes every check gets a marker file written before the load
// and removed after, so a crash *during* the load leaves it behind. Nothing here
// crashes, so the file must be gone when the call returns — and the temp
// directory must not be left dirty.
void test_plugin_a_completed_load_leaves_no_crash_marker ()
{
	TMPlugInController* controller = fresh_controller();
	NSString* marker = [NSTemporaryDirectory() stringByAppendingPathComponent:@"load_com.example.marker"];
	[NSFileManager.defaultManager removeItemAtPath:marker error:nil];

	[controller loadPlugInAtPath:make_plugin(@"Marker.tmplugin", @"com.example.marker", @2)];

	OAK_ASSERT_EQ((bool)[NSFileManager.defaultManager fileExistsAtPath:marker], false);
}

// A bundle that is refused before the load never writes one either.
void test_plugin_a_skipped_plugin_writes_no_crash_marker ()
{
	TMPlugInController* controller = fresh_controller();
	NSString* marker = [NSTemporaryDirectory() stringByAppendingPathComponent:@"load_com.example.skipped"];
	[NSFileManager.defaultManager removeItemAtPath:marker error:nil];

	[controller loadPlugInAtPath:make_plugin(@"Skipped.tmplugin", @"com.example.skipped", @1)];

	OAK_ASSERT_EQ((bool)[NSFileManager.defaultManager fileExistsAtPath:marker], false);
}
