#import "AppController.h"
#import "AppControllerSupport.h"
#import "OakMainMenu.h"
#import "Favorites.h"
#import "RMateServer.h"
#import <BundleEditor/BundleEditor.h>
#import <BundlesManager/BundlesManager.h>
#import <CrashReporter/CrashReporter.h>
#import <DocumentWindow/DocumentWindowController.h>
#import <Find/Find.h>
#import <CommitWindow/CommitWindow.h>
#import <OakAppKit/NSAlert Additions.h>
#import <OakAppKit/NSMenuItem Additions.h>
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakPasteboard.h>
#import <OakFilterList/BundleItemChooser.h>
#import <TMBundleModel/TMBundleModelCxx.h>
#import <OakFoundation/OakFoundation.h>
#import <OakFoundation/NSString Additions.h>
#import <OakTextView/OakDocumentView.h>
#import <Preferences/Keys.h>
#import <Preferences/Preferences.h>
#import <Preferences/TerminalPreferences.h>
#import <SoftwareUpdate/SoftwareUpdate.h>
#import <document/OakDocument.h>
#import <document/OakDocumentController.h>
#import <bundles/query.h>
#import <regexp/glob.h>
#import <ns/ns.h>
#import <oak/debug.h>
#import <oak/oak.h>
#import <scm/scm.h>
#import <text/types.h>
#import "TextMate-Swift.h"

