// Test-only declarations for the application shell, mirroring the frameworks'
// *Testing.h files.
//
// This is the first of them, and it only exists because ide/seed_xcodeproj.rb now
// compiles an application's own sources into its test bundle (73f8318e). Before
// that no class declared under Applications/ was reachable from a test at all.
#import "../src/AboutWindowController.h"
#import "../src/Favorites.h"
#import "../src/FavoritesSupport.h"
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
