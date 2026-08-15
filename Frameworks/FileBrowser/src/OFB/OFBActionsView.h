// Hand-written ObjC declaration of OFBActionsView, which is implemented in
// OFBActionsView.swift (Phase 4).
//
// The framework's own ObjC++ — FileBrowserView.mm builds one, and
// FileBrowserViewController.mm reaches all six controls by name to set
// targets/actions and the actions-menu delegate — imports this header unchanged.
// It must never reach the Swift bridging header: it declares a class Swift
// defines, and both spellings in the Swift compilation is a redefinition.
//
// Nothing checks this against the Swift at build time; a drift is an
// unrecognized selector at runtime, which is what t_ofb_actions_view.mm guards.
#import <Cocoa/Cocoa.h>

@interface OFBActionsView : NSVisualEffectView
@property (nonatomic) NSButton* createButton;
@property (nonatomic) NSPopUpButton* actionsPopUpButton;
@property (nonatomic) NSButton* reloadButton;
@property (nonatomic) NSButton* searchButton;
@property (nonatomic) NSButton* favoritesButton;
@property (nonatomic) NSButton* scmButton;
@end