void OakOpenDocuments (NSArray* paths, BOOL treatFilePackageAsFolder)
{
	NSArray* const bundleExtensions = @[ @"tmbundle", @"tmcommand", @"tmdragcommand", @"tmlanguage", @"tmmacro", @"tmpreferences", @"tmsnippet", @"tmtheme" ];

	NSMutableArray<OakDocument*>* documents = [NSMutableArray array];
	NSMutableArray* itemsToInstall = [NSMutableArray array];
	NSMutableArray* plugInsToInstall = [NSMutableArray array];
	BOOL enableInstallHandler = treatFilePackageAsFolder == NO && ([NSEvent modifierFlags] & NSEventModifierFlagOption) == 0;
	for(NSString* path in paths)
	{
		BOOL isDirectory = NO;
		NSString* pathExt = [[path pathExtension] lowercaseString];
		if(enableInstallHandler && [bundleExtensions containsObject:pathExt])
		{
			[itemsToInstall addObject:path];
		}
		else if(enableInstallHandler && [pathExt isEqualToString:@"tmplugin"])
		{
			[plugInsToInstall addObject:path];
		}
		else if([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory)
		{
			[OakDocumentController.sharedInstance showFileBrowserAtPath:path];
		}
		else
		{
			[documents addObject:[OakDocumentController.sharedInstance documentWithPath:path]];
		}
	}

	if([itemsToInstall count])
		[BundlesManager.sharedInstance installBundleItemsAtPaths:itemsToInstall];

	for(NSString* path in plugInsToInstall)
		[TMPlugInController.sharedInstance installPlugInAtPath:path];

	[OakDocumentController.sharedInstance showDocuments:documents];
}

BOOL HasDocumentWindow (NSArray* windows)
{
	for(NSWindow* window in windows)
	{
		if([window.delegate isKindOfClass:[DocumentWindowController class]])
			return YES;
	}
	return NO;
}

@interface AppController () <OakUserDefaultsObserver>
@property (nonatomic) BOOL didFinishLaunching;
@property (nonatomic) BOOL keyWindowHasBackAndForwardActions;
@end

@implementation AppController
- (NSMenu*)mainMenu
{
	// Read the display name from CFBundleName rather than spelling it out here, so
	// the fork’s name lives in exactly one place. Note this is deliberately not
	// ${TARGET_NAME}: the target (and therefore CFBundleExecutable) stays
	// “TextMate”, only the user-visible name is TextMate-NG.
	NSString* const appName = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"] ?: @"TextMate";

	OakMainMenu* menu = [[OakMainMenu alloc] initWithTitle:@"AMainMenu"];
	TMMainMenuRefs* refs = [TMMenus buildMainMenuInto:menu target:self appName:appName];

	// MBCreateMenu wrote these four through `NSMenu* __strong*` out-parameters
	// while it built; the Swift builder hands them back instead. -menuNeedsUpdate:
	// dispatches on their identity, and the delegates are assigned afterwards
	// exactly as before — MBCreateMenuItem sets a submenu's delegate from the
	// item's own `.delegate`, which is nil for all four.
	bundlesMenu    = refs.bundlesMenu;
	themesMenu     = refs.themesMenu;
	spellingMenu   = refs.spellingMenu;
	wrapColumnMenu = refs.wrapColumnMenu;

	bundlesMenu.delegate    = self;
	themesMenu.delegate     = self;
	spellingMenu.delegate   = self;
	wrapColumnMenu.delegate = self;
	return menu;
}

- (NSMenu*)applicationDockMenu:(NSApplication*)anApplication
{
	return [TMMenus dockMenuWithTarget:self];
}

- (void)setKeyWindowHasBackAndForwardActions:(BOOL)flag
{
	if(_keyWindowHasBackAndForwardActions == flag)
		return;
	_keyWindowHasBackAndForwardActions = flag;

	NSMenu* textMenu        = [NSApp.mainMenu itemWithTitle:@"Text"].submenu;
	NSMenu* fileBrowserMenu = [NSApp.mainMenu itemWithTitle:@"File Browser"].submenu;

	auto itemWithAction = ^NSMenuItem*(NSMenu* menu, SEL action){
		NSInteger index = [menu indexOfItemWithTarget:nil andAction:action];
		return index == -1 ? nil : menu.itemArray[index];
	};

	NSMenuItem* backMenuItem       = itemWithAction(fileBrowserMenu, @selector(goBack:));
	NSMenuItem* forwardMenuItem    = itemWithAction(fileBrowserMenu, @selector(goForward:));
	NSMenuItem* shiftLeftMenuItem  = itemWithAction(textMenu,        @selector(shiftLeft:));
	NSMenuItem* shiftRightMenuItem = itemWithAction(textMenu,        @selector(shiftRight:));

	if(!backMenuItem || !forwardMenuItem || !shiftLeftMenuItem || !shiftRightMenuItem)
		return;

	for(NSMenuItem* menuItem in @[ backMenuItem, forwardMenuItem, shiftLeftMenuItem, shiftRightMenuItem ])
		menuItem.keyEquivalent = @"";

	(flag ? backMenuItem : shiftLeftMenuItem).keyEquivalent                 = @"[";
	(flag ? backMenuItem : shiftLeftMenuItem).keyEquivalentModifierMask     = NSEventModifierFlagCommand;
	(flag ? forwardMenuItem : shiftRightMenuItem).keyEquivalent             = @"]";
	(flag ? forwardMenuItem : shiftRightMenuItem).keyEquivalentModifierMask = NSEventModifierFlagCommand;
}

- (void)applicationDidUpdate:(NSNotification*)aNotification
{
	BOOL foundBackAndForwardActions = NO;
	for(NSResponder* responder = NSApp.keyWindow.firstResponder; responder && !foundBackAndForwardActions; responder = responder.nextResponder)
	{
		if([responder respondsToSelector:@selector(shiftLeft:)])
			break;
		else if([responder respondsToSelector:@selector(goBack:)])
			foundBackAndForwardActions = YES;
	}
	self.keyWindowHasBackAndForwardActions = foundBackAndForwardActions;
}

- (void)userDefaultsDidChange:(id)sender
{
	BOOL disableRmate        = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsDisableRMateServerKey];
	NSString* rmateInterface = [NSUserDefaults.standardUserDefaults stringForKey:kUserDefaultsRMateServerListenKey];
	int rmatePort            = [NSUserDefaults.standardUserDefaults integerForKey:kUserDefaultsRMateServerPortKey];
	setup_rmate_server(!disableRmate, rmatePort, [rmateInterface isEqualToString:kRMateServerListenRemote]);
}

