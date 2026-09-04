// The C++ half of BundleEditor's public surface.
//
// Exported, but only for ObjC++ consumers that still speak both languages —
// DocumentWindowSupport.mm and, until it flips, AppController.mm. Swift
// consumers use BundleEditor.h, which is C++-free.
//
// This header contains C++ and therefore must NOT be reachable from any Swift
// bridging header. Same arrangement as TMBundleModelCxx.h next to TMBundleItem.h.
#import "BundleEditor.h"
#import <bundles/bundles.h>

@interface BundleEditor (BECxxInterop)
// Implemented in BEInterop.mm, which converts the item and calls -revealItem:.
// Kept because two other targets call it with a bundles::item_ptr they already
// have, and neither is Swift yet.
- (void)revealBundleItem:(bundles::item_ptr const&)anItem;
@end
