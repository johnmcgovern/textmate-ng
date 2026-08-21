#import "OakFilterListTesting.h"
#import <objc/runtime.h>

// Written against the ObjC++ BundleItemChooser, before the Swift port (rule 18). The
// ⌃⌘T "Select Bundle Item" panel and the last file in this framework: three sources
// (actions, settings, other), five searchable fields, a key-equivalent recorder, and an
// edit action alongside the usual accept.
//
// Its item list needs the bundle index, which a bare test process does not have (rule 8),
// so the counts are the app's business. What is pinned here is the surface a port can
// break silently: the properties AppController sets before showing the panel, the actions
// the menu and buttons reach by name, and -windowWillClose: being implemented on this
// class rather than inherited — the SymbolChooser lesson, and here it is what removes the
// key-equivalent observer and the event monitor.
//
// AppController.mm is the only consumer and it is ObjC++, so it also sets `scope`. That
// was a scope::context_t property when this file was written; the boundary work swapped it
// for TMScopeContext, the C++-free box (rule 17), and this assertion moved with it. The
// wildcard matters and is asserted by name: it is AppController's fallback when nothing
// answers -scopeContext, and TMScopeContext's own +currentScope falls back to the *empty*
// scope instead, which matches only selectors that accept it and would empty this panel.

void setup ()
{
	NSApplicationLoad();
}

void test_bundle_item_chooser_shared_instance_is_a_chooser ()
{
	BundleItemChooser* chooser = BundleItemChooser.sharedInstance;
	OAK_ASSERT(chooser != nil);
	OAK_ASSERT(chooser == BundleItemChooser.sharedInstance);
	OAK_ASSERT([chooser isKindOfClass:OakChooser.class]);
}

void test_bundle_item_chooser_builds_its_window ()
{
	BundleItemChooser* chooser = [BundleItemChooser new];
	OAK_ASSERT(chooser.window != nil);
	OAK_ASSERT([chooser.window.title isEqualToString:@"Select Bundle Item"]);
	OAK_ASSERT(chooser.searchField != nil);
	OAK_ASSERT(chooser.statusTextField != nil);
	OAK_ASSERT(chooser.tableView.rowHeight == 38);
}

void test_bundle_item_chooser_properties_round_trip ()
{
	// Exactly what -[AppController showBundleItemChooser:] sets before showing it.
	BundleItemChooser* chooser = [BundleItemChooser new];

	chooser.path         = @"/project/src/main.cc";
	chooser.directory    = @"/project/src";
	chooser.hasSelection = YES;
	chooser.editAction   = @selector(editBundleItem:);

	OAK_ASSERT([chooser.path isEqualToString:@"/project/src/main.cc"]);
	OAK_ASSERT([chooser.directory isEqualToString:@"/project/src"]);
	OAK_ASSERT(chooser.hasSelection == YES);
	OAK_ASSERT(chooser.editAction == @selector(editBundleItem:));
}

void test_bundle_item_chooser_accepts_a_scope ()
{
	// The wildcard is AppController's fallback when no text view answers -scopeContext,
	// and it is NOT the empty scope: wildcard matches every selector, empty matches only
	// those that accept it. A port that swaps one for the other shows an empty panel.
	BundleItemChooser* chooser = [BundleItemChooser new];
	chooser.scope = TMScopeContext.wildcardScope;
	OAK_ASSERT(chooser.scope == TMScopeContext.wildcardScope);
	OAK_ASSERT(chooser.items != nil);
}

void test_bundle_item_chooser_keeps_its_selector_surface ()
{
	SEL const selectors[] = {
		@selector(path),         @selector(setPath:),
		@selector(directory),    @selector(setDirectory:),
		@selector(hasSelection), @selector(setHasSelection:),
		@selector(editAction),   @selector(setEditAction:),
		@selector(updateItems:),
		@selector(updateStatusText:),
		@selector(updateFilterString:),
		@selector(accept:),
		@selector(editItem:),
		@selector(canAccept),
		@selector(canEdit),
		@selector(validateMenuItem:),
		@selector(selectNextTab:),
		@selector(selectPreviousTab:),
	};

	for(SEL selector : selectors)
		OAK_ASSERT([BundleItemChooser instancesRespondToSelector:selector]);
	OAK_ASSERT([BundleItemChooser respondsToSelector:@selector(sharedInstance)]);
}

void test_bundle_item_chooser_implements_windowWillClose_itself ()
{
	// This is where the key-equivalent recorder's KVO observer and the event monitor are
	// torn down; it arrives through the window delegate, and -respondsToSelector: alone
	// cannot tell an own implementation from an inherited one.
	unsigned int count = 0;
	Method* methods = class_copyMethodList(BundleItemChooser.class, &count);
	BOOL found = NO;
	for(unsigned int i = 0; i < count; ++i)
		found = found || method_getName(methods[i]) == @selector(windowWillClose:);
	free(methods);

	OAK_ASSERT(found);
}

void test_bundle_item_chooser_can_accept_and_edit_with_no_selection ()
{
	// Both read self.items[selectedRow] behind a -1 guard; losing that guard is an
	// out-of-range crash the moment the panel opens empty.
	BundleItemChooser* chooser = [BundleItemChooser new];
	OAK_ASSERT([chooser canAccept] == NO);
	OAK_ASSERT([chooser canEdit] == NO);
}
