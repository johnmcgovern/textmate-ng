// The Bundle Editor's NSBrowser model, ObjC-shaped (Phase 4).
//
// `be::entry_t` is a small polymorphic C++ hierarchy — a bundle expands into
// "Menu Actions"/"Other Actions"/"Language Grammars"/…, a Support directory
// expands into real files, a menu expands into its items — with children
// computed lazily on first access. Swift cannot subclass it, but it does not
// need to: every subclass exists only to override one protected `entries()`,
// and the interface a browser drives it through is entirely ObjC-expressible.
//
// So this wraps the *interface* and leaves the hierarchy alone. It deliberately
// lives in BundleEditor rather than TMBundleModel: the tree is this one
// window's browser model, not part of the bundle-item model.
//
// This header is free of C++ so the Swift bridging header can import it.
#import <Cocoa/Cocoa.h>
#import <TMBundleModel/TMBundleItem.h>

NS_ASSUME_NONNULL_BEGIN

@interface BEEntry : NSObject

- (instancetype)init NS_UNAVAILABLE;

// The tree root — the list of installed bundles. Rebuilt from the current index
// on every call, which is what the Bundle Editor does when bundles change.
@property (class, nonatomic, readonly) BEEntry* bundlesRoot;

// What the browser cell displays. Falls back through the entry's own name, its
// path's display name, and finally the represented item's name.
@property (nonatomic, readonly, nullable) NSString* name;

// The bundle item this row stands for, if any. Group rows ("Settings",
// "Support") and directory rows have none.
@property (nonatomic, readonly, nullable) TMBundleItem* representedItem;

// The file this row stands for, for rows under a bundle's Support directory.
@property (nonatomic, readonly, nullable) NSString* representedPath;

// Drawn dimmed. Note a separator counts as disabled even though no user
// disabled it — that is be::entry_t's rule, preserved.
@property (nonatomic, readonly, getter=isDisabled) BOOL disabled;

// ⚠️ This means "is not a leaf", NOT "has at least one child" — an entry can
// answer YES and still return an empty `children`. be::entry_t distinguishes
// the two by a sentinel: the base entries() returns a one-null-element vector
// meaning "leaf", so a subclass returning a genuinely empty vector is
// expandable-but-empty. The Support row of a bundle that has no Support
// directory is exactly that, and NSBrowser is driven straight off this to set
// a cell's leaf flag — so collapsing it to `children.count > 0` would silently
// change which rows show a disclosure triangle.
//
// Computing it populates the children, so it is not free the first time; the
// C++ caches the result for the entry's lifetime.
@property (nonatomic, readonly) BOOL hasChildren;
@property (nonatomic, readonly) NSArray<BEEntry*>* children;

// Stable across a rebuild of the tree, which is how the Bundle Editor restores
// the browser's selection after the bundle index changes. NOT the same as
// -name: a menu entry identifies by name, an item entry by UUID, a file by
// path.
@property (nonatomic, readonly, nullable) NSString* identifier;

@end

NS_ASSUME_NONNULL_END
