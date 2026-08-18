// The outline view's extra delegate callbacks, split out of FileBrowserOutlineView.h
// so the Swift side can see the protocol without also seeing the class it
// defines (rule 11 — the Find.h → FindTypes.h split). The bridging header
// imports this; FileBrowserOutlineView.h re-imports it, so ObjC++ consumers get
// both the protocol and the class from the one header as before.
//
// These are the expand/collapse hooks (the outline view fires them around
// -expandItem:/-collapseItem: so the controller can bracket its own animation)
// and the trash notification after a drag to the Dock's Trash. Pure ObjC — no
// C++ — which is what lets it reach the Swift bridging header.
#import <Cocoa/Cocoa.h>

// **Annotated, and that is load-bearing rather than tidiness.** Without these
// every parameter imports as an optional — including `NSOutlineView?`, which no
// caller can produce — and a Swift class adopting this protocol then has to
// spell its witnesses `(NSOutlineView?, Any?, Bool)` to match. Annotating the
// header instead is rule 44's advice applied to a protocol: fix the declaration
// once rather than cope at every conformance.
//
// `someItem` is the one genuinely nullable parameter: NSOutlineView uses nil for
// the root, and -expandItem:/-collapseItem: pass whatever they were given
// straight through.
NS_ASSUME_NONNULL_BEGIN

@protocol FileBrowserOutlineViewDelegate <NSOutlineViewDelegate>
- (void)outlineView:(NSOutlineView*)outlineView willExpandItem:(nullable id)someItem expandChildren:(BOOL)flag;
- (void)outlineView:(NSOutlineView*)outlineView didExpandItem:(nullable id)someItem expandChildren:(BOOL)flag;
- (void)outlineView:(NSOutlineView*)outlineView willCollapseItem:(nullable id)someItem collapseChildren:(BOOL)flag;
- (void)outlineView:(NSOutlineView*)outlineView didCollapseItem:(nullable id)someItem collapseChildren:(BOOL)flag;
- (void)outlineView:(NSOutlineView*)outlineView didTrashURLs:(NSArray<NSURL*>*)someURLs;
@end

NS_ASSUME_NONNULL_END
