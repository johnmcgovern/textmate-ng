#import <Cocoa/Cocoa.h>
#import <ns/ns.h>

// The application shell's first test, and it exists to guard the thing that makes
// every later one possible.
//
// A test bundle links the *static libraries* under test. An application is not
// one — its sources compile straight into the app binary — so before the seed
// change that accompanies this file, a test bundle for Applications/TextMate
// linked 49 libraries and could not see a single class the app itself defines.
// Measured: NSClassFromString("AppController") was Nil while framework classes
// resolved fine.
//
// ide/seed_xcodeproj.rb now compiles a non-lib target's own sources into its test
// bundle. If that ever regresses, everything under Applications/ silently becomes
// untestable again — the bundle still builds and still passes, it just stops
// seeing the code. This test is what turns that into a failure.

void setup ()
{
	NSApplicationLoad();
}

// Classes from frameworks the bundle links. If these are Nil the harness itself
// is broken, and the assertions below would be meaningless rather than wrong.
void test_app_target_controls_resolve ()
{
	OAK_ASSERT_EQ((bool)(NSClassFromString(@"OakDocumentView") != Nil),   true);
	OAK_ASSERT_EQ((bool)(NSClassFromString(@"OakHTMLOutputView") != Nil), true);
}

void test_app_target_own_classes_are_reachable ()
{
	// One from each of four source files, including the Swift one — a bundle that
	// compiled the ObjC++ but not the Swift would pass a narrower check.
	std::string missing;
	for(NSString* name in @[ @"AboutWindowController", @"AppController", @"FavoriteChooser", @"TMSwiftInterop" ])
	{
		if(!NSClassFromString(name))
			missing += to_s(name) + " ";
	}
	OAK_ASSERT_EQ(missing, std::string(""));
}
