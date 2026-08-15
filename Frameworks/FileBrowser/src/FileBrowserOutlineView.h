// Hand-written ObjC declaration of FileBrowserOutlineView, which is implemented
// in FileBrowserOutlineView.swift (Phase 4).
//
// FileBrowserView.mm builds one and FileBrowserViewController.mm is its delegate;
// both import this header unchanged. It must never reach the Swift bridging
// header — it declares a class Swift defines. The delegate protocol lives in
// FileBrowserOutlineViewDelegate.h (which the bridging header *does* import) and
// is re-exported here so consumers still get both from this one header.
//
// Nothing checks this against the Swift at build time; a drift is an
// unrecognized selector at runtime, which is what t_file_browser_outline_view.mm
// guards.
#import "FileBrowserOutlineViewDelegate.h"

@interface FileBrowserOutlineView : NSOutlineView
@end
