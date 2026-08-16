#import "FileBrowserViewController.h"
// The action methods this file's menu construction refers to by @selector, now
// that they are Swift. Hand-written, and imported here rather than through the
// bridging header — the FileBrowserDiskOperations.h arrangement exactly.
#import "FileBrowserActions.h"
#import "FileBrowserDiskOperations.h"
#import "FileBrowserViewControllerSupport.h"
#import "FileBrowserView.h"
#import "FileBrowserOutlineView.h"
#import "FileBrowserNotifications.h"
#import "FileItem.h"
#import "FileItemTableCellView.h"
#import "SCMManager.h"
#import "FSEventsManager.h"
#import "OFB/OFBHeaderView.h"
#import "OFB/OFBActionsView.h"
#import "OFB/OFBFinderTagsChooser.h"
#import <MenuBuilder/MenuBuilder.h>
#import <OakAppKit/NSMenuItem Additions.h>
#import <OakAppKit/NSImage Additions.h>
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakOpenWithMenu.h>
#import <OakAppKit/OakFinderTag.h>
#import <OakAppKit/OakZoomingIcon.h>
#import <OakFoundation/OakFoundation.h>
#import <TMFileReference/TMFileReference.h>
#import <Preferences/Keys.h>
#import <io/path.h>
#import <text/format.h>

static NSMutableIndexSet* MutableLongestCommonSubsequence (NSArray* lhs, NSArray* rhs)
{
	NSInteger width  = lhs.count + 1;
	NSInteger height = rhs.count + 1;

	NSInteger* matrix = new NSInteger[width * height];

	for(NSInteger i = lhs.count; i >= 0; --i)
	{
		for(NSInteger j = rhs.count; j >= 0; --j)
		{
			if(i == lhs.count || j == rhs.count)
				matrix[width*i + j] = 0;
			else if([lhs[i] isEqual:rhs[j]])
				matrix[width*i + j] = matrix[width*(i+1) + j+1] + 1;
			else
				matrix[width*i + j] = MAX(matrix[width*(i+1) + j], matrix[width*i + j+1]);
		}
	}

	NSMutableIndexSet* res = [NSMutableIndexSet indexSet];
	for(NSInteger i = 0, j = 0; i < lhs.count && j < rhs.count; )
	{
		if([lhs[i] isEqual:rhs[j]])
		{
			[res addIndex:i];
			i++;
			j++;
		}
		else if(matrix[width*i + j+1] < matrix[width*(i+1) + j])
		{
			i++;
		}
		else
		{
			j++;
		}
	}

	delete [] matrix;

	return res;
}

@interface FileBrowserViewController () <NSMenuDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, FileBrowserOutlineViewDelegate, NSTextFieldDelegate, QLPreviewPanelDataSource, OakUserDefaultsObserver>

// These nine were instance variables in a `{ … }` block until the port needed
// them. A Swift extension cannot see an ObjC ivar at all, so every method
// touching one was stuck in this file no matter how ordinary it was — the
// QuickLook section, the whole expand/collapse counter family and the async
// loading bookkeeping, twenty-two methods between them.
//
// As properties they are reachable, because FileBrowserViewControllerInternal.h
// can re-declare them readonly for the sections that need them. Nothing else
// changes: auto-synthesis backs each one with an ivar of exactly the name it
// had, so every `_foo` in this file still resolves to the same storage, and the
// ownership is the ivars' own — strong, unannotated, per rule 27, not a
// judgement about what it ought to be.
@property (nonatomic) NSUndoManager* fileBrowserUndoManager;
@property (nonatomic) NSArray<FileItem*>* previewItems;
@property (nonatomic) OakOpenWithMenuDelegate* openWithMenuDelegate;

@property (nonatomic) NSMutableDictionary<NSURL*, id>* fileItemObservers;

@property (nonatomic) NSMutableSet<NSURL*>* loadingURLs;
@property (nonatomic) NSArray<void(^)()>* loadingURLsCompletionHandlers;

@property (nonatomic) NSInteger expandingChildrenCounter;
@property (nonatomic) NSInteger collapsingChildrenCounter;
@property (nonatomic) NSInteger nestedCollapsingChildrenCounter;

@property (nonatomic) BOOL canExpandSymbolicLinks;
@property (nonatomic) BOOL canExpandPackages;
@property (nonatomic) BOOL sortDirectoriesBeforeFiles;

@property (nonatomic) BOOL showExcludedItems;

@property (nonatomic) TMFileReference* fileReference;
@property (nonatomic, readonly) NSArray<FileItem*>* selectedItems;
@property (nonatomic, readonly) NSArray<FileItem*>* previewableItems;

@property (nonatomic) NSMutableSet<NSURL*>* expandedURLs;
@property (nonatomic) NSMutableSet<NSURL*>* selectedURLs;

- (void)expandURLs:(NSArray<NSURL*>*)expandURLs selectURLs:(NSArray<NSURL*>*)selectURLs;

- (void)updateDisambiguationSuffixInParent:(FileItem*)item;

// =============================
// = FileBrowserViewController =
// =============================

@property (nonatomic) NSMenuItem* currentLocationMenuItem;
@property (nonatomic) NSMutableArray<NSDictionary*>* history;
@property (nonatomic) NSInteger historyIndex;
@property (nonatomic) FileBrowserView* fileBrowserView;
@end

@implementation FileBrowserViewController
+ (NSSet*)keyPathsForValuesAffectingCanGoBack    { return [NSSet setWithObjects:@"historyIndex", nil]; }
+ (NSSet*)keyPathsForValuesAffectingCanGoForward { return [NSSet setWithObjects:@"historyIndex", nil]; }

// Was +initialize, which a Swift class cannot provide (rule 20), so it is now
// explicit and lazy — the same conversion +load got in 2a8d36fb, and a prep step
// rather than part of the port.
//
// The timing is unchanged in every way that is observable: +initialize fired on
// the first message to the class, which in practice is the +alloc immediately
// before -init (DocumentWindowController.swift:1588 is the only construction
// site, and neither +restorableStateKeyPaths nor the two
// +keyPathsForValuesAffecting… methods can be reached before an instance
// exists). It must stay at the *top* of -init: -init itself reads
// kUserDefaultsFoldersOnTopKey three lines later, and that read is the reason
// the default is registered at all.
+ (void)registerDefaults
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		[NSApplication.sharedApplication registerServicesMenuSendTypes:@[ NSFilenamesPboardType, NSURLPboardType ] returnTypes:@[ ]];

		[NSUserDefaults.standardUserDefaults registerDefaults:@{
			kUserDefaultsFoldersOnTopKey: [[[NSUserDefaults alloc] initWithSuiteName:@"com.apple.finder"] objectForKey:@"_FXSortFoldersFirst"] ?: @NO,
		}];
	});
}

- (instancetype)init
{
	if(self = [super init])
	{
		[FileBrowserViewController registerDefaults];

		_fileItemObservers = [NSMutableDictionary dictionary];
		_loadingURLs       = [NSMutableSet set];

		_canExpandSymbolicLinks     = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsAllowExpandingLinksKey];
		_canExpandPackages          = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsAllowExpandingPackagesKey];
		_sortDirectoriesBeforeFiles = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsFoldersOnTopKey];

		_expandedURLs = [NSMutableSet set];
		_selectedURLs = [NSMutableSet set];

		OakObserveUserDefaults(self);
	}
	return self;
}