- (void)applicationWillFinishLaunching:(NSNotification*)aNotification
{
	// First, because it used to run at nib-load time — see the note on the method.
	[AppController setupThemeDefaultsAndObservers];

	if(NSMenu* menu = [self mainMenu])
		NSApp.mainMenu = menu;

	// SoftwareUpdate.sharedInstance.channels is deliberately left unconfigured
	// (Phase 2.5, 2026-07-26): these previously resolved against MacroMates'
	// api.textmate.org/releases — this fork's own TextMate-NG. "Check for
	// updates" now surfaces a clear "No channel named …" error instead of
	// silently offering the wrong product's releases. Wire this back up once a
	// J23-owned update feed exists; SoftwareUpdate.mm's checkForTestBuild: does
	// the lookup by name against whatever channels dict is set here.

	[AppControllerSupport setupSettingsPaths];

	[NSUserDefaults.standardUserDefaults registerDefaults:@{
		@"NSRecentDocumentsLimit": @25,
		@"WebKitDeveloperExtras":  @YES,
	}];
	RegisterDefaults();

	[TMPlugInController.sharedInstance loadAllPlugIns:nil];

	[AppControllerSupport installDefaultBundlesIfNeeded];
	[BundlesManager.sharedInstance loadBundlesIndex];

	if(BOOL restoreSession = ![NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsDisableSessionRestoreKey])
	{
		NSString* const prematureTerminationDuringRestore = AppControllerSupport.sessionRestoreMarkerPath;

		NSString* promptUser = nil;
		if([AppControllerSupport markerExistsAtPath:prematureTerminationDuringRestore])
			promptUser = @"Previous attempt of restoring your session caused an abnormal exit. Would you like to skip session restore?";
		else if([NSEvent modifierFlags] & NSEventModifierFlagShift)
			promptUser = @"By holding down shift (⇧) you have indicated that you wish to disable restoring the documents which were open in last session.";

		if(promptUser)
		{
			NSAlert* alert        = [[NSAlert alloc] init];
			alert.messageText     = @"Disable Session Restore?";
			alert.informativeText = promptUser;
			[alert addButtons:@"Restore Documents", @"Disable", nil];
			if([alert runModal] == NSAlertSecondButtonReturn) // "Disable"
				restoreSession = NO;
		}

		if(restoreSession)
		{
			[AppControllerSupport createMarkerAtPath:prematureTerminationDuringRestore];
			[DocumentWindowController restoreSession];
		}
		[AppControllerSupport removeMarkerAtPath:prematureTerminationDuringRestore];
	}
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication*)anApplication
{
	return self.didFinishLaunching;
}

- (void)applicationDidFinishLaunching:(NSNotification*)aNotification
{
	NSWindow.allowsAutomaticWindowTabbing = NO;

	NSApp.automaticCustomizeTouchBarMenuItemEnabled = YES;

	if(!HasDocumentWindow([NSApp orderedWindows]))
	{
		BOOL disableUntitledAtStartupPrefs = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsDisableNewDocumentAtStartupKey];
		BOOL showFavoritesInsteadPrefs     = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsShowFavoritesInsteadOfUntitledKey];

		if(showFavoritesInsteadPrefs)
			[self openFavorites:self];
		else if(!disableUntitledAtStartupPrefs)
			[self newDocument:self];
	}

	[self userDefaultsDidChange:nil]; // setup mate/rmate server
	OakObserveUserDefaults(self);

	NSMenu* selectMenu = [[[[[NSApp mainMenu] itemWithTitle:@"Edit"] submenu] itemWithTitle:@"Select"] submenu];
	[[selectMenu itemWithTitle:@"Toggle Column Selection"] setActivationString:@"⌥" withFont:nil];

	[TerminalPreferences updateMateIfRequired];
	[AboutWindowController showChangesIfUpdated];

	[CrashReporter.sharedInstance applicationDidFinishLaunching:aNotification];
	// Uploading is deliberately disabled (Phase 2.5, 2026-07-26): `REST_API` here
	// resolves to MacroMates' api.textmate.org, and this call defaulted to
	// enabled — most users would never see the opt-out checkbox in Preferences
	// before their first crash silently uploaded to a company this fork isn't
	// affiliated with. Re-enable once a J23-owned collector exists, by restoring
	// `[CrashReporter.sharedInstance postNewCrashReportsToURLString:...]` pointed
	// at it. macOS's own system crash reporting is unaffected either way.

	[OakCommitWindowServer sharedInstance]; // Setup server

	// Phase 3 proof-of-life: the first Swift↔ObjC↔C++ round trip, once per
	// launch. Logged rather than shown — it proves the interop toolchain without
	// changing behavior. Remove once real Swift code exists (Phase 4).
	static os_log_t log = os_log_create("com.j23software.TextMate-NG", "swift-interop");
	os_log(log, "%{public}@", [TMSwiftInterop interopDescription]);

	self.didFinishLaunching = YES;
}

- (void)applicationWillResignActive:(NSNotification*)aNotification
{
	scm::disable();
}

