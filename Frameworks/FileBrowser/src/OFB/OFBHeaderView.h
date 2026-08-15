// Hand-written ObjC declaration of OFBHeaderView, which is implemented in
// OFBHeaderView.swift (Phase 4).
//
// The framework's own ObjC++ — FileBrowserView.mm builds one, and
// FileBrowserViewController.mm reads its three controls by name to set
// targets/actions and bind enabled state — imports this header unchanged. It
// must never reach the Swift bridging header: it declares a class Swift defines,
// and both spellings in the Swift compilation is a redefinition.
//
// Nothing checks this against the Swift at build time; a drift is an
// unrecognized selector at runtime, which is what t_ofb_header_view.mm guards.
#import <Cocoa/Cocoa.h>

@interface OFBHeaderView : NSVisualEffectView
@property (nonatomic) NSPopUpButton* folderPopUpButton;
@property (nonatomic) NSButton* goBackButton;
@property (nonatomic) NSButton* goForwardButton;
@end
