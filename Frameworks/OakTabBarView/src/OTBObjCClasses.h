// Declarations the Swift half of this framework needs for classes that are
// still ObjC++ (OakTabView and OakTabBarView, both in OakTabBarView.mm).
//
// Why not import OakTabBarView.h? The Swift module and the ObjC class share the
// name OakTabBarView, so the generated *-Swift.h emits `namespace
// OakTabBarView` and clang rejects it as "redefinition of 'OakTabBarView' as a
// different kind of symbol". Same rule and workaround as BundleEditor's
// BESwiftClasses.h.
//
// OakTabView needs a real @interface, not a @class forward declaration: Swift
// refuses to type a property with a forward-declared ObjC class ("has only been
// forward-declared; import its owning module"). Only the inheritance is
// declared — Swift holds it purely as an opaque back-reference from OakTabItem.
// The full declaration lives in OakTabBarView.mm, which does not import this
// header; if the two are ever pulled into one translation unit the duplicate is
// a hard build error, not a silent divergence.
#import <Cocoa/Cocoa.h>

@interface OakTabView : NSView
@end