- (void)dealloc
{
	for(id observer in _fileItemObservers.allValues)
		[FileItem removeObserver:observer];
	_fileItemObservers = nil;

	if(_currentLocationMenuItem)
	{
		[_currentLocationMenuItem unbind:NSTitleBinding];
		[_currentLocationMenuItem unbind:NSImageBinding];
	}

	if(OFBHeaderView* headerView = _fileBrowserView.headerView)
	{
		[headerView.goBackButton    unbind:NSEnabledBinding];
		[headerView.goForwardButton unbind:NSEnabledBinding];

		[NSNotificationCenter.defaultCenter removeObserver:self name:NSPopUpButtonWillPopUpNotification object:headerView.folderPopUpButton];
	}
}

- (void)userDefaultsDidChange:(id)sender
{
	self.canExpandSymbolicLinks     = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsAllowExpandingLinksKey];
	self.canExpandPackages          = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsAllowExpandingPackagesKey];
	self.sortDirectoriesBeforeFiles = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsFoldersOnTopKey];
}

- (void)loadView
{
	self.view = self.fileBrowserView;
}

- (FileBrowserView*)fileBrowserView
{
	if(!_fileBrowserView)
	{
		_fileBrowserView = [[FileBrowserView alloc] initWithFrame:NSZeroRect];

		_currentLocationMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(takeURLFrom:) keyEquivalent:@""];
		_currentLocationMenuItem.target = self;
		[_currentLocationMenuItem bind:NSTitleBinding toObject:self withKeyPath:@"fileItem.displayName" options:nil];
		[_currentLocationMenuItem bind:NSImageBinding toObject:self withKeyPath:@"fileReference.image" options:nil];

		NSOutlineView* outlineView = _fileBrowserView.outlineView;
		outlineView.dataSource   = self;
		outlineView.delegate     = self;
		outlineView.target       = self;
		outlineView.action       = @selector(didSingleClickOutlineView:);
		outlineView.doubleAction = @selector(didDoubleClickOutlineView:);

		outlineView.menu = [[NSMenu alloc] init];
		outlineView.menu.delegate = self;

		OFBHeaderView* headerView = _fileBrowserView.headerView;
		headerView.goBackButton.target  = self;
		headerView.goBackButton.action  = @selector(goBack:);
		headerView.goBackButton.enabled = NO;

		headerView.goForwardButton.target  = self;
		headerView.goForwardButton.action  = @selector(goForward:);
		headerView.goForwardButton.enabled = NO;

		[headerView.goBackButton    bind:NSEnabledBinding toObject:self withKeyPath:@"canGoBack"    options:nil];
		[headerView.goForwardButton bind:NSEnabledBinding toObject:self withKeyPath:@"canGoForward" options:nil];

		NSMenu* folderPopUpMenu = headerView.folderPopUpButton.menu;
		[folderPopUpMenu removeAllItems];
		[folderPopUpMenu addItem:_currentLocationMenuItem];
		[headerView.folderPopUpButton selectItem:_currentLocationMenuItem];

		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(folderPopUpButtonWillPopUp:) name:NSPopUpButtonWillPopUpNotification object:headerView.folderPopUpButton];

		OFBActionsView* actionsView = _fileBrowserView.actionsView;

		actionsView.createButton.action    = @selector(newDocumentInDirectory:);
		actionsView.reloadButton.target    = self;
		actionsView.reloadButton.action    = @selector(reload:);
		actionsView.searchButton.action    = @selector(orderFrontFindPanelForFileBrowser:);
		actionsView.favoritesButton.target = self;
		actionsView.favoritesButton.action = @selector(goToFavorites:);
		actionsView.scmButton.target       = self;
		actionsView.scmButton.action       = @selector(goToSCMDataSource:);

		actionsView.actionsPopUpButton.menu.delegate = self;
	}
	return _fileBrowserView;
}

- (void)toggleShowInvisibles:(id)sender
{
	self.showExcludedItems = !self.showExcludedItems;
}

- (NSView*)headerView                { return self.fileBrowserView.headerView;              }
- (NSOutlineView*)outlineView        { return self.fileBrowserView.outlineView;             }
- (NSString*)path                    { return self.URL.filePathURL.path;                    }
- (NSArray<NSURL*>*)selectedFileURLs { return [[self.selectedItems filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"URL.isFileURL == YES"]] valueForKeyPath:@"URL"]; }

- (BOOL)canGoBack                    { return _historyIndex > 0; }
- (BOOL)canGoForward                 { return _historyIndex+1 < self.history.count; }

- (void)goBack:(id)sender            { self.historyIndex = _historyIndex - 1; }
- (void)goForward:(id)sender         { self.historyIndex = _historyIndex + 1; }

- (NSMutableArray<NSDictionary*>*)history
{
	if(!_history)
		_history = [NSMutableArray array];
	return _history;
}

- (void)setHistoryIndex:(NSInteger)index
{
	_historyIndex = index;
	self.URL = self.history[index][@"url"];
}

- (void)addHistoryURL:(NSURL*)url
{
	if(_historyIndex + 1 < self.history.count)
		[self.history removeObjectsInRange:NSMakeRange(_historyIndex + 1, self.history.count - (_historyIndex + 1))];

	if(NSDictionary* dict = _history.lastObject)
	{
		_history[_history.count-1] = @{
			@"url":          dict[@"url"],
			@"scrollOffset": @(NSMinY(self.outlineView.visibleRect)),
		};
	}

	[self.history addObject:@{ @"url": url }];
	self.historyIndex = self.history.count-1;
}

- (void)goToURL:(NSURL*)url
{
	if(url && ![self.URL isEqual:url])
		[self addHistoryURL:url];
}

- (void)goToComputer:(id)sender      { [self goToURL:kURLLocationComputer]; }
- (void)goToHome:(id)sender          { [self goToURL:[NSURL fileURLWithPath:NSHomeDirectory()]]; }
- (void)goToDesktop:(id)sender       { [self goToURL:[NSFileManager.defaultManager URLForDirectory:NSDesktopDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil]]; }

- (void)goToFavorites:(id)sender
{
	if(![self.URL isEqual:kURLLocationFavorites])
		[self goToURL:kURLLocationFavorites];
	else if(self.canGoBack)
		[self goBack:sender];
}

- (void)goToSCMDataSource:(id)sender
{
	NSURL* url = self.URL;
	if([url.scheme isEqualToString:@"file"])
	{
		SCMRepository* repository = [SCMManager.sharedInstance repositoryAtURL:url];
		if(repository && repository.enabled)
		{
			[self goToURL:[NSURL URLWithString:[NSString stringWithFormat:@"scm://localhost%@/", [url.path stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet]]]];
		}
		else
		{
			NSAlert* alert = [[NSAlert alloc] init];

			if(repository)
			{
				alert.messageText     = [NSString stringWithFormat:@"Version control is disabled for “%@”.", self.fileItem.localizedName];
				alert.informativeText = @"For performance reasons TextMate will not monitor version control information for this folder.";
			}
			else
			{
				alert.messageText     = [NSString stringWithFormat:@"Version control is not available for “%@”.", self.fileItem.localizedName];
				alert.informativeText = @"You need to initialize the folder using your favorite version control system before TextMate can show you status.";
			}

			[alert addButtonWithTitle:@"OK"];
			[alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response){ }];
		}
	}
	else if([url.scheme isEqualToString:@"scm"])
	{
		if(self.canGoBack)
			[self goBack:self];
		else if(NSURL* parentURL = self.fileItem.parentURL)
			[self goToURL:parentURL];
	}
	else
	{
		NSBeep();
	}
}

