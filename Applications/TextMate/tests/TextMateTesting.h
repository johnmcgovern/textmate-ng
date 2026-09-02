// Test-only declarations for the application shell, mirroring the frameworks'
// *Testing.h files.
//
// This is the first of them, and it only exists because ide/seed_xcodeproj.rb now
// compiles an application's own sources into its test bundle (73f8318e). Before
// that no class declared under Applications/ was reachable from a test at all.
#import "../src/AboutWindowController.h"
#import "../src/AppController.h"
#import "../src/AppControllerSupport.h"
#import "../src/TxMtURLSupport.h"
#import "../src/Favorites.h"
#import "../src/FavoritesSupport.h"
#import "../src/TMPlugInController.h"
#import <Cocoa/Cocoa.h>

@interface AboutWindowController (Testing)
// All declared in the .mm's class extension. The window's whole behaviour is
// which page is showing, and these are what says so.
@property (nonatomic, readonly) NSArray<NSString*>* segmentLabels;
@property (nonatomic) NSSegmentedControl* segmentedControl;
@property (nonatomic) NSString* selectedPage;

- (void)takeSelectedSegmentFrom:(id)sender;
- (void)selectPageAtRelativeOffset:(NSInteger)offset;
- (void)selectNextTab:(id)sender;
- (void)selectPreviousTab:(id)sender;
- (void)updateShowTabMenu:(NSMenu*)aMenu;
- (NSArray*)toolbarDefaultItemIdentifiers:(NSToolbar*)aToolbar;
- (NSArray*)toolbarAllowedItemIdentifiers:(NSToolbar*)aToolbar;
@end

@interface FavoriteChooser (Testing)
@property (nonatomic) NSArray* sourceListLabels;
@property (nonatomic) NSUInteger sourceIndex;
@end

@interface TMPlugInController (Testing)
// -loadPlugInAtPath: is the whole decision — blacklist, API version, already
// loaded — and it is declared only in the .mm. loadedPlugIns is what it decides
// about.
// Get-only, matching the Swift: the tests seed the dictionary through it, they
// never replace it.
@property (nonatomic, readonly) NSMutableDictionary* loadedPlugIns;
- (void)loadPlugInAtPath:(NSString*)aPath;
@end

@interface AppController (Testing)
// Declared only in the .mm. -mainMenu is the whole menu bar; the four NSMenu
// ivars are what -menuNeedsUpdate: dispatches on, and MBCreateMenu writes them
// through `.submenuRef` while building.
- (NSMenu*)mainMenu;
- (NSMenu*)applicationDockMenu:(NSApplication*)anApplication;
- (BOOL)validateMenuItem:(NSMenuItem*)item;
@end

// Hand declarations for the two Swift classes in MainMenu.swift, rather than
// importing the generated TextMate-Swift.h: this header already declares
// AboutWindowController, FavoriteChooser and TMPlugInController by hand, and
// importing the generated header alongside them gives every one of those two
// interfaces (rule 43). AppController.mm reaches them through TextMate-Swift.h
// in its own translation unit, which is unaffected.
@interface TMMainMenuRefs : NSObject
@property (nonatomic, readonly) NSMenu* bundlesMenu;
@property (nonatomic, readonly) NSMenu* themesMenu;
@property (nonatomic, readonly) NSMenu* spellingMenu;
@property (nonatomic, readonly) NSMenu* wrapColumnMenu;
@end

@interface TMThemeMenuRefs : NSObject
@property (nonatomic, readonly) NSMenu* lightMenu;
@property (nonatomic, readonly) NSMenu* darkMenu;
@end

@interface TMMenus : NSObject
+ (TMMainMenuRefs*)buildMainMenuInto:(NSMenu*)existingMenu target:(id)target appName:(NSString*)appName;
+ (TMThemeMenuRefs*)buildThemeMenuInto:(NSMenu*)existingMenu target:(id)target;
+ (NSMenu*)dockMenuWithTarget:(id)target;
@end
