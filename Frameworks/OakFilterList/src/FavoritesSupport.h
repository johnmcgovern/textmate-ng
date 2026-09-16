// Extracted from Favorites.mm ahead of porting FavoriteChooser to Swift.
// Everything that class does which touches C++ lives here, behind an API with
// none in it — the same shape as OakFilterList's SymbolChooserSupport, and for
// the same two reasons:
//
//   - the Favorites folder walk, which is path::entries over dirent plus
//     oak::application_t::support and path::resolve/join/name;
//   - the filter ranking (oak::rank into a std::multimap) and
//     CreateAttributedStringWithMarkedUpRanges over the ranges it produces
//     (rule 19 — Swift can call a free function but never export one).
//
// FavoritesItem stays an ObjC class rather than becoming a Swift struct for the
// reason SymbolChooserItem does: it is what the table view binds to, and the row
// builder asks it for values by key.
//
// The *recent projects* half of -loadItems: did not move. It is KVDB, sort
// descriptors and access(2) — ObjC and C, all of which Swift reaches directly.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface FavoritesItem : NSObject
- (instancetype)initWithPath:(NSString*)path isLink:(BOOL)isLink isRemovable:(BOOL)isRemovable;

@property (nonatomic, readonly) NSImage* icon;
@property (nonatomic, nullable) NSAttributedString* name;
@property (nonatomic, nullable) NSAttributedString* folder;
@property (nonatomic, getter = isRemovable) BOOL removable;

@property (nonatomic, readonly, nullable) NSString* path; // Path of the recent project
@property (nonatomic, readonly, nullable) NSString* link; // Path of symbolic link in Favorites folder (nullable)

@property (nonatomic, readonly, nullable) NSString* displayName;
@property (nonatomic, nullable) NSString* displayNameSuffix;
@end

@interface FavoritesSupport : NSObject

// Everything in the user's Favorites folder, sorted by display name.
//
// A symlink named "[DIR] Foo" is a *folder of projects*: its children are listed
// individually and are not removable, because removing one would mean editing
// somebody's directory rather than deleting a shortcut. Each gets " — Foo" after
// its name, but only when the symlink was renamed away from what it points at —
// otherwise the suffix would repeat the folder's own name.
+ (NSArray<FavoritesItem*>*)favoritesFolderItems;

// The items to show, best first, with `name` and `folder` marked up for the
// filter. An empty filter keeps the input order and marks up nothing.
//
// `bindings` are the paths this abbreviation has been used for before; a match
// among them outranks any score, most-recent first.
+ (NSArray<FavoritesItem*>*)rankItems:(NSArray<FavoritesItem*>*)items filterString:(nullable NSString*)filterString bindings:(NSArray<NSString*>*)bindings;

@end

NS_ASSUME_NONNULL_END