- (void)goToParentFolder:(id)sender
{
	if(NSURL* url = self.fileItem.parentURL)
	{
		NSURL* cameFromURL = self.URL;
		[self goToURL:url];
		[self expandURLs:nil selectURLs:@[ cameFromURL ]];
	}
}

- (void)takeURLFrom:(id)sender
{
	[self goToURL:[sender representedObject]];
}

- (void)folderPopUpButtonWillPopUp:(NSNotification*)aNotification
{
	NSMenu* menu = self.fileBrowserView.headerView.folderPopUpButton.menu;
	while(menu.numberOfItems > 1)
		[menu removeItemAtIndex:menu.numberOfItems-1];

	FileItem* fileItem = self.fileItem;
	while(fileItem = [FileItem fileItemWithURL:fileItem.parentURL])
	{
		NSMenuItem* menuItem = [menu addItemWithTitle:fileItem.localizedName action:@selector(takeURLFrom:) keyEquivalent:@""];
		menuItem.representedObject = fileItem.resolvedURL;
		menuItem.image             = [TMFileReference imageForURL:fileItem.resolvedURL size:NSMakeSize(16, 16)];
		menuItem.target            = self;
	}

	[menu addItem:[NSMenuItem separatorItem]];
	[[menu addItemWithTitle:@"Other…" action:@selector(orderFrontGoToFolder:) keyEquivalent:@""] setTarget:self];

	FileItem* item = self.fileItem;
	if(NSURL* url = item.URL.filePathURL)
	{
		[menu addItem:[NSMenuItem separatorItem]];
		[[menu addItemWithTitle:[NSString stringWithFormat:@"Use “%@” as Project Folder", item.localizedName] action:@selector(takeProjectPathFrom:) keyEquivalent:@""] setRepresentedObject:url.path];
	}
}

- (void)openItems:(NSArray<FileItem*>*)items animate:(BOOL)animateFlag
{
	NSMutableArray<FileItem*>* itemsToOpen              = [NSMutableArray array];
	NSMutableArray<FileItem*>* itemsToOpenInTextMate    = [NSMutableArray array];
	NSMutableArray<FileItem*>* itemsToShowInFinder      = [NSMutableArray array];
	NSMutableArray<FileItem*>* itemsToShowInFileBrowser = [NSMutableArray array];

	NSEventType eventType           = NSApp.currentEvent.type;
	NSEventModifierFlags eventFlags = NSApp.currentEvent.modifierFlags & (NSEventModifierFlagControl|NSEventModifierFlagOption|NSEventModifierFlagShift|NSEventModifierFlagCommand);
	BOOL isMouseEvent               = eventType == NSEventTypeLeftMouseUp || eventType == NSEventTypeOtherMouseUp || eventType == NSEventTypeOtherMouseUp;
	BOOL commandKeyDown             = isMouseEvent && eventFlags == NSEventModifierFlagCommand;
	BOOL optionKeyDown              = isMouseEvent && eventFlags == NSEventModifierFlagOption;
	BOOL treatPackageAsDirectory    = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsAllowExpandingPackagesKey];

	for(FileItem* item in items)
	{
		if(commandKeyDown)
			[itemsToShowInFinder addObject:item];
		else if(item.isDirectory && (treatPackageAsDirectory || !item.isPackage) || item.isLinkToDirectory && (treatPackageAsDirectory || !item.isLinkToPackage) || optionKeyDown && (item.isPackage || item.isLinkToDirectory))
			[itemsToShowInFileBrowser addObject:item];
		else if(item.isPackage || item.isLinkToPackage || item.URL.isFileURL && [FileBrowserViewControllerSupport isBinaryURL:item.URL])
			[itemsToOpen addObject:item];
		else
			[itemsToOpenInTextMate addObject:item];
	}

	if(itemsToShowInFileBrowser.count > 0)
		return [self goToURL:itemsToShowInFileBrowser.firstObject.resolvedURL];

	if(animateFlag && ![NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsFileBrowserOpenAnimationDisabled])
	{
		for(NSArray* items in @[ itemsToOpen, itemsToOpenInTextMate ])
		{
			for(FileItem* item in items)
				[OakZoomingIcon zoomIcon:[TMFileReference imageForURL:item.URL size:NSMakeSize(48, 48)] fromRect:[self imageRectOfItem:item]];
		}
	}

	if(itemsToShowInFinder.count > 0)
		[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:[itemsToShowInFinder valueForKeyPath:@"URL"]];

	for(FileItem* item in itemsToOpen)
		[NSWorkspace.sharedWorkspace openFile:item.resolvedURL.path];

	if(itemsToOpenInTextMate.count > 0)
		[self.delegate fileBrowser:self openURLs:[itemsToOpenInTextMate valueForKeyPath:@"URL"]];
}

- (void)didSingleClickOutlineView:(id)sender
{
	if(NSEvent.modifierFlags & (NSEventModifierFlagControl|NSEventModifierFlagShift|NSEventModifierFlagCommand))
		return;

	if([NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsFileBrowserSingleClickToOpenKey])
	{
		FileItem* item = [self.outlineView itemAtRow:self.outlineView.clickedRow];
		if(item && !item.isDirectory && !item.isLinkToDirectory && !item.isPackage && !item.isLinkToPackage && !item.isApplication)
			[self openItems:@[ item ] animate:NO];
	}
}

- (void)didDoubleClickOutlineView:(id)sender
{
	[self openItems:self.selectedItems animate:YES];
}

// ===============
// = Action Menu =
// ===============

