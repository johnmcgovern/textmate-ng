#import "../src/FileBrowserViewController.h"
#import "../src/FileItem.h"
#import "../src/FileItemTableCellView.h"
#import "../src/FileBrowserViewControllerSupport.h"
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

// ===============================================================
// = The KVO surface (rule 1), which the port has to keep alive  =
// ===============================================================
//
// The header view's two nav buttons bind their enabled state to canGoBack /
// canGoForward, and neither is ever set: both are derived from historyIndex
// through +keyPathsForValuesAffecting…. In Swift that only keeps working if
// historyIndex is `@objc dynamic` — without it the write skips the KVO swizzle,
// no notification is posted, and the buttons stay whatever they were. Invisible
// to the compiler and to every other test here.
//
// So this binds a real NSButton exactly as OFBHeaderView does, rather than
// asserting the two class methods exist: the binding is the mechanism that has
// to survive, and it fails for the missing-`dynamic` reason and no other. (A
// hand-written observer class would say the same thing, but a test file cannot
// declare one — the seed wraps each file's body in a C++ namespace.)
//
// historyIndex and fileItem are private, in the class extension; the bindings
// reach them by key path through KVC, which is how the app reaches them too.

void test_file_browser_view_controller_publishes_can_go_back_from_history_index ()
{
	FileBrowserViewController* controller = [FileBrowserViewController new];

	NSButton* goBackButton    = [NSButton new];
	NSButton* goForwardButton = [NSButton new];
	[goBackButton    bind:NSEnabledBinding toObject:controller withKeyPath:@"canGoBack"    options:nil];
	[goForwardButton bind:NSEnabledBinding toObject:controller withKeyPath:@"canGoForward" options:nil];

	// historyIndex is 0 and history is empty, so neither direction is available.
	OAK_ASSERT(!goBackButton.enabled);
	OAK_ASSERT(!goForwardButton.enabled);

	[controller setValue:@[ @{}, @{} ] forKey:@"history"];
	[controller setValue:@1 forKey:@"historyIndex"];

	// canGoBack is historyIndex > 0; canGoForward is historyIndex+1 < count.
	OAK_ASSERT(goBackButton.enabled);
	OAK_ASSERT(!goForwardButton.enabled);

	[controller setValue:@0 forKey:@"historyIndex"];
	OAK_ASSERT(!goBackButton.enabled);
	OAK_ASSERT(goForwardButton.enabled);

	[goBackButton    unbind:NSEnabledBinding];
	[goForwardButton unbind:NSEnabledBinding];
}

// The current-location menu item binds its title to fileItem.displayName and its
// image to fileReference.image, so fileItem carries the same requirement.
void test_file_browser_view_controller_publishes_file_item ()
{
	FileBrowserViewController* controller = [FileBrowserViewController new];

	NSMenuItem* menuItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
	[menuItem bind:NSTitleBinding toObject:controller withKeyPath:@"fileItem.displayName" options:nil];

	NSURL* url = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
	FileItem* item = [FileItem fileItemWithURL:url];
	OAK_ASSERT(item != nil);

	[controller setValue:item forKey:@"fileItem"];
	OAK_ASSERT([menuItem.title isEqualToString:item.displayName]);

	[menuItem unbind:NSTitleBinding];
}

// The delegate is how DocumentWindowController receives openURLs / closeURL;
// it is a property on the public header rather than an action, so nothing else
// here would notice it going missing.
void test_file_browser_view_controller_keeps_its_delegate_accessors ()
{
	assert_responds(@selector(delegate));
	assert_responds(@selector(setDelegate:));
}

// =========================================================
// = The glob filter, now that it is reachable on its own  =
// =========================================================
//
// Extracting the C++ ahead of the port turned the browser's visibility rule from
// a private method that only ran with a live tree into a pure function of a
// directory URL, so it can be tested rather than eyeballed.
//
// The assertions deliberately avoid the glob lists themselves: those come from
// settings (.tm_properties and the bundled defaults), so what they exclude
// depends on the machine the test runs on. What is pinned here is the branch a
// port is most likely to inverse — hidden items are matched against the
// *include* globs and everything else against the *exclude* globs, and a hidden
// item whose name does not begin with a dot is rejected outright.

