#import "../src/FileBrowserViewController.h"
#import <Preferences/Keys.h>

// The framework's first tests. Written before any port, against the ObjC++, so
// that a green suite after the port means something — the order every port in
// this project since Find has used.
//
// The one question this file exists to settle before anything else is planned:
//
//   **Is FileBrowserViewController constructible in a test process at all?**
//
// It is an NSViewController, and -init is deliberately light: it reads a handful
// of user defaults, allocates two mutable sets and a dictionary, and registers
// for user-defaults observation. The view — the outline view, the header, the
// C++ text machinery reached through the cells — is built lazily in -loadView /
// -setupViewWithState:, so -init alone should not touch any of it. But Find's
// controller turned out constructible and CrashReporter's did not, so this is
// asserted rather than assumed: it decides whether the rest of this framework's
// coverage can use instances or has to stay at the class level.

void setup ()
{
	// +[FileBrowserViewController registerDefaults] calls
	// -registerServicesMenuSendTypes: on NSApp, and the controller observes user
	// defaults; both want a real application object and main run loop to exist.
	NSApplicationLoad();
}

void test_file_browser_view_controller_is_constructible ()
{
	FileBrowserViewController* controller = [FileBrowserViewController new];
	OAK_ASSERT(controller != nil);
}

// ==================================================================
// = The ObjC selector surface the Swift port has to keep            =
// ==================================================================
//
// Rule 18: two classes of defect are invisible to the compiler *and* to a green
// suite — an action method that was never ported (a greyed-out menu item,
// because -targetForAction: looks it up by selector) and an @optional delegate
// method whose Swift spelling drifts (compiles, exposes no selector, silently
// does nothing). -instancesRespondToSelector: is the right check because it is
// what AppKit itself does, and it needs no instance, so it stands whatever the
// answer to the constructibility question above.

static void assert_responds (SEL selector)
{
	OAK_ASSERT([FileBrowserViewController instancesRespondToSelector:selector]);
}

void test_file_browser_view_controller_keeps_its_action_methods ()
{
	SEL const actions[] = {
		@selector(goToURL:), @selector(selectURL:withParentURL:),
		@selector(newFile:), @selector(newFolder:),
		@selector(reload:), @selector(deselectAll:), @selector(toggleShowInvisibles:),
		@selector(goBack:), @selector(goForward:), @selector(goToParentFolder:),
		@selector(goToComputer:), @selector(goToHome:), @selector(goToDesktop:),
		@selector(goToFavorites:), @selector(goToSCMDataSource:), @selector(orderFrontGoToFolder:),
		@selector(setupViewWithState:),
	};

	for(SEL selector : actions)
		assert_responds(selector);
}

// The public read-only surface three external consumers reach, plus canGoBack /
// canGoForward which the header exposes as methods and the go-back / go-forward
// buttons bind their enabled state to.
void test_file_browser_view_controller_keeps_its_public_accessors ()
{
	assert_responds(@selector(URL));
	assert_responds(@selector(path));
	assert_responds(@selector(directoryURLForNewItems));
	assert_responds(@selector(selectedFileURLs));
	assert_responds(@selector(headerView));
	assert_responds(@selector(outlineView));
	assert_responds(@selector(sessionState));
	assert_responds(@selector(canGoBack));
	assert_responds(@selector(canGoForward));
}

// -variables returns std::map<std::string, std::string> and is pinned from
// outside the framework: DocumentWindowSupport.mm:356 calls it. That selector
// cannot change shape, so — exactly like DocumentWindowController's four —
// whatever the port does inside, this has to keep answering. The DiskOperations
// pair is the category the header promises to three consumers.
void test_file_browser_view_controller_keeps_its_cxx_and_category_selectors ()
{
	assert_responds(@selector(variables));
	assert_responds(@selector(performOperation:withURLs:unique:select:));
	assert_responds(@selector(performOperation:sourceURLs:destinationURLs:unique:select:));
}

// The registration that used to be +initialize (rule 20: a Swift class cannot
// provide one, so it became explicit and lazy before the port). Two things have
// to stay true and neither is visible to the compiler: that constructing a
// controller performs it, and that it is idempotent — -init runs per instance
// where +initialize ran once.
//
// This does not depend on running before the other tests in this bundle, even
// though they construct controllers too: -init is the *only* caller of
// +registerDefaults now that the runtime is not, so if that call were dropped
// the key would never reach the registration domain in this process at all and
// the assert below fails whatever the order. (Removing the key from the standard
// domain first is not what makes it fail — that domain is a different one; it is
// there so a value left by a previous run cannot mask the registration.)
void test_file_browser_view_controller_registers_its_defaults_from_init ()
{
	OAK_ASSERT([FileBrowserViewController respondsToSelector:@selector(registerDefaults)]);

	// foldersOnTop has no registered default until a controller exists.
	[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsFoldersOnTopKey];

	FileBrowserViewController* controller = [FileBrowserViewController new];
	OAK_ASSERT(controller != nil);

	NSDictionary* registered = [NSUserDefaults.standardUserDefaults volatileDomainForName:NSRegistrationDomain];
	OAK_ASSERT(registered[kUserDefaultsFoldersOnTopKey] != nil);

	// A second instance must not fail or re-register differently.
	id firstValue = registered[kUserDefaultsFoldersOnTopKey];
	FileBrowserViewController* second = [FileBrowserViewController new];
	OAK_ASSERT(second != nil);
	OAK_ASSERT([[NSUserDefaults.standardUserDefaults volatileDomainForName:NSRegistrationDomain][kUserDefaultsFoldersOnTopKey] isEqual:firstValue]);
}