- (void)updateMenu:(NSMenu*)menu
{
	NSInteger kRequiresSelectionTag = 1;

	NSMenuItem* insertBundleItemsMenuItem;
	NSMenuItem* finderTagsMenuItem;

	_openWithMenuDelegate = [[OakOpenWithMenuDelegate alloc] initWithDocumentURLs:[self.previewableItems valueForKey:@"resolvedURL"]];

	NSString* openWithTitle = @"Open With";
	NSURL* openWithAppURL;
	for(OakOpenWithApplicationInfo* app in _openWithMenuDelegate.applications)
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
		{ openWithTitle,              @selector(openWithMenuAction:), .delegate = _openWithMenuDelegate, .representedObject = openWithAppURL },
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

// ==================
// = Action Methods =
// ==================

- (void)openWithMenuAction:(id)sender
{
	if(NSURL* appURL = [sender representedObject])
		[_openWithMenuDelegate openDocumentURLs:[self.previewableItems valueForKey:@"resolvedURL"] withApplicationURL:appURL];
}

- (NSURL*)newFile:(id)sender
{
	NSURL* directoryURL = self.directoryURLForNewItems;
	if(!directoryURL)
		return nil;

	NSString* pathExtension = @"txt";
	if(NSString* ext = [FileBrowserViewControllerSupport pathExtensionForNewFileInDirectoryURL:directoryURL])
		pathExtension = ext;

	NSURL* newFileURL = [[directoryURL URLByAppendingPathComponent:@"untitled" isDirectory:NO] URLByAppendingPathExtension:pathExtension];
	NSArray<NSURL*>* urls = [self performOperation:FBOperationNewFile sourceURLs:nil destinationURLs:@[ newFileURL ] unique:YES select:YES];
	if(urls.count == 1 && self.outlineView.numberOfSelectedRows == 1)
	{
		FileItem* newItem = [self.outlineView itemAtRow:self.outlineView.selectedRow];
		if([newItem.URL isEqual:urls.firstObject])
		{
			[self.outlineView scrollRowToVisible:self.outlineView.selectedRow];
			[self.outlineView editColumn:0 row:self.outlineView.selectedRow withEvent:nil select:YES];
		}
	}
	return urls.firstObject;
}

- (NSURL*)newFolder:(id)sender
{
	NSURL* directoryURL = self.directoryURLForNewItems;
	if(!directoryURL)
		return nil;

	NSURL* newFolderURL = [directoryURL URLByAppendingPathComponent:@"untitled folder" isDirectory:YES];
	NSArray<NSURL*>* urls = [self performOperation:FBOperationNewFolder sourceURLs:nil destinationURLs:@[ newFolderURL ] unique:YES select:YES];
	if(urls.count == 1 && self.outlineView.numberOfSelectedRows == 1)
	{
		FileItem* newItem = [self.outlineView itemAtRow:self.outlineView.selectedRow];
		if([newItem.URL isEqual:urls.firstObject])
		{
			[self.outlineView scrollRowToVisible:self.outlineView.selectedRow];
			[self.outlineView editColumn:0 row:self.outlineView.selectedRow withEvent:nil select:YES];
		}
	}
	return urls.firstObject;
}

// =====================
// = NSRestorableState =
// =====================

+ (NSArray<NSString*>*)restorableStateKeyPaths
{
	return @[ @"showExcludedItems" ];
}

- (void)restoreStateWithCoder:(NSCoder*)state
{
	[super restoreStateWithCoder:state];

	NSArray* newHistory = [state decodeObjectForKey:@"history"];
	if(newHistory.count)
	{
		self.history      = [newHistory mutableCopy];
		self.historyIndex = std::clamp<NSInteger>([state decodeIntegerForKey:@"historyIndex"], 0, newHistory.count);

		NSArray<NSURL*>* expandedURLs = [state decodeObjectForKey:@"expandedURLs"];
		NSArray<NSURL*>* selectedURLs = [state decodeObjectForKey:@"selectedURLs"];
		[self expandURLs:expandedURLs selectURLs:selectedURLs];
	}
}

- (void)encodeRestorableStateWithCoder:(NSCoder*)state
{
	[super encodeRestorableStateWithCoder:state];

	NSMutableArray* history = [NSMutableArray array];
	NSUInteger from = _history.count > 5 ? _history.count - 5 : 0;
	for(NSUInteger i = from; i < _history.count; ++i)
	{
		NSDictionary* record = _history[i];
		NSNumber* scrollOffset = i == _historyIndex ? @(NSMinY(self.outlineView.visibleRect)) : record[@"scrollOffset"];
		if(scrollOffset && scrollOffset.doubleValue > 0)
		{
			[history addObject:@{
				@"url":          record[@"url"],
				@"scrollOffset": scrollOffset,
			}];
		}
		else
		{
			[history addObject:@{ @"url": record[@"url"], }];
		}
	}

	[state encodeObject:history forKey:@"history"];
	[state encodeInteger:_historyIndex - from forKey:@"historyIndex"];
	[state encodeObject:self.selectedURLs.allObjects forKey:@"selectedURLs"];
	[state encodeObject:self.expandedURLs.allObjects forKey:@"expandedURLs"];
}

// ==============
// = Public API =
// ==============

- (id)sessionState
{
	if(NSKeyedArchiver* coder = [[NSKeyedArchiver alloc] init])
	{
		[self encodeRestorableStateWithCoder:coder];
		[coder finishEncoding];
		return coder.encodedData;
	}
	return nil;
}

- (void)setupViewWithState:(id)state
{
	if([state isKindOfClass:[NSData class]])
	{
		if(NSCoder* coder = [[NSKeyedUnarchiver alloc] initForReadingWithData:state])
			[self restoreStateWithCoder:coder];
	}
	else if([state isKindOfClass:[NSDictionary class]])
	{
		NSDictionary* fileBrowserState = state;

		self.showExcludedItems = [fileBrowserState[@"showHidden"] boolValue];

		NSMutableArray* newHistory = [NSMutableArray array];
		for(NSDictionary* entry in fileBrowserState[@"history"])
		{
			if(NSString* urlString = entry[@"url"])
			{
				[newHistory addObject:@{
					@"url": [NSURL URLWithString:urlString],
				}];
			}
		}

		if(newHistory.count)
		{
			self.history      = newHistory;
			self.historyIndex = std::clamp([fileBrowserState[@"historyIndex"] unsignedIntegerValue], (NSUInteger)0, newHistory.count);

			NSMutableArray<NSURL*>* expandedURLs = [NSMutableArray array];
			for(NSString* urlString in fileBrowserState[@"expanded"])
				[expandedURLs addObject:[NSURL URLWithString:urlString]];

			NSMutableArray<NSURL*>* selectedURLs = [NSMutableArray array];
			for(NSString* urlString in fileBrowserState[@"selection"])
				[selectedURLs addObject:[NSURL URLWithString:urlString]];

			[self expandURLs:expandedURLs selectURLs:selectedURLs];
		}
	}
}

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

- (void)selectURL:(NSURL*)url withParentURL:(NSURL*)parentURL
{
	NSURL* fileReferenceURL = url.fileReferenceURL;
	for(NSInteger i = 0; i < self.outlineView.numberOfRows; ++i)
	{
		FileItem* item = [self.outlineView itemAtRow:i];
		if([url isEqual:item.URL] || [fileReferenceURL isEqual:item.fileReferenceURL])
		{
			[self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
			[self centerSelectionInVisibleArea:self];
			return;
		}
	}

	NSURL* currentParent = self.URL;
	NSMutableSet<NSURL*>* expandURLs = [self.expandedURLs mutableCopy];

	NSURL* childURL = url;
	while(true)
	{
		NSNumber* flag;
		if([childURL getResourceValue:&flag forKey:NSURLIsVolumeKey error:nil] && flag.boolValue)
			break;

		NSURL* potentialParentURL;
		if(![childURL getResourceValue:&potentialParentURL forKey:NSURLParentDirectoryURLKey error:nil] || [childURL isEqual:potentialParentURL])
			break;

		childURL = potentialParentURL;
		if([childURL isEqual:currentParent])
		{
			parentURL = currentParent;
			break;
		}

		if([childURL isEqual:parentURL])
			break;

		[expandURLs addObject:childURL];
	}

	if([childURL isEqual:parentURL])
	{
		[self goToURL:parentURL];
		[self expandURLs:expandURLs.allObjects selectURLs:@[ url ]];
	}
	else
	{
		[self goToURL:url.URLByDeletingLastPathComponent];
		[self expandURLs:nil selectURLs:@[ url ]];
	}
}

- (void)deselectAll:(id)sender
{
	[self.outlineView deselectAll:sender];
}

- (void)orderFrontGoToFolder:(id)sender
{
	NSOpenPanel* panel = [NSOpenPanel openPanel];

	panel.canChooseFiles          = NO;
	panel.canChooseDirectories    = YES;
	panel.allowsMultipleSelection = NO;
	panel.directoryURL            = self.URL.filePathURL;

	[panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
		if(result == NSModalResponseOK)
			[self goToURL:panel.URLs.lastObject];
	}];
}

// =========
// = Swipe =
// =========

- (BOOL)wantsScrollEventsForSwipeTrackingOnAxis:(NSEventGestureAxis)axis
{
	return axis == NSEventGestureAxisHorizontal;
}

- (void)scrollWheel:(NSEvent*)anEvent
{
	if(!NSEvent.isSwipeTrackingFromScrollEventsEnabled || anEvent.phase == NSEventPhaseNone || fabs(anEvent.scrollingDeltaX) <= fabs(anEvent.scrollingDeltaY))
		return;

	[anEvent trackSwipeEventWithOptions:0 dampenAmountThresholdMin:(self.canGoForward ? -1 : 0) max:(self.canGoBack ? +1 : 0) usingHandler:^(CGFloat gestureAmount, NSEventPhase phase, BOOL isComplete, BOOL* stop) {
		if(phase == NSEventPhaseBegan)
		{
			// Setup animation overlay layers
		}

		// Update animation overlay to match gestureAmount

		if(phase == NSEventPhaseEnded)
		{
			if(gestureAmount > 0 && self.canGoBack)
				[self goBack:self];
			else if(gestureAmount < 0 && self.canGoForward)
				[self goForward:self];
		}

		if(isComplete)
		{
			// Tear down animation overlay here
		}
	}];
}

// ========================
// = From FileBrowserView =
// ========================

- (void)setCanExpandSymbolicLinks:(BOOL)flag
{
	if(_canExpandSymbolicLinks == flag)
		return;
	_canExpandSymbolicLinks = flag;

	if(!self.fileItem)
		return;

	NSMutableArray<FileItem*>* stack = [self.fileItem.arrangedChildren mutableCopy];
	while(FileItem* item = stack.firstObject)
	{
		[stack removeObjectAtIndex:0];
		if(item.isLinkToDirectory && (_canExpandPackages || !item.isLinkToPackage))
			[self.outlineView reloadItem:item reloadChildren:YES];
		if([self.outlineView isExpandable:item] && item.arrangedChildren)
			[stack addObjectsFromArray:item.arrangedChildren];
	}
}

- (void)setCanExpandPackages:(BOOL)flag
{
	if(_canExpandPackages == flag)
		return;
	_canExpandPackages = flag;

	if(!self.fileItem)
		return;

	NSMutableArray<FileItem*>* stack = [self.fileItem.arrangedChildren mutableCopy];
	while(FileItem* item = stack.firstObject)
	{
		[stack removeObjectAtIndex:0];
		if(item.isDirectory && item.isPackage)
			[self.outlineView reloadItem:item reloadChildren:YES];
		if([self.outlineView isExpandable:item] && item.arrangedChildren)
			[stack addObjectsFromArray:item.arrangedChildren];
	}
}

- (void)setSortDirectoriesBeforeFiles:(BOOL)flag
{
	if(_sortDirectoriesBeforeFiles == flag)
		return;
	_sortDirectoriesBeforeFiles = flag;

	if(!self.fileItem)
		return;

	NSMutableArray<FileItem*>* stack = [NSMutableArray arrayWithObject:self.fileItem];
	while(FileItem* item = stack.firstObject)
	{
		[stack removeObjectAtIndex:0];
		[self rearrangeChildrenInParent:item];
		if(item == self.fileItem || [self.outlineView isItemExpanded:item])
			[stack addObjectsFromArray:item.arrangedChildren];
	}
}

- (void)setShowExcludedItems:(BOOL)flag
{
	if(_showExcludedItems == flag)
		return;
	_showExcludedItems = flag;

	if(!self.fileItem)
		return;

	NSMutableArray<FileItem*>* stack = [NSMutableArray arrayWithObject:self.fileItem];
	while(FileItem* item = stack.firstObject)
	{
		[stack removeObjectAtIndex:0];
		[self rearrangeChildrenInParent:item];
		if(item == self.fileItem || [self.outlineView isItemExpanded:item])
			[stack addObjectsFromArray:item.arrangedChildren];
	}
}

- (NSComparator)itemComparator
{
	NSArray<NSSortDescriptor*>* sortDescriptors = @[
		[NSSortDescriptor sortDescriptorWithKey:@"localizedName" ascending:YES selector:@selector(localizedCompare:)],
		[NSSortDescriptor sortDescriptorWithKey:@"URL.URLByDeletingLastPathComponent.lastPathComponent" ascending:YES selector:@selector(localizedCompare:)],
	];

	return ^NSComparisonResult(FileItem* lhs, FileItem* rhs){
		if(_sortDirectoriesBeforeFiles)
		{
			if((lhs.isDirectory || lhs.isLinkToDirectory) && !(rhs.isDirectory || rhs.isLinkToDirectory))
				return NSOrderedAscending;
			else if((rhs.isDirectory || rhs.isLinkToDirectory) && !(lhs.isDirectory || lhs.isLinkToDirectory))
				return NSOrderedDescending;
		}

		for(NSSortDescriptor* sortDescriptor in sortDescriptors)
		{
			NSComparisonResult order = [sortDescriptor compareObject:lhs toObject:rhs];
			if(order != NSOrderedSame)
				return order;
		}

		return NSOrderedSame;
	};
}

- (NSPredicate*)itemPredicateForChildrenInParent:(FileItem*)parentOrNil
{
	if(_showExcludedItems)
		return [NSPredicate predicateWithValue:YES];
	return [FileBrowserViewControllerSupport itemPredicateForDirectoryURL:(parentOrNil ?: self.fileItem).URL];
}

- (NSArray<FileItem*>*)arrangeChildren:(NSArray<FileItem*>*)children inParent:(FileItem*)parentOrNil
{
	return [[children filteredArrayUsingPredicate:[self itemPredicateForChildrenInParent:parentOrNil]] sortedArrayUsingComparator:self.itemComparator];
}

- (void)rearrangeChildrenInParent:(FileItem*)item
{
	NSMutableArray<FileItem*>* existingChildren = item.arrangedChildren;
	if(existingChildren && existingChildren.count * item.children.count < 250000)
	{
		NSArray* newArrangedChildren = [self arrangeChildren:item.children inParent:item];

		// ================
		// = Remove Items =
		// ================

		NSMutableIndexSet* indexesToRemove = [NSMutableIndexSet indexSet];
		for(NSUInteger i = 0; i < existingChildren.count; ++i)
		{
			if(![newArrangedChildren containsObject:existingChildren[i]])
				[indexesToRemove addIndex:i];
		}

		if(indexesToRemove.count)
		{
			BOOL wasFirstResponderInOutlineView = [self.outlineView.window.firstResponder isKindOfClass:[NSView class]] && [(NSView*)self.outlineView.window.firstResponder isDescendantOf:self.outlineView];

			[existingChildren removeObjectsAtIndexes:indexesToRemove];
			[self.outlineView removeItemsAtIndexes:indexesToRemove inParent:(item != self.fileItem ? item : nil) withAnimation:NSTableViewAnimationEffectFade|NSTableViewAnimationSlideUp];

			if(wasFirstResponderInOutlineView && !([self.outlineView.window.firstResponder isKindOfClass:[NSView class]] && [(NSView*)self.outlineView.window.firstResponder isDescendantOf:self.outlineView]))
				[self.outlineView.window makeFirstResponder:self.outlineView];
		}

		// =======================
		// = Move Items (rename) =
		// =======================

		NSComparator compare = self.itemComparator;

		BOOL alreadySorted = YES;
		for(NSUInteger i = 1; alreadySorted && i < existingChildren.count; ++i)
			alreadySorted = compare(existingChildren[i-1], existingChildren[i]) != NSOrderedDescending;

		if(!alreadySorted)
		{
			NSMutableIndexSet* lcs = MutableLongestCommonSubsequence(existingChildren, newArrangedChildren);

			std::vector<std::pair<BOOL, FileItem*>> v;
			for(NSUInteger i = 0; i < existingChildren.count; ++i)
				v.emplace_back([lcs containsIndex:i], existingChildren[i]);

			for(NSUInteger i = 0; i < v.size(); )
			{
				if(v[i].first == YES)
				{
					i++;
				}
				else
				{
					FileItem* child = existingChildren[i];

					v.erase(v.begin() + i);
					NSInteger newIndex = 0;
					for(; newIndex < v.size(); ++newIndex)
					{
						if(v[newIndex].first && compare(child, v[newIndex].second) == NSOrderedAscending)
							break;
					}
					v.emplace(v.begin() + newIndex, YES, child);

					[existingChildren removeObjectAtIndex:i];
					[existingChildren insertObject:child atIndex:newIndex];
					[self.outlineView moveItemAtIndex:i inParent:(item != self.fileItem ? item : nil) toIndex:newIndex inParent:(item != self.fileItem ? item : nil)];
				}
			}
		}

		// ================
		// = Insert Items =
		// ================

		NSMutableIndexSet* insertionIndexes = [NSMutableIndexSet indexSet];
		for(NSUInteger i = 0; i < newArrangedChildren.count; ++i)
		{
			FileItem* child = newArrangedChildren[i];
			if(![existingChildren containsObject:child])
				[insertionIndexes addIndex:i];
		}

		if(insertionIndexes.count)
		{
			[existingChildren insertObjects:[newArrangedChildren objectsAtIndexes:insertionIndexes] atIndexes:insertionIndexes];
			[self.outlineView insertItemsAtIndexes:insertionIndexes inParent:(item != self.fileItem ? item : nil) withAnimation:NSTableViewAnimationEffectFade|NSTableViewAnimationSlideUp];
		}
	}
	else
	{
		item.arrangedChildren = [[self arrangeChildren:item.children inParent:item] mutableCopy];
		[self.outlineView reloadItem:(item != self.fileItem ? item : nil) reloadChildren:YES];

		if(item == self.fileItem)
			[self.outlineView setNeedsDisplay:YES];
	}

	[self updateDisambiguationSuffixInParent:item];
}

- (NSString*)disambiguationSuffixForURL:(NSURL*)url numberOfParents:(NSInteger)numberOfParents
{
	NSMutableArray* parentNames = [NSMutableArray array];
	for(NSUInteger i = 0; i < numberOfParents; ++i)
	{
		NSNumber* flag;
		if([url getResourceValue:&flag forKey:NSURLIsVolumeKey error:nil] && flag.boolValue)
			return nil;

		NSURL* parentURL;
		if(![url getResourceValue:&parentURL forKey:NSURLParentDirectoryURLKey error:nil] || [url isEqual:parentURL])
			return nil;

		NSString* parentName;
		if(![parentURL getResourceValue:&parentName forKey:NSURLLocalizedNameKey error:nil])
			return nil;

		[parentNames addObject:parentName];
		url = parentURL;
	}
	return [[parentNames.reverseObjectEnumerator allObjects] componentsJoinedByString:@"/"];
}

- (void)updateDisambiguationSuffixInParent:(FileItem*)item
{
	NSArray* children = [item.arrangedChildren filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"URL.isFileURL == YES"]];
	for(FileItem* child in children)
		child.disambiguationSuffix = nil;

	NSInteger showNumberOfParents = 1;
	while(children.count)
	{
		NSCountedSet* countOfConflicts = [[NSCountedSet alloc] initWithArray:[children valueForKeyPath:@"displayName"]];
		NSMutableArray* conflictedChildren = [NSMutableArray array];
		for(FileItem* child in children)
		{
			if([countOfConflicts countForObject:child.displayName] == 1)
				continue;

			if(NSString* newSuffix = [self disambiguationSuffixForURL:child.URL numberOfParents:showNumberOfParents])
			{
				child.disambiguationSuffix = [@" — " stringByAppendingString:newSuffix];
				[conflictedChildren addObject:child];
			}
		}
		children = conflictedChildren;
		++showNumberOfParents;
	}
}

