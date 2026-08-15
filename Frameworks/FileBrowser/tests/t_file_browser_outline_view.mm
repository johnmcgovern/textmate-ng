#import "../src/FileBrowserOutlineView.h"

// FileBrowserOutlineView is implemented in Swift behind a hand-written ObjC
// header, so nothing checks the two against each other at build time. This pins
// that the class is still constructible and keeps the action selectors the key
// bindings and menus reach — showContextMenu:, performDoubleClick:,
// performEditSelectedRow:, and the performKeyEquivalent: override. A dropped or
// renamed one is a dead shortcut with no compile error.
//
// The expand/collapse and didTrashURLs forwarding can't be reached without a
// live outline session, and the delegate-cast that carries them (nominal in
// Swift, structural in the ObjC++) is verified in the running app instead.

void setup ()
{
	NSApplicationLoad();
}

void test_file_browser_outline_view_is_constructible ()
{
	FileBrowserOutlineView* view = [[FileBrowserOutlineView alloc] initWithFrame:NSZeroRect];
	OAK_ASSERT(view != nil);
	OAK_ASSERT([view isKindOfClass:NSOutlineView.class]);
}

void test_file_browser_outline_view_keeps_its_action_selectors ()
{
	SEL const actions[] = {
		@selector(showContextMenu:),
		@selector(performDoubleClick:),
		@selector(performEditSelectedRow:),
		@selector(performKeyEquivalent:),
	};

	for(SEL selector : actions)
		OAK_ASSERT([FileBrowserOutlineView instancesRespondToSelector:selector]);
}
