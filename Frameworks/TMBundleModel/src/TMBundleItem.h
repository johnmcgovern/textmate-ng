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
// Still deliberately absent: scope_selector, does_match, bundle_variables,
// set_parent_menu, add_path. They arrive with the consumer that needs them.
#import <Cocoa/Cocoa.h>
#import "TMScopeContext.h"

NS_ASSUME_NONNULL_BEGIN

// Mirrors bundles::kind_t. NS_ENUM and not NS_OPTIONS even though the C++ values
// are powers of two: the bitmask exists so the *query* APIs can take a union of
// kinds, and none of those are exposed here — an item's -kind is always exactly
// one of these, and an enum is what lets Swift switch over it exhaustively.
//
// The raw values are pinned against the C++ enum by static_assert in
// TMBundleItem.mm — a silent divergence here would mis-route every menu item.
typedef NS_ENUM(NSUInteger, TMBundleItemKind) {
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
//
// NS_SWIFT_NAME because an ObjC class method whose name echoes its class is
// otherwise imported as an initializer, and a failable init reads as "make one
// of these" rather than "find the one with this UUID".
+ (nullable TMBundleItem*)itemWithUUIDString:(nullable NSString*)uuidString NS_SWIFT_NAME(item(uuidString:));

// bundles::item_t::menu_item_separator(). A process-wide singleton, so
// `TMBundleItem.menuItemSeparator == TMBundleItem.menuItemSeparator`.
@property (class, nonatomic, readonly) TMBundleItem* menuItemSeparator;

// bundles::items_for_proxy — expands a kProxy item into the items it stands for
// in the given scope. Pass nil for the wildcard scope.
+ (NSArray<TMBundleItem*>*)itemsForProxy:(TMBundleItem*)proxyItem scope:(nullable TMScopeContext*)scope NS_SWIFT_NAME(items(forProxy:scope:));

// Sorted by name using the same case-insensitive collation the ObjC++ menus
// used (text::less_t). Menu order is user-visible, so this is not merely
// -localizedCaseInsensitiveCompare: by another name — it is the existing one.
+ (NSArray<TMBundleItem*>*)itemsSortedByName:(NSArray<TMBundleItem*>*)items NS_SWIFT_NAME(sortedByName(_:));

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

// "Name — Bundle", the Bundle Editor's window title.
@property (nonatomic, readonly, nullable) NSString* nameWithBundle;

// Every file this item is stored in. Usually one; a non-local item that has been
// overridden locally has more, which is why the Bundle Editor offers a path menu
// rather than a single represented URL.
@property (nonatomic, readonly) NSArray<NSString*>* paths;

// The bundle's Support directory. nil when it has none.
@property (nonatomic, readonly, nullable) NSString* supportPath;

@property (nonatomic, readonly, getter=isDisabled) BOOL disabled;
@property (nonatomic, readonly, getter=isHiddenFromUser) BOOL hiddenFromUser;

// MARK: - Property bag
//
// item_t's plist as a Foundation object graph. This is the shape an editor
// wants: the Bundle Editor binds its property xibs straight to a mutable copy
// of `properties` and writes the result back, so no per-field accessor is
// needed and nothing has to know the plist variant type.

// Reading gives the stored plist; assigning replaces it. Assigning does NOT
// write to disk — call -save for that.
@property (nonatomic, copy) NSDictionary* properties;

// Multi-valued fields (a grammar's file extensions, a drag command's drop
// extensions) — item_t stores these flattened, so they are not reachable
// through `properties`.
- (NSArray<NSString*>*)valuesForField:(NSString*)field;

// plist::equal against the item's *stored* plist. The Bundle Editor uses this to
// decide whether an edit is still pending, so it must compare values and not
// object identity — and it cannot be -[NSDictionary isEqual:], because the round
// trip through plist::any_t does not preserve every Foundation class.
- (BOOL)storedPropertiesEqual:(NSDictionary*)properties;

// MARK: - Persistence and the index

- (BOOL)save;
- (BOOL)saveToDirectory:(NSString*)directory;
- (BOOL)moveToTrash;

// Creates an item and adds it to the running index. `bundle` is nil only when
// creating a bundle itself.
+ (TMBundleItem*)createItemOfKind:(TMBundleItemKind)kind inBundle:(nullable TMBundleItem*)bundle properties:(NSDictionary*)properties;

// bundles::remove_item. Does not touch the file — -moveToTrash does that.
- (void)removeFromIndex;

// bundles::query restricted to one bundle, including disabled and hidden items,
// with proxies left unresolved — the Bundle Editor lists what is *there*, not
// what would apply in some scope. Pass nil for every bundle.
+ (NSArray<TMBundleItem*>*)itemsInBundle:(nullable TMBundleItem*)bundle ofKinds:(TMBundleItemKind)kinds NS_SWIFT_NAME(items(inBundle:ofKinds:));

@end

// Posted on the main thread after the bundle index changes.
//
// This is the wrapper's answer to bundles::callback_t, which is a C++ struct
// with virtual methods that Swift cannot subclass. One process-wide subscriber
// is registered in +load and re-broadcasts as a notification, so consumers need
// no C++ at all — and get the ordering guarantee for free, which is the same
// reason BundleEditor registers its reveal observer in +load rather than lazily.
extern NSNotificationName const TMBundleItemsDidChangeNotification;

NS_ASSUME_NONNULL_END