// ===========================
// = Loading/Expanding Items =
// ===========================

- (void)setFileItem:(FileItem*)item
{
	if(_fileItem)
	{
		// Remove visible but non-selected/expanded items from pending selection/expansion
		_expandedURLs = [self.expandedURLs mutableCopy];
		_selectedURLs = [self.selectedURLs mutableCopy];

		for(id observer in _fileItemObservers.allValues)
			[FileItem removeObserver:observer];
		_fileItemObservers = [NSMutableDictionary dictionary];
	}

	_fileItem = item;

	NSURL* url = _fileItem.URL;
	if(url.isFileURL)
	{
		self.fileReference = [TMFileReference fileReferenceWithURL:url];
	}
	else
	{
		NSImage* image;
		if([url.scheme isEqualToString:@"scm"])
		{
			if([url.query hasSuffix:@"unstaged"] || [url.query hasSuffix:@"untracked"])
					image = [NSWorkspace.sharedWorkspace iconForFileType:NSFileTypeForHFSTypeCode((OSType)kGenericFolderIcon)];
			else	image = [NSImage imageNamed:@"SCMTemplate" inSameBundleAsClass:NSClassFromString(@"OakFileBrowser")];
		}
		else if([url.scheme isEqualToString:@"computer"])
		{
			image = [NSImage imageNamed:NSImageNameComputer];
		}
		else
		{
			image = [NSWorkspace.sharedWorkspace iconForFileType:NSFileTypeForHFSTypeCode((OSType)kGenericFolderIcon)];
		}

		image = [image copy];
		image.size = NSMakeSize(16, 16);
		self.fileReference = [TMFileReference fileReferenceWithImage:image];
	}

	[self.outlineView reloadItem:nil reloadChildren:YES];
	[self.outlineView deselectAll:self];
	[self.outlineView scrollRowToVisible:0];

	[self loadChildrenForItem:item expandChildren:NO];

	[self invalidateRestorableState];
}

