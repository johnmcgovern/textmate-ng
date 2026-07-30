// An ObjC-shaped model layer over bundles::item_ptr (Phase 4).
//
// The `bundles` framework's public API is C++ free functions over
// std::shared_ptr<bundles::item_t>, which Swift can neither call nor implement.
// That is the single blocker under both BundleMenu (whose entire public API is
// those free functions) and BundleEditor's window controller. This class exists
// so that blocker is solved once rather than per framework.
//
// This header is deliberately free of C++ so it can be imported by a Swift
// bridging header and exported through the include farm unchanged.
//
// SCOPE: only what the consumers actually touch, not all of bundles::item_t.
// There is no field-string lookup, no scope_selector, no does_match, no
// plist round-trip — those arrive when the consumer that needs them does.
#import <Cocoa/Cocoa.h>
#import "TMScopeContext.h"

NS_ASSUME_NONNULL_BEGIN

// Mirrors bundles::kind_t. A bitmask, because the query APIs take a union of
// kinds. The raw values are pinned against the C++ enum by static_assert in
// TMBundleItem.mm — a silent divergence here would mis-route every menu item.
typedef NS_OPTIONS(NSUInteger, TMBundleItemKind) {
	TMBundleItemKindCommand           = 1,
	TMBundleItemKindDragCommand       = 2,
	TMBundleItemKindGrammar           = 4,
	TMBundleItemKindMacro             = 8,
	TMBundleItemKindSettings          = 16,
	TMBundleItemKindSnippet           = 32,
	TMBundleItemKindProxy             = 64,
	TMBundleItemKindTheme             = 128,
	TMBundleItemKindBundle            = 256,
	TMBundleItemKindMenu              = 512,
	TMBundleItemKindMenuItemSeparator = 1024,
	TMBundleItemKindUnknown           = 2048,
};

// NSCopying so an item can be a dictionary key, which is the shape
// BundleEditor's std::map<item_ptr, plist::dictionary_t> pending-edits map
// becomes. Instances are immutable and interned, so -copy returns self.
@interface TMBundleItem : NSObject <NSCopying>

// Instances are interned on the identity of the underlying C++ item, so two
// wrappers of the same bundle item are the same object and -isEqual:/-hash
// behave like std::set<item_ptr>/std::map<item_ptr, …> did. Both consumers rely
// on this: BundleMenu tracks which items it has already emitted, and
// BundleEditor keys its pending-edits map on the item.
- (instancetype)init NS_UNAVAILABLE;

// bundles::lookup. nil when no item carries that UUID — including when
// uuidString is not a UUID at all.
+ (nullable TMBundleItem*)itemWithUUIDString:(nullable NSString*)uuidString;

// bundles::item_t::menu_item_separator(). A process-wide singleton, so
// `TMBundleItem.separatorItem == TMBundleItem.separatorItem`.
@property (class, nonatomic, readonly) TMBundleItem* separatorItem;

// bundles::items_for_proxy — expands a kProxy item into the items it stands for
// in the given scope. Pass nil for the wildcard scope.
+ (NSArray<TMBundleItem*>*)itemsForProxy:(TMBundleItem*)proxyItem scope:(nullable TMScopeContext*)scope;

// Sorted by name using the same case-insensitive collation the ObjC++ menus
// used (text::less_t). Menu order is user-visible, so this is not merely
// -localizedCaseInsensitiveCompare: by another name — it is the existing one.
+ (NSArray<TMBundleItem*>*)itemsSortedByName:(NSArray<TMBundleItem*>*)items;

@property (nonatomic, readonly) TMBundleItemKind kind;

// nil rather than a sentinel: the C++ NULL_STR is converted here, once, so it
// can never reach a caller.
@property (nonatomic, readonly, nullable) NSString* name;
@property (nonatomic, readonly, nullable) NSString* uuidString;
@property (nonatomic, readonly, nullable) NSString* tabTrigger;

// bundles::key_equivalent — not simply the item's own field, it also resolves
// the key equivalent a proxy item lends to its semantic class.
@property (nonatomic, readonly, nullable) NSString* keyEquivalent;

// The tmbundle this item belongs to; nil for an item that is itself a bundle.
@property (nonatomic, readonly, nullable) TMBundleItem* bundle;

// The item's menu children, excluding deleted and disabled items — matching
// item_t::menu()'s default. Empty for anything that is not a bundle or a menu.
@property (nonatomic, readonly) NSArray<TMBundleItem*>* menu;

@end

NS_ASSUME_NONNULL_END
