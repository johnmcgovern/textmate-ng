// ObjC declarations of BundleMenu's Swift classes, for the ObjC++ inside this
// framework (Phase 4).
//
// The framework cannot import its own generated BundleMenu-Swift.h: under
// SWIFT_OBJC_INTEROP_MODE=objcxx that header emits `namespace BundleMenu { … }`
// and clang rejects it against the module of the same name — the collision first
// recorded for BundleEditor. So the ObjC++ side gets a hand-written declaration
// instead, and NOTHING checks it against the Swift at build time: a drift here
// is an unrecognized selector at runtime, not a compile error. That is what
// BundleMenu's tests are for.
#import <Cocoa/Cocoa.h>
#import <TMBundleModel/TMBundleItem.h>

NS_ASSUME_NONNULL_BEGIN

@interface BundleMenuPopup : NSObject
+ (nullable TMBundleItem*)showMenuForItems:(NSArray<TMBundleItem*>*)items inView:(nullable NSView*)view atPoint:(NSPoint)point;
@end

@interface BundleMenuBuilder : NSObject
+ (void)addItems:(NSArray<TMBundleItem*>*)items toMenu:(NSMenu*)menu setKeys:(BOOL)setKeys;
@end

NS_ASSUME_NONNULL_END