- (void)outlineViewItemDidExpand:(NSNotification*)aNotification
{
	FileItem* item = aNotification.userInfo[@"NSObject"];
	[self loadChildrenForItem:item expandChildren:_expandingChildrenCounter > 0];
	[self invalidateRestorableState];
}

- (void)loadChildrenForItem:(FileItem*)item expandChildren:(BOOL)flag
{
	if(item.arrangedChildren || item.children)
		return;

	NSURL* url = item.URL;

	if(_fileItemObservers[url])
	{
		// ================
		// = Debug Output =
		// ================

		NSMutableArray<NSString*>* itemInfo = [NSMutableArray array];

		NSMutableArray<FileItem*>* stack = [NSMutableArray arrayWithObject:self.fileItem];
		while(FileItem* item = stack.firstObject)
		{
			if(item.isDirectory)
			{
				NSMutableString* info = [item.URL.path mutableCopy];
				if(item == self.fileItem || [self.outlineView isItemExpanded:item])
					[info appendString:@" [expanded]"];
				if([_fileItemObservers objectForKey:item.URL])
					[info appendString:@" [observing]"];
				if([_loadingURLs containsObject:item.URL])
					[info appendString:@" [loading]"];
				if(item.arrangedChildren || item.children)
					[info appendFormat:@" [%lu / %lu children]", item.arrangedChildren.count, item.children.count];
				[itemInfo addObject:info];
			}

			[stack removeObjectAtIndex:0];
			if(NSArray<FileItem*>* children = item.arrangedChildren)
				[stack addObjectsFromArray:children];
		}

		NSLog(@"%s *** Observer already exists for: %@\n%@", sel_getName(_cmd), url, [itemInfo componentsJoinedByString:@"\n"]);

		// ===================================
		// = Temporary (possible) workaround =
		// ===================================

		[FileItem removeObserver:_fileItemObservers[url]];
		_fileItemObservers[url] = nil;
	}

	[_loadingURLs addObject:url];

	__weak FileBrowserViewController* weakSelf = self;
	_fileItemObservers[url] = [FileItem addObserverToDirectoryAtURL:item.resolvedURL usingBlock:^(NSArray<NSURL*>* urls){
		[weakSelf didReceiveURLs:urls forItemWithURL:url expandChildren:flag];
	}];
}

