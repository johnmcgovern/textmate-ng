// The one selector that cannot follow BundlesManager into Swift.
//
// Rule 37: -findBundleForInstall: answers through a `bundles::item_ptr*`, and
// both of its callers — OakTextView's scratch-macro save and
// InstallBundleItems — take that item_ptr and go on using it as C++. There is
// nothing to extract; the selector keeps an ObjC++ home as a category on the
// class, the OakHTMLOutputViewCxx shape. It holds no state, so a category is
// enough. This header is not in the bridging header, and BundlesManager.h no
// longer imports <bundles/item.h>, which is what lets four bridging headers
// import it cleanly.
#import "BundlesManager.h"
#import <bundles/item.h>

@interface BundlesManager (Cxx)
- (BOOL)findBundleForInstall:(bundles::item_ptr*)res;
@end
