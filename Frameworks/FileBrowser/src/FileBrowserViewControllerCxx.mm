// The two methods of FileBrowserViewController that stay ObjC++ now that the
// class itself is Swift, plus the menu delegate callback that reaches one of
// them.
//
// This is the DocumentWindowSupport.mm arrangement (rule 23), and the direction
// matters for the same reason it does there: **an ObjC++ category may call into
// the Swift, but the Swift cannot call back into this category.** Doing so would
// need FileBrowserViewController.h in the bridging header, which would declare
// the class a second time alongside the one Swift defines. That is why
// -menuNeedsUpdate: lives here rather than in the Swift — it is the only caller
// of -updateMenu:, and if it were Swift there would be no legal way for it to
// make the call.
//
// Why each of the two cannot be Swift:
//
//   -variables      returns std::map<std::string, std::string> and is pinned
//                   from outside the framework — DocumentWindowSupport.mm:356
//                   does `res = [self.fileBrowser variables]`. The selector
//                   cannot change shape, so it is declared in
//                   FileBrowserViewController.h and implemented here. The
//                   importer drops it from the Swift view of that header, which
//                   is exactly what makes the hand-written declaration workable.
//
//   -updateMenu:    builds an `MBMenu`, which MenuBuilder declares as
//                   `typedef std::vector<MBMenuItem> MBMenu` and which is
//                   populated with C++ designated-initialiser aggregate syntax
//                   and `NSMenuItem* __strong*` out-parameters. There is no
//                   ObjC-shaped MenuBuilder API to use instead. Extracting just
//                   the literal so the other forty lines could be Swift was
//                   considered and rejected: it buys an `NSMenuItem**` boundary
//                   for code that needs an ObjC++ neighbour either way.
//
// Neither is a leftover to be finished later. They are the permanent ObjC++ of
// this class, the same way DocumentWindowController keeps four C++-typed
// selectors.
#import "FileBrowserViewController.h"
#import "FileBrowserViewControllerSupport.h"
#import "FileBrowserOutlineViewDelegate.h"
#import "FileItem.h"
#import "OFB/OFBFinderTagsChooser.h"
#import <MenuBuilder/MenuBuilder.h>
#import <OakAppKit/NSMenuItem Additions.h>
#import <OakAppKit/OakFinderTag.h>
#import <OakAppKit/OakOpenWithMenu.h>
#import <io/path.h>
#import <text/format.h>

// The half of the class this file calls into, hand-declared because the
// generated FileBrowser-Swift.h is not importable here: it declares every class
// this framework's Swift defines, and this file already imports the
// hand-written headers for two of them (FileBrowserViewController.h, FileItem.h),
// so clang would reject the duplicate interfaces (rule 43). FindSupport.mm and
// DocumentWindowSupport.mm hand-declare their Swift halves for the same reason.
//
// Nothing checks these against the Swift at build time beyond the selector
// names. A drift in argument or return type is an unrecognized selector at
// runtime, which is what the -instancesRespondToSelector: tests guard (rule 18).
@interface FileBrowserViewController (FileBrowserSwiftHalf)
@property (nonatomic, readonly, nonnull) NSArray<FileItem*>* selectedItems;
@property (nonatomic, readonly, nonnull) NSArray<FileItem*>* previewableItems;
@property (nonatomic, readonly, nullable) NSArray<NSURL*>* selectedFileURLs;

// Assigned by -updateMenu: below and read by -openWithMenuAction:, which is
// Swift. It is `private` over there; @objc keeps the selector available here
// without widening the Swift name.
@property (nonatomic, nullable) OakOpenWithMenuDelegate* openWithMenuDelegate;
@end