- (FileItem*)findItemForURL:(NSURL*)url
{
	NSMutableArray<FileItem*>* stack = [NSMutableArray arrayWithObject:self.fileItem];
	while(FileItem* item = stack.firstObject)
	{
		[stack removeObjectAtIndex:0];
		if([item.URL isEqual:url])
			return item;
		if(NSArray<FileItem*>* children = item.arrangedChildren)
			[stack addObjectsFromArray:children];
	}
	return nil;
}

- (void)didReceiveURLs:(NSArray<NSURL*>*)urls forItemWithURL:(NSURL*)url expandChildren:(BOOL)flag
{
	FileItem* item = [self findItemForURL:url];
	if(!item)
	{
		NSLog(@"%s *** unable to find item for %@", sel_getName(_cmd), url);
	}
	else if(item != self.fileItem && ![self.outlineView isItemExpanded:item])
	{
		NSLog(@"%s *** item no longer expanded: %@", sel_getName(_cmd), item);

		item.children = nil;
		item.arrangedChildren = nil;
		[self.outlineView reloadItem:item reloadChildren:YES];

		[FileItem removeObserver:_fileItemObservers[url]];
		_fileItemObservers[url] = nil;
	}
	else
	{
		NSMutableArray* children = [NSMutableArray array];

		if(item.children)
		{
			NSMutableSet<NSURL*>* newURLs = [NSMutableSet setWithArray:urls];

			for(FileItem* child in item.children)
			{
				if(NSURL* url = child.fileReferenceURL.filePathURL)
					child.URL = url;

				if([newURLs containsObject:child.URL])
				{
					[newURLs removeObject:child.URL];
					[child updateFileProperties];
					[children addObject:child];
				}
			}

			urls = newURLs.allObjects;
		}

		for(NSURL* url in urls)
			[children addObject:[FileItem fileItemWithURL:url]];

		item.children = [children copy];
		[self rearrangeChildrenInParent:item];

		for(FileItem* child in item.arrangedChildren)
		{
			if((flag && !child.isSymbolicLink || [_expandedURLs containsObject:child.URL] || [child.URL.scheme isEqualToString:@"scm"]) && [self.outlineView isExpandable:child])
				[self.outlineView expandItem:child expandChildren:flag && !child.isSymbolicLink];

			if([_selectedURLs containsObject:child.URL])
			{
				[self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:[self.outlineView rowForItem:child]] byExtendingSelection:YES];
				[_selectedURLs removeObject:child.URL];
			}
		}
	}

	[_loadingURLs removeObject:url];
	[self checkLoadCompletionHandlers];
}

- (void)checkLoadCompletionHandlers
{
	if(_loadingURLs.count == 0)
	{
		NSArray<void(^)()>* completionHandlers = _loadingURLsCompletionHandlers;
		_loadingURLsCompletionHandlers = nil;
		for(void(^handler)() in completionHandlers)
			handler();
	}
}

- (void)expandURLs:(NSArray<NSURL*>*)expandURLs selectURLs:(NSArray<NSURL*>*)selectURLs
{
	_loadingURLsCompletionHandlers = [(_loadingURLsCompletionHandlers ?: @[ ]) arrayByAddingObject:^{
		[self performSelector:@selector(centerSelectionInVisibleArea:) withObject:self afterDelay:0];
	}];

	_expandedURLs = expandURLs ? [NSMutableSet setWithArray:expandURLs] : _expandedURLs;
	_selectedURLs = selectURLs ? [NSMutableSet setWithArray:selectURLs] : _selectedURLs;

	NSMutableArray<FileItem*>* stack = [self.fileItem.arrangedChildren mutableCopy];
	while(FileItem* item = stack.firstObject)
	{
		[stack removeObjectAtIndex:0];
		if([_expandedURLs containsObject:item.URL])
		{
			[self.outlineView expandItem:item];
			if(NSArray<FileItem*>* arrangedChildren = item.arrangedChildren)
				[stack addObjectsFromArray:arrangedChildren];
		}
	}

	NSMutableIndexSet* indexesToSelect = [NSMutableIndexSet indexSet];
	for(NSUInteger i = 0; i < self.outlineView.numberOfRows; ++i)
	{
		FileItem* item = [self.outlineView itemAtRow:i];
		if([_selectedURLs containsObject:item.URL])
			[indexesToSelect addIndex:i];
	}
	[self.outlineView selectRowIndexes:indexesToSelect byExtendingSelection:NO];

	[self checkLoadCompletionHandlers];
}

- (void)outlineView:(NSOutlineView*)outlineView willExpandItem:(FileItem*)item expandChildren:(BOOL)flag
{
	_expandingChildrenCounter += flag ? 1 : 0;
}

- (void)outlineView:(NSOutlineView*)outlineView didExpandItem:(FileItem*)item expandChildren:(BOOL)flag
{
	_expandingChildrenCounter -= flag ? 1 : 0;
}