void test_item_predicate_rejects_hidden_items_not_named_with_a_dot ()
{
	NSURL* dir = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
	NSPredicate* predicate = [FileBrowserViewControllerSupport itemPredicateForDirectoryURL:dir];
	OAK_ASSERT(predicate != nil);

	FileItem* plain = [FileItem fileItemWithURL:[dir URLByAppendingPathComponent:@"plain.txt"]];
	OAK_ASSERT(plain != nil);
	OAK_ASSERT(!plain.hidden);
	OAK_ASSERT([predicate evaluateWithObject:plain]);

	// Hidden, but not a dotfile: rejected before any glob is consulted.
	plain.hidden = YES;
	OAK_ASSERT(![predicate evaluateWithObject:plain]);

	// A dotfile is *not* rejected by that rule — it falls through to the include
	// globs. What those globs then decide is a settings question and so is not
	// asserted here; on this machine a dotfile in /tmp is excluded by them.
}

void test_is_binary_url_follows_the_binary_setting ()
{
	// No assertion about which globs are configured — only that the call works
	// through the extracted boundary and answers for a plain text file.
	NSURL* url = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:@"plain.txt"];
	OAK_ASSERT(![FileBrowserViewControllerSupport isBinaryURL:url]);
}

// =========================================================
// = The outline view data source, after it became Swift   =
// =========================================================
//
// The seven data-source methods are the first section peeled off the controller
// into a Swift extension. Six of them are one line and nothing here would tell
// you if they broke; the two that resolve "the item asked about, or the root"
// are a different matter, because `fileItem` imports as an implicitly unwrapped
// optional and the root is nil on a controller that has not been given a URL.
//
// That is not a theoretical state — AppKit asks for the row count while the
// view is being set up, and the first draft of the Swift trapped there and took
// the whole test process down with it. This pins it directly rather than
// leaving it to be caught side-on by the menu test that happened to find it.

void test_outline_view_data_source_survives_a_nil_root ()
{
	FileBrowserViewController* controller = [FileBrowserViewController new];
	NSOutlineView* outlineView = controller.outlineView;
	OAK_ASSERT(outlineView != nil);

	// No URL has been set, so fileItem is nil — the ObjC++ answered 0 by
	// messaging nil, and the Swift has to answer 0 rather than trap.
	id <NSOutlineViewDataSource> dataSource = (id <NSOutlineViewDataSource>)controller;
	OAK_ASSERT([dataSource outlineView:outlineView numberOfChildrenOfItem:nil] == 0);

	// Out of range against a nil root answers nil rather than trapping, which is
	// what the ObjC++ subscript did.
	OAK_ASSERT([dataSource outlineView:outlineView child:0 ofItem:nil] == nil);
}

// ===========================================================
// = The table cell constructor, after it became Swift       =
// ===========================================================
//
// The cell's two buttons are wired here by name — target set to the controller,
// action set to a selector — and nothing about that is checked by the compiler.
// If either selector drifts in the Swift (rule 18) or the target assignment is
// dropped, the buttons render exactly as before and simply do nothing when
// clicked. t_file_item_table_cell_view.mm pins the *view's* half of this (that
// -init still produces the two buttons); this pins the controller's half.
//
// The text field's delegate matters for the same reason: it is what makes a
// finished rename commit, and it only resolves because the Swift extension
// declares the NSTextFieldDelegate conformance itself.

void test_table_cell_view_is_constructed_and_wired ()
{
	FileBrowserViewController* controller = [FileBrowserViewController new];
	NSOutlineView* outlineView = controller.outlineView;
	OAK_ASSERT(outlineView != nil);

	NSTableColumn* column = outlineView.tableColumns.firstObject;
	OAK_ASSERT(column != nil);

	FileItem* item = [FileItem fileItemWithURL:[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]];
	OAK_ASSERT(item != nil);

	id <NSOutlineViewDelegate> delegate = (id <NSOutlineViewDelegate>)controller;
	NSView* view = [delegate outlineView:outlineView viewForTableColumn:column item:item];
	OAK_ASSERT(view != nil);
	OAK_ASSERT([view isKindOfClass:[FileItemTableCellView class]]);

	FileItemTableCellView* cell = (FileItemTableCellView*)view;
	OAK_ASSERT([(NSString*)cell.identifier isEqualToString:(NSString*)column.identifier]);

	OAK_ASSERT(cell.openButton != nil);
	OAK_ASSERT(cell.openButton.target == controller);
	OAK_ASSERT(cell.openButton.action == @selector(takeItemToOpenFrom:));

	OAK_ASSERT(cell.closeButton != nil);
	OAK_ASSERT(cell.closeButton.target == controller);
	OAK_ASSERT(cell.closeButton.action == @selector(takeItemToCloseFrom:));

	OAK_ASSERT(cell.textField != nil);
	OAK_ASSERT(cell.textField.delegate == (id <NSTextFieldDelegate>)controller);
}

