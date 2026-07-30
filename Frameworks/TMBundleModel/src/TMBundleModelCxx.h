// The C++ side of the TMBundleModel boundary.
//
// Exported, but only for ObjC++ shims that still have to speak both languages —
// principally the thin compatibility layer a ported framework keeps so its own
// C++-typed public API (e.g. OakShowMenuForBundleItems) can stay unchanged for
// consumers that are still ObjC++.
//
// This header contains C++ and therefore must NOT be reachable from any Swift
// bridging header. Swift consumers use TMBundleItem.h / TMScopeContext.h, which
// are deliberately C++-free.
#import "TMBundleItem.h"
#import "TMScopeContext.h"
#import <bundles/bundles.h>

NS_ASSUME_NONNULL_BEGIN

@interface TMBundleItem (Cxx)
// nil for a null item_ptr, so the C++ empty-pointer convention maps onto the
// ObjC one at the boundary rather than inside each consumer.
+ (nullable TMBundleItem*)itemWithCxxItem:(bundles::item_ptr const&)item;
+ (NSArray<TMBundleItem*>*)itemsWithCxxItems:(std::vector<bundles::item_ptr> const&)items;

// Read this only on a non-nil receiver. It returns a non-trivial C++ type, and
// objc_msgSend to nil does not produce a valid one — check for nil first rather
// than relying on a zeroed return.
@property (nonatomic, readonly) bundles::item_ptr cxxItem;
@end

std::vector<bundles::item_ptr> TMCxxItemsFromArray (NSArray<TMBundleItem*>* items);

@interface TMScopeContext (Cxx)
+ (TMScopeContext*)scopeContextWithCxxContext:(scope::context_t const&)context;
@property (nonatomic, readonly) scope::context_t cxxContext;
@end

NS_ASSUME_NONNULL_END