- (void)outlineView:(NSOutlineView*)outlineView willCollapseItem:(id)someItem collapseChildren:(BOOL)flag
{
	_collapsingChildrenCounter += flag ? 1 : 0;
}

- (void)outlineView:(NSOutlineView*)outlineView didCollapseItem:(id)someItem collapseChildren:(BOOL)flag
{
	_collapsingChildrenCounter -= flag ? 1 : 0;
}

- (void)outlineViewItemWillCollapse:(NSNotification*)aNotification
{
	FileItem* item = aNotification.userInfo[@"NSObject"];
	if(_nestedCollapsingChildrenCounter == 0 || _collapsingChildrenCounter > 0)
		[_expandedURLs removeObject:item.URL];

	_nestedCollapsingChildrenCounter += 1;
}

- (void)outlineViewItemDidCollapse:(NSNotification*)aNotification
{
	_nestedCollapsingChildrenCounter -= 1;

	if(_nestedCollapsingChildrenCounter == 0)
		[self invalidateRestorableState];
}

- (void)outlineViewSelectionDidChange:(NSNotification*)aNotification
{
	[self invalidateRestorableState];
}

// ================
// = Location URL =
// ================

- (NSURL*)URL
{
	return _fileItem.URL;
}

- (void)setURL:(NSURL*)url
{
	if(FileItem* item = [FileItem fileItemWithURL:url])
		self.fileItem = item;
}

- (void)reload:(id)sender
{
	NSMutableArray<FileItem*>* stack = [NSMutableArray arrayWithObject:self.fileItem];
	while(FileItem* item = stack.firstObject)
	{
		[stack removeObjectAtIndex:0];
		if(!item.arrangedChildren)
			continue;
		[FSEventsManager.sharedInstance reloadDirectoryAtURL:item.resolvedURL];
		[stack addObjectsFromArray:item.arrangedChildren];
	}
}

- (NSArray<FileItem*>*)selectedItems
{
	NSIndexSet* indexSet;

	NSInteger clickedRow = self.outlineView.clickedRow;
	if(0 <= clickedRow && clickedRow < self.outlineView.numberOfRows && ![self.outlineView.selectedRowIndexes containsIndex:clickedRow])
			indexSet = [NSIndexSet indexSetWithIndex:clickedRow];
	else	indexSet = self.outlineView.selectedRowIndexes;

	NSMutableArray* res = [NSMutableArray array];
	for(NSUInteger index = indexSet.firstIndex; index != NSNotFound; index = [indexSet indexGreaterThanIndex:index])
		[res addObject:[self.outlineView itemAtRow:index]];
	return res;
}

- (NSURL*)directoryURLForNewItems
{
	NSMutableArray<NSURL*>* candidates = [NSMutableArray array];
	for(FileItem* item in self.selectedItems)
	{
		if(item.resolvedURL.isFileURL && [self.outlineView isItemExpanded:item])
		{
			[candidates addObject:item.resolvedURL];
		}
		else if(FileItem* parentItem = [self.outlineView parentForItem:item])
		{
			if(parentItem.resolvedURL.isFileURL)
				[candidates addObject:parentItem.resolvedURL];
		}
	}
	return candidates.lastObject ?: self.fileItem.URL.filePathURL;
}

- (void)centerSelectionInVisibleArea:(id)sender
{
	if(self.outlineView.numberOfSelectedRows == 0)
		return;

	NSInteger row = self.outlineView.selectedRowIndexes.firstIndex;

	NSRect rowRect     = [self.outlineView rectOfRow:row];
	NSRect visibleRect = self.outlineView.visibleRect;
	if(NSMinY(rowRect) < NSMinY(visibleRect) || NSMaxY(rowRect) > NSMaxY(visibleRect))
		[self.outlineView scrollPoint:NSMakePoint(NSMinX(rowRect), round(NSMidY(rowRect) - NSHeight(visibleRect)/2))];
}

- (NSSet<NSURL*>*)selectedURLs
{
	NSMutableSet<NSURL*>* res = [_selectedURLs mutableCopy];
	NSIndexSet* selectedIndexes = self.outlineView.selectedRowIndexes;
	for(NSUInteger i = 0; i < self.outlineView.numberOfRows; ++i)
	{
		FileItem* item = [self.outlineView itemAtRow:i];
		if([selectedIndexes containsIndex:i])
				[res addObject:item.URL];
		else	[res removeObject:item.URL];
	}
	return [res copy];
}

- (NSSet<NSURL*>*)expandedURLs
{
	NSMutableSet<NSURL*>* res = [_expandedURLs mutableCopy];
	for(NSUInteger i = 0; i < self.outlineView.numberOfRows; ++i)
	{
		FileItem* item = [self.outlineView itemAtRow:i];
		if([self.outlineView isItemExpanded:item] && ![item.URL.scheme isEqualToString:@"scm"])
				[res addObject:item.URL];
		else	[res removeObject:item.URL];
	}
	return [res copy];
}

// = NSOutlineViewDataSource =
//
// The seven data-source/delegate methods are Swift, in
// FileBrowserOutlineViewDataSource.swift — the first section peeled off ahead
// of the port. The conformance stays on the class extension above; AppKit
// reaches them by selector.

// = Table cell view constructor =
//
// The cell constructor, its two button actions and the rename commit are Swift,
// in FileBrowserTableCells.swift. The buttons' target/action are wired there
// too, so nothing in this file refers to them any more.

// =============
// = QuickLook =
// =============

- (NSArray<FileItem*>*)previewableItems
{
	return [self.selectedItems filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"previewItemURL != nil"]];
}

// ============
// = Services =
// ============

- (id)validRequestorForSendType:(NSString*)sendType returnType:(NSString*)returnType
{
	return returnType == nil && sendType != nil && [@[ NSFilenamesPboardType, NSURLPboardType ] containsObject:sendType] ? self : nil;
}

- (BOOL)writeSelectionToPasteboard:(NSPasteboard*)pboard types:(NSArray*)types
{
	NSArray<NSURL*>* urls = [self.previewableItems valueForKeyPath:@"URL"];
	if(urls.count == 0)
		return NO;

	[pboard clearContents];
	return [pboard writeObjects:urls];
}

// = Accepting Drops =
//
// validateDrop / acceptDrop and the outline view's didTrashURLs: report are
// Swift, in FileBrowserAcceptDrop.swift, along with the operation-mask filter
// that used to be a file-static here.

// =============
// = Undo/Redo =
// =============

- (NSUndoManager*)undoManager
{
	if(!_fileBrowserUndoManager)
		_fileBrowserUndoManager = [[NSUndoManager alloc] init];
	return _fileBrowserUndoManager;
}

- (NSUndoManager*)activeUndoManager
{
	NSResponder* firstResponder = self.view.window.firstResponder;
	if([firstResponder isKindOfClass:[NSView class]] && [(NSView*)firstResponder isDescendantOf:self.view])
			return firstResponder.undoManager;
	else	return self.undoManager;
}

- (void)undo:(id)sender
{
	[self.activeUndoManager undo];
}

- (void)redo:(id)sender
{
	[self.activeUndoManager redo];
}
@end
