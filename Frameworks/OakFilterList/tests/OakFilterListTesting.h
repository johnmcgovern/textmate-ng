// The internal surface of OakFilterList's choosers that the tests drive.
//
// In its own header for the reason OakAppKitTesting.h and FindTesting.h are:
// ide/gen_xctest.rb wraps each test file's body in `namespace <basename>`, and an ObjC
// declaration may only appear at global scope — but every `#import` is hoisted, so a
// declaration reached through one is fine.
//
// Both members below exist today in BundleItemChooser's implementation, called by its own
// Select/Edit buttons and by -validateMenuItem:. Declaring them pins the spelling a Swift
// port has to keep reachable from ObjC, and gives them their real BOOL return rather than
// the `id` the compiler infers for an undeclared selector.
#import "../src/BundleItemChooser.h"
#import "../src/Favorites.h"
#import "../src/FavoritesSupport.h"

@interface BundleItemChooser (Testing)
- (BOOL)canAccept;
- (BOOL)canEdit;
@end

// FavoriteChooser's two source-list members, declared in its class extension.
// Moved here with the class on 2026-09-15 (it lived in the app until then).
@interface FavoriteChooser (Testing)
@property (nonatomic) NSArray* sourceListLabels;
@property (nonatomic) NSUInteger sourceIndex;
@end