// The action methods named by @selector in the menu construction below. These
// were FileBrowserActions.h until the flip; that header existed so the ObjC++
// .mm could see the methods Swift defines, and it is deleted now that this file
// is the only ObjC++ left that needs them.
//
// Worth keeping rather than tolerating the warnings: without a declaration every
// @selector here is -Wundeclared-selector, and a typo there produces a menu item
// that is silently dead — rule 18's failure mode exactly.
@interface FileBrowserViewController (FileBrowserSwiftActions)
- (void)openSelectedItems:(nullable id)sender;
- (void)openWithMenuAction:(nullable id)sender;
- (void)showOriginal:(nullable id)sender;
- (void)showEnclosingFolder:(nullable id)sender;
- (void)showPackageContents:(nullable id)sender;
- (void)showSelectedEntriesInFinder:(nullable id)sender;
- (void)editSelectedEntries:(nullable id)sender;
- (void)duplicateSelectedEntries:(nullable id)sender;
- (void)addSelectedEntriesToFavorites:(nullable id)sender;
- (void)removeSelectedEntriesFromFavorites:(nullable id)sender;
- (void)executeBundleCommand:(nullable id)sender;
- (void)toggleQuickLookPreview:(nullable id)sender;
- (void)didChangeFinderTag:(nullable OFBFinderTagsChooser*)finderTagsChooser;
- (void)delete:(nullable id)sender;
- (void)cut:(nullable id)sender;
- (void)copy:(nullable id)sender;
- (void)copyAsPathname:(nullable id)sender;
- (void)paste:(nullable id)sender;
- (void)pasteNext:(nullable id)sender;
- (void)createLinkToPasteboardItems:(nullable id)sender;
- (void)undo:(nullable id)sender;
- (void)redo:(nullable id)sender;
- (nullable NSURL*)newFolder:(nullable id)sender;
@end

@implementation FileBrowserViewController (Cxx)

- (std::map<std::string, std::string>)variables
{
	std::map<std::string, std::string> env;

	if(self.selectedFileURLs.count)
	{
		std::vector<std::string> paths;
		for(NSURL* url in self.selectedFileURLs)
			paths.emplace_back(path::escape(url.fileSystemRepresentation));

		env["TM_SELECTED_FILE"]  = self.selectedFileURLs.lastObject.fileSystemRepresentation;
		env["TM_SELECTED_FILES"] = text::join(paths, " ");
	}

	return env;
}

// ===============
// = Action Menu =
// ===============