// ==========================================================
// = The action menu's two C++ clusters, after the second   =
// = extraction commit                                      =
// ==========================================================
//
// The inactive key equivalents were a std::map<SEL, std::string> whose values
// were built with utf8::to_s() and applied with -setInactiveKeyEquivalentCxxString:.
// They are now an NSDictionary applied with -setInactiveKeyEquivalent:, which is
// the same code path one conversion earlier (it is literally
// `…CxxString:to_s(arg)`), so what has to be pinned is not the mechanism but the
// *bytes*: "@" followed by U+F701 for Open, a bare U+000D for Rename. A wrong
// format specifier or a wrong NSEvent constant compiles and renders a plausible
// but different glyph, which no other test and no compiler would catch.
//
// Rather than assert the rendered glyphs — which would pin OakAppKit's rendering
// rather than this table — each item is compared against a reference NSMenuItem
// given the intended string as an independent literal.

static NSMenuItem* menu_item_with_action (NSMenu* menu, SEL action)
{
	for(NSMenuItem* menuItem in menu.itemArray)
	{
		if(menuItem.action == action)
			return menuItem;
	}
	return nil;
}

static NSMenuItem* reference_item_with_title (NSString* title, NSString* keyEquivalent)
{
	NSMenuItem* res = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];
	[res setInactiveKeyEquivalent:keyEquivalent];
	return res;
}

void test_action_menu_keeps_its_inactive_key_equivalents ()
{
	FileBrowserViewController* controller = [FileBrowserViewController new];

	NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
	[(id <NSMenuDelegate>)controller menuNeedsUpdate:menu];

	// "Open" carries no kRequiresSelectionTag, so it survives an empty selection.
	NSMenuItem* open = menu_item_with_action(menu, @selector(openSelectedItems:));
	OAK_ASSERT(open != nil);
	OAK_ASSERT([open.attributedTitle.string isEqualToString:reference_item_with_title(@"Open", @"@").attributedTitle.string]);

	NSMenuItem* rename = menu_item_with_action(menu, @selector(editSelectedEntries:));
	OAK_ASSERT(rename != nil);
	OAK_ASSERT([rename.attributedTitle.string isEqualToString:reference_item_with_title(@"Rename", @"\r").attributedTitle.string]);

	// A plain ASCII one, to catch the table being dropped altogether.
	NSMenuItem* duplicate = menu_item_with_action(menu, @selector(duplicateSelectedEntries:));
	OAK_ASSERT(duplicate != nil);
	OAK_ASSERT([duplicate.attributedTitle.string isEqualToString:reference_item_with_title(@"Duplicate", @"@d").attributedTitle.string]);
}

// The bundle-contributed action-menu items. `bundles::item_ptr` is the rule-20
// type that cannot cross into Swift, so the boundary returns finished
// NSMenuItems; what matters is that nothing of the C++ leaks through it and that
// -executeBundleCommand: still finds a UUID string where it looks.
//
// **Know what this does and does not cover.** No bundle index is loaded in a
// test process — measured, not assumed: asserting `items.count != 0` here fails.
// So the loop below is vacuous as things stand, and what actually runs is the
// call itself: that the boundary is reachable, returns an array rather than
// throwing, and hands back nothing C++-shaped. The per-item assertions are
// there for the day a fixture bundle is loaded, and the populated menu is
// covered by the app run (rule 8) rather than by this.
//
// Which bundles are installed is a per-machine question either way, so the
// *contents* are not asserted — nor the text::less_t ordering, which is
// strcasecmp and would disagree with any NSString comparator on a non-ASCII
// bundle name.
void test_bundle_action_menu_items_are_shaped_for_the_menu ()
{
	NSArray<NSMenuItem*>* items = [FileBrowserViewControllerSupport actionMenuItemsWithAction:@selector(executeBundleCommand:)];
	OAK_ASSERT(items != nil);

	for(NSMenuItem* item in items)
	{
		OAK_ASSERT(item.action == @selector(executeBundleCommand:));
		OAK_ASSERT(item.title.length != 0);
		OAK_ASSERT([item.representedObject isKindOfClass:[NSString class]]);
		OAK_ASSERT([item.representedObject length] != 0);
	}
}
