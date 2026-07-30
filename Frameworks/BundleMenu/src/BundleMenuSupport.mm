// All that is left of BundleMenu's ObjC++ (Phase 4).
//
// BundleMenu.h's public API is a C++ free function over bundles::item_ptr, and
// its two callers — OakTextView.mm and OakMainMenu.mm — are ObjC++ that stays
// ObjC++. So the signature is kept exactly, and this file is the one place the
// item_ptr <-> TMBundleItem conversion happens. Consumers were not touched.
#import "BundleMenu.h"
#import "BMSwiftClasses.h"
#import <TMBundleModel/TMBundleModelCxx.h>

bundles::item_ptr OakShowMenuForBundleItems (std::vector<bundles::item_ptr> const& items, NSView* view, NSPoint pos)
{
	// -cxxItem is read only after a nil check, never through a nil receiver:
	// objc_msgSend to nil does not produce a valid non-trivial C++ return value.
	TMBundleItem* selected = [BundleMenuPopup showMenuForItems:[TMBundleItem itemsWithCxxItems:items] inView:view atPoint:pos];
	return selected ? selected.cxxItem : bundles::item_ptr();
}