- (void)applicationWillBecomeActive:(NSNotification*)aNotification
{
	scm::enable();
}

- (void)applicationDidResignActive:(NSNotification*)aNotification
{
	// If the window to activate, when switching back to TextMate, has “Move to
	// Active Space” set, then the system will move this window to the current
	// space. This is not what we want for auxillary windows like the Find dialog
	// or HTML output, as these windows are tied to a document window.
	//
	// Starting with macOS 10.11 we have to change collection behavior after the
	// current event loop cycle, both when receiving the did become and did resign
	// active notification.

	dispatch_async(dispatch_get_main_queue(), ^{
		NSMutableArray* changedWindows = [NSMutableArray array];
		for(NSWindow* window in NSApp.windows)
		{
			if((window.collectionBehavior & (NSWindowCollectionBehaviorMoveToActiveSpace|NSWindowCollectionBehaviorFullScreenAuxiliary)) == (NSWindowCollectionBehaviorMoveToActiveSpace|NSWindowCollectionBehaviorFullScreenAuxiliary))
			{
				window.collectionBehavior &= ~NSWindowCollectionBehaviorMoveToActiveSpace;
				[changedWindows addObject:window];
			}
		}

		if(changedWindows.count)
		{
			__weak __block id token = [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidBecomeActiveNotification object:NSApp queue:nil usingBlock:^(NSNotification*){
				[NSNotificationCenter.defaultCenter removeObserver:token];
				dispatch_async(dispatch_get_main_queue(), ^{
					for(NSWindow* window in changedWindows)
						window.collectionBehavior |= NSWindowCollectionBehaviorMoveToActiveSpace;
				});
			}];
		}
	});
}

// =========================
// = Past Startup Delegate =
// =========================

- (IBAction)newDocumentAndActivate:(id)sender
{
	[NSApp activateIgnoringOtherApps:YES];
	[self newDocument:sender];
}

- (IBAction)openDocumentAndActivate:(id)sender
{
	[NSApp activateIgnoringOtherApps:YES];
	[self openDocument:sender];
}

- (IBAction)orderFrontAboutPanel:(id)sender
{
	[AboutWindowController.sharedInstance showAboutWindow:self];
}

- (IBAction)orderFrontFindPanel:(id)sender
{
	Find* find = Find.sharedInstance;
	NSInteger mode = [sender respondsToSelector:@selector(tag)] ? [sender tag] : FFSearchTargetDocument;
	switch(mode)
	{
		case FFSearchTargetDocument:  find.searchTarget = FFSearchTargetDocument;  break;
		case FFSearchTargetSelection: find.searchTarget = FFSearchTargetSelection; break;
		case FFSearchTargetProject:   find.searchTarget = FFSearchTargetProject;   break;
		case FFSearchTargetOther:     return [find showFolderSelectionPanel:self]; break;
	}
	[find showWindow:self];
}

- (IBAction)orderFrontGoToLinePanel:(id)sender;
{
	if(id textView = [NSApp targetForAction:@selector(selectionString)])
		[goToLineTextField setStringValue:[textView selectionString]];
	[goToLinePanel makeKeyAndOrderFront:self];
}

- (IBAction)performGoToLine:(id)sender
{
	[goToLinePanel orderOut:self];
	[NSApp sendAction:@selector(selectAndCenter:) to:nil from:[goToLineTextField stringValue]];
}

- (IBAction)performSoftwareUpdateCheck:(id)sender
{
	[SoftwareUpdate.sharedInstance checkForUpdate:self];
}

- (IBAction)showPreferences:(id)sender
{
	[Preferences.sharedInstance showWindow:self];
}

- (IBAction)showBundleEditor:(id)sender
{
	[BundleEditor.sharedInstance showWindow:self];
}

- (IBAction)openFavorites:(id)sender
{
	FavoriteChooser* chooser = FavoriteChooser.sharedInstance;
	chooser.action = @selector(didSelectFavorite:);
	[chooser showWindow:self];
}

- (void)didSelectFavorite:(id)sender
{
	NSMutableArray* paths = [NSMutableArray array];
	for(id item in [sender selectedItems])
		[paths addObject:[item valueForKey:@"path"]];
	OakOpenDocuments(paths, YES);
}

// =======================
// = Bundle Item Chooser =
// =======================

