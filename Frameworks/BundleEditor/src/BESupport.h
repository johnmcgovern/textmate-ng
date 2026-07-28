// The ObjC boundary the BundleEditor Swift code sits on (Phase 4).
//
// Same rule as CWSupport.h / PWSupport.h: everything here exists because Swift
// cannot express it. BundleEditor has more of it than the earlier ports — its
// browser model, its pending-changes map and its property bags are all C++
// (`be::entry_t`, `bundles::item_ptr`, `plist::dictionary_t`), so the boundary
// is a real model layer rather than a handful of free functions. See BEModel.h
// for that part; this header holds the small pieces.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// decode::rot13 — the Bundle Editor obfuscates contact e-mail addresses in the
// stored plist, and the Bundle properties xib binds through a value transformer
// registered under the name "OakRot13Transformer".
NSString* BERot13 (NSString* _Nullable string);

NS_ASSUME_NONNULL_END
