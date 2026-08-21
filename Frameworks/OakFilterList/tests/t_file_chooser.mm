#import "../src/FileChooser.h"
#import <objc/runtime.h>

// Written against the ObjC++ FileChooser, before the Swift port (rule 18). The ⌘T "Open
// Quickly" panel, and the biggest OakChooser subclass: three sources (all files, open
// documents, uncommitted changes), a background search with a polling timer, SCM status,
// and a filter string with its own mini-syntax.
//
// Its two live paths — the directory search and the SCM status — need a real project on
// disk and are left to the app (rule 8). What is pinned here is everything else, and in
// particular the parts a port can silently get wrong: the source-index/title mapping, the
// menu validation that decides whether ⌘↑ is enabled, and the delegate and action
// selectors AppController and OakDocumentView reach by name.
//
// DocumentWindowController.swift already drives this class from Swift through
// FileChooser.h, so the port has to keep that spelling working too — .path,
// .currentDocument and .sharedInstance are asserted here for that reason.
//
// The window title assertions double as the source-index pin: -setSourceIndex: is what
// retitles the window, and it also persists to NSUserDefaults — in this process that is
// the test bundle's own domain, never the app's.

void setup ()
{
	NSApplicationLoad();
}

void test_file_chooser_shared_instance_is_a_chooser ()
{
	FileChooser* chooser = FileChooser.sharedInstance;
	OAK_ASSERT(chooser != nil);
	OAK_ASSERT(chooser == FileChooser.sharedInstance);
	OAK_ASSERT([chooser isKindOfClass:OakChooser.class]);
}

void test_file_chooser_builds_its_window_and_views ()
{
	FileChooser* chooser = [FileChooser new];
	OAK_ASSERT(chooser.window != nil);
	OAK_ASSERT(chooser.searchField != nil);
	OAK_ASSERT(chooser.statusTextField != nil);
	OAK_ASSERT(chooser.itemCountTextField != nil);
	OAK_ASSERT(chooser.window.initialFirstResponder == chooser.searchField);
	// Multiple selection and the taller rows are this subclass's table settings.
	OAK_ASSERT(chooser.tableView.allowsMultipleSelection == YES);
	OAK_ASSERT(chooser.tableView.rowHeight == 38);
}

void test_file_chooser_source_index_drives_the_window_title ()
{
	FileChooser* chooser = [FileChooser new];

	chooser.sourceIndex = kFileChooserOpenDocumentsSourceIndex;
	OAK_ASSERT(chooser.sourceIndex == kFileChooserOpenDocumentsSourceIndex);
	OAK_ASSERT([chooser.window.title isEqualToString:@"Open Documents"]);

	chooser.sourceIndex = kFileChooserUncommittedChangesSourceIndex;
	OAK_ASSERT([chooser.window.title isEqualToString:@"Uncommitted Documents"]);

	// The "all" source titles with the path, and falls back when there is none.
	chooser.sourceIndex = kFileChooserAllSourceIndex;
	OAK_ASSERT([chooser.window.title isEqualToString:@"Open Quickly"]);
}

void test_file_chooser_path_appears_in_the_title ()
{
	FileChooser* chooser = [FileChooser new];
	chooser.sourceIndex = kFileChooserOpenDocumentsSourceIndex; // no directory search
	chooser.path = @"/usr/share";
	OAK_ASSERT([chooser.path isEqualToString:@"/usr/share"]);

	chooser.sourceIndex = kFileChooserAllSourceIndex;
	OAK_ASSERT([chooser.window.title isEqualToString:@"/usr/share"]);
}

void test_file_chooser_go_to_parent_folder_validation ()
{
	FileChooser* chooser = [FileChooser new];
	NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"Parent" action:@selector(goToParentFolder:) keyEquivalent:@""];

	chooser.sourceIndex = kFileChooserOpenDocumentsSourceIndex;
	chooser.path = @"/usr/share";
	OAK_ASSERT([chooser validateMenuItem:item] == NO); // wrong source: disabled

	chooser.sourceIndex = kFileChooserAllSourceIndex;
	OAK_ASSERT([chooser validateMenuItem:item] == YES); // has a parent

	chooser.path = @"/";
	OAK_ASSERT([chooser validateMenuItem:item] == NO); // root is its own parent
}

void test_file_chooser_keeps_its_selector_surface ()
{
	SEL const selectors[] = {
		@selector(path),            @selector(setPath:),
		@selector(currentDocument), @selector(setCurrentDocument:),
		@selector(sourceIndex),     @selector(setSourceIndex:),
		@selector(updateItems:),
		@selector(updateStatusText:),
		@selector(updateFilterString:),
		@selector(selectedItems),
		@selector(accept:),
		@selector(takeItemToCloseFrom:),
		@selector(goToParentFolder:),
		@selector(validateMenuItem:),
		@selector(selectNextTab:),
		@selector(selectPreviousTab:),
		@selector(updateShowTabMenu:),
		@selector(tableView:viewForTableColumn:row:),
	};

	for(SEL selector : selectors)
		OAK_ASSERT([FileChooser instancesRespondToSelector:selector]);
	OAK_ASSERT([FileChooser respondsToSelector:@selector(sharedInstance)]);
}

void test_file_chooser_implements_windowWillClose_itself ()
{
	// As with SymbolChooser: this is where the panel tears down its search, SCM info and
	// records, it arrives through the window delegate, and -respondsToSelector: alone
	// cannot tell an own implementation from an inherited one.
	unsigned int count = 0;
	Method* methods = class_copyMethodList(FileChooser.class, &count);
	BOOL found = NO;
	for(unsigned int i = 0; i < count; ++i)
		found = found || method_getName(methods[i]) == @selector(windowWillClose:);
	free(methods);

	OAK_ASSERT(found);
}

void test_file_chooser_closing_clears_its_items ()
{
	FileChooser* chooser = [FileChooser new];
	chooser.sourceIndex = kFileChooserOpenDocumentsSourceIndex;
	[chooser windowWillClose:nil];
	OAK_ASSERT(chooser.items.count == 0);
}
