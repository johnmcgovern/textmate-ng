// Hand-written ObjC declaration of FileBrowserView, which is implemented in
// FileBrowserView.swift (Phase 4).
//
// FileBrowserViewController.mm creates one as its `view` and reads all three
// child views by name; it imports this header unchanged. It must never reach the
// Swift bridging header — it declares a class Swift defines, and both spellings
// in the Swift compilation is a redefinition.
//
// Nothing checks this against the Swift at build time; a drift is an
// unrecognized selector at runtime, which is what t_file_browser_view.mm guards.
#include <oak/misc.h>

@class OFBHeaderView;
@class OFBActionsView;

@interface FileBrowserView : NSView
@property (nonatomic) OFBHeaderView*  headerView;
@property (nonatomic) NSOutlineView*  outlineView;
@property (nonatomic) OFBActionsView* actionsView;
@end
