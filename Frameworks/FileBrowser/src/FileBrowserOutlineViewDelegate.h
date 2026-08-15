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

@protocol FileBrowserOutlineViewDelegate <NSOutlineViewDelegate>
- (void)outlineView:(NSOutlineView*)outlineView willExpandItem:(id)someItem expandChildren:(BOOL)flag;
- (void)outlineView:(NSOutlineView*)outlineView didExpandItem:(id)someItem expandChildren:(BOOL)flag;
- (void)outlineView:(NSOutlineView*)outlineView willCollapseItem:(id)someItem collapseChildren:(BOOL)flag;
- (void)outlineView:(NSOutlineView*)outlineView didCollapseItem:(id)someItem collapseChildren:(BOOL)flag;
- (void)outlineView:(NSOutlineView*)outlineView didTrashURLs:(NSArray<NSURL*>*)someURLs;
@end