- (IBAction)showBundleItemChooser:(id)sender
{
	BundleItemChooser* chooser = BundleItemChooser.sharedInstance;
	chooser.action     = @selector(bundleItemChooserDidSelectItems:);
	chooser.editAction = @selector(editBundleItem:);

	OakTextView* textView = [NSApp targetForAction:@selector(scopeContext)];
	chooser.scope        = textView ? [TMScopeContext scopeContextWithCxxContext:[textView scopeContext]] : TMScopeContext.wildcardScope;
	chooser.hasSelection = [textView hasSelection];

	if(DocumentWindowController* controller = [NSApp targetForAction:@selector(selectedDocument)])
	{
		OakDocument* doc = controller.selectedDocument;
		chooser.path      = doc.path;
		chooser.directory = [doc.path stringByDeletingLastPathComponent] ?: doc.directory;
	}
	else
	{
		chooser.path      = nil;
		chooser.directory = nil;
	}

	[chooser showWindowRelativeToFrame:textView.window ? [textView.window convertRectToScreen:[textView convertRect:[textView visibleRect] toView:nil]] : [[NSScreen mainScreen] visibleFrame]];
}

- (void)bundleItemChooserDidSelectItems:(id)sender
{
	for(id item in [sender selectedItems])
		[NSApp sendAction:@selector(performBundleItemWithUUIDStringFrom:) to:nil from:@{ @"representedObject": [item valueForKey:@"uuid"] }];
}

// ===========================
// = Find options menu items =
// ===========================

- (IBAction)toggleFindOption:(id)sender
{
	[Find.sharedInstance takeFindOptionToToggleFrom:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem*)item
{
	BOOL enabled = YES;
	if([item action] == @selector(toggleFindOption:))
	{
		BOOL active = NO;
		if(OakPasteboardEntry* entry = [OakPasteboard.findPasteboard current])
		{
			switch([item tag])
			{
				case find::ignore_case:        active = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsFindIgnoreCase]; break;
				case find::regular_expression: active = [entry regularExpression]; break;
				case find::full_words:         active = [entry fullWordMatch];     enabled = ![entry regularExpression]; break;
				case find::ignore_whitespace:  active = [entry ignoreWhitespace];  enabled = ![entry regularExpression]; break;
				case find::wrap_around:        active = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsFindWrapAround]; break;
			}
			[item setState:(active ? NSControlStateValueOn : NSControlStateValueOff)];
		}
		else
		{
			enabled = NO;
		}
	}
	else if([item action] == @selector(orderFrontGoToLinePanel:))
	{
		enabled = [NSApp targetForAction:@selector(setSelectionString:)] != nil;
	}
	else if([item action] == @selector(performBundleItemWithUUIDStringFrom:))
	{
		id menuItemValidator = [NSApp.keyWindow.delegate respondsToSelector:@selector(performBundleItem:)] ? NSApp.keyWindow.delegate : [NSApp targetForAction:@selector(performBundleItem:)];
		if(menuItemValidator != self && [menuItemValidator respondsToSelector:@selector(validateMenuItem:)])
			enabled = [menuItemValidator validateMenuItem:item];
	}
	else
	{
		enabled = [self validateThemeMenuItem:item];
	}
	return enabled;
}

- (void)editBundleItem:(id)sender
{
	ASSERT([sender respondsToSelector:@selector(selectedItems)]);
	ASSERT([[sender selectedItems] count] == 1);

	if(NSString* uuid = [[[sender selectedItems] lastObject] valueForKey:@"uuid"])
	{
		[BundleEditor.sharedInstance revealBundleItem:bundles::lookup(to_s(uuid))];
	}
	else if(NSString* path = [[[sender selectedItems] lastObject] valueForKey:@"file"])
	{
		OakDocument* doc = [OakDocumentController.sharedInstance documentWithPath:path];
		NSString* line = [[[sender selectedItems] lastObject] valueForKey:@"line"];
		[OakDocumentController.sharedInstance showDocument:doc andSelect:(line ? text::pos_t(to_s(line)) : text::pos_t::undefined) inProject:nil bringToFront:YES];
	}
}

- (void)editBundleItemWithUUIDString:(NSString*)uuidString
{
	[BundleEditor.sharedInstance revealBundleItem:bundles::lookup(to_s(uuidString))];
}

// ============
// = Printing =
// ============

- (IBAction)runPageLayout:(id)sender
{
	[[NSPageLayout pageLayout] runModal];
}
@end