- (void)updateMenu:(NSMenu*)menu
{
	NSInteger kRequiresSelectionTag = 1;

	NSMenuItem* insertBundleItemsMenuItem;
	NSMenuItem* finderTagsMenuItem;

	self.openWithMenuDelegate = [[OakOpenWithMenuDelegate alloc] initWithDocumentURLs:[self.previewableItems valueForKey:@"resolvedURL"]];

	NSString* openWithTitle = @"Open With";
	NSURL* openWithAppURL;
	for(OakOpenWithApplicationInfo* app in self.openWithMenuDelegate.applications)
	{
		if(app.isDefaultApplication)
		{
			if(![app.bundleIdentifier isEqualToString:NSBundle.mainBundle.bundleIdentifier])
			{
				openWithTitle  = [NSString stringWithFormat:@"Open With %@", app.name];
				openWithAppURL = app.URL;
			}
			break;
		}
	}

	MBMenu const items = {
		{ @"Open",                    @selector(openSelectedItems:)           },
		{ openWithTitle,              @selector(openWithMenuAction:), .delegate = self.openWithMenuDelegate, .representedObject = openWithAppURL },
		{ /* -------- */ },
		{ @"Show Original",           @selector(showOriginal:)                },
		{ @"Show Enclosing Folder",   @selector(showEnclosingFolder:)         },
		{ @"Show Package Contents",   @selector(showPackageContents:)         },
		{ @"Show in Finder",          @selector(showSelectedEntriesInFinder:) },
		{ /* -------- */ },
		{ @"New File",                @selector(newDocumentInDirectory:), @"n", NSEventModifierFlagCommand|NSEventModifierFlagControl },
		{ @"New Folder",              @selector(newFolder:),              @"n", NSEventModifierFlagCommand|NSEventModifierFlagShift   },
		{ /* -------- */ },
		{ @"Rename",                  @selector(editSelectedEntries:)                },
		{ @"Duplicate",               @selector(duplicateSelectedEntries:)           },
		{ @"Quick Look",              @selector(toggleQuickLookPreview:)             },
		{ @"Add to Favorites",        @selector(addSelectedEntriesToFavorites:)      },
		{ @"Remove From Favorites",   @selector(removeSelectedEntriesFromFavorites:) },
		{ /* -------- */ },
		{ @"Move to Trash",           @selector(delete:)   },
		{ /* -------- */ .ref = &insertBundleItemsMenuItem },
		{ /* -------- */ },
		{ @"Copy",                    @selector(copy:)                                                                            },
		{ @"Copy as Pathname",        @selector(copyAsPathname:),      @"",  NSEventModifierFlagOption, .tag = kRequiresSelectionTag, .alternate = YES },
		{ @"Paste",                   @selector(paste:),                      },
		{ @"Move Items Here",         @selector(pasteNext:),                  },
		{ @"Create Link to Items",    @selector(createLinkToPasteboardItems:) },
		{ /* -------- */ },
		{ @"Finder Tag", .tag = kRequiresSelectionTag, .ref = &finderTagsMenuItem },
		{ /* -------- */ },
		{ @"Undo",                    @selector(undo:) },
		{ @"Redo",                    @selector(redo:) },
		{ /* -------- */ },
	};

	MBCreateMenu(items, menu);

	NSDictionary<NSString*, NSString*>* inactiveKeyEquivalents = @{
		NSStringFromSelector(@selector(openSelectedItems:)):        [NSString stringWithFormat:@"@%C", (unichar)NSDownArrowFunctionKey],
		NSStringFromSelector(@selector(editSelectedEntries:)):      [NSString stringWithFormat:@"%C", (unichar)NSCarriageReturnCharacter],
		NSStringFromSelector(@selector(duplicateSelectedEntries:)): @"@d",
		NSStringFromSelector(@selector(toggleQuickLookPreview:)):   @" ",
		NSStringFromSelector(@selector(delete:)):                   [NSString stringWithFormat:@"@%C", (unichar)NSDeleteCharacter],
		NSStringFromSelector(@selector(copy:)):                     @"@c",
		NSStringFromSelector(@selector(copyAsPathname:)):           @"~@c",
		NSStringFromSelector(@selector(paste:)):                    @"@v",
		NSStringFromSelector(@selector(pasteNext:)):                @"~@v",
		NSStringFromSelector(@selector(undo:)):                     @"@z",
		NSStringFromSelector(@selector(redo:)):                     @"@Z",
	};

	for(NSMenuItem* menuItem in menu.itemArray)
	{
		if(NSString* keyEquivalent = menuItem.action ? inactiveKeyEquivalents[NSStringFromSelector(menuItem.action)] : nil)
			[menuItem setInactiveKeyEquivalent:keyEquivalent];
	}

	if(self.previewableItems.count == 0)
	{
		NSInteger i = [menu indexOfItemWithTag:kRequiresSelectionTag];
		while(i != -1)
		{
			[menu removeItemAtIndex:i];
			i = [menu indexOfItemWithTag:kRequiresSelectionTag];
		}
	}
	else
	{
		NSArray<OakFinderTag*>* allTags = [self.selectedItems valueForKeyPath:@"@unionOfArrays.finderTags"];
		NSCountedSet* finderTagsCountedSet = [[NSCountedSet alloc] initWithArray:allTags];

		NSMutableArray<OakFinderTag*>* removeFinderTags = [NSMutableArray array];
		for(OakFinderTag* tag in finderTagsCountedSet)
		{
			if([finderTagsCountedSet countForObject:tag] == self.selectedItems.count)
				[removeFinderTags addObject:tag];
		}

		OFBFinderTagsChooser* chooser = [OFBFinderTagsChooser finderTagsChooserWithSelectedTags:finderTagsCountedSet.objectEnumerator.allObjects andSelectedTagsToRemove:[removeFinderTags copy] forMenu:menu];
		chooser.action               = @selector(didChangeFinderTag:);
		chooser.target               = self;

		finderTagsMenuItem.view = chooser;

		// ================
		// = Bundle Items =
		// ================

		NSInteger i = [menu indexOfItem:insertBundleItemsMenuItem];
		for(NSMenuItem* item in [FileBrowserViewControllerSupport actionMenuItemsWithAction:@selector(executeBundleCommand:)])
			[menu insertItem:item atIndex:++i];
	}

	for(NSMenuItem* menuItem in menu.itemArray)
	{
		if(!menuItem.target && menuItem.action && [self respondsToSelector:menuItem.action])
			menuItem.target = self;
	}
}

- (void)menuNeedsUpdate:(NSMenu*)menu
{
	[menu removeAllItems];
	[self updateMenu:menu];
}
@end
