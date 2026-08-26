// Split out of OTVStatusBar.h so Swift can see it.
//
// OTVStatusBar.h is now a hand declaration of a Swift class (rule 23) and so must
// stay out of this framework's bridging header (rule 43) — but the Swift class
// declares `delegate` with this protocol's type, so the protocol itself has to be
// somewhere the bridging header *can* import. That is here. OTVStatusBar.h
// imports it too, so an ObjC++ consumer still gets both from the one header.
#import <Cocoa/Cocoa.h>

@protocol OTVStatusBarDelegate <NSObject>
- (void)showBundleItemSelector:(NSPopUpButton*)popUpButton;
- (void)showSymbolSelector:(NSPopUpButton*)popUpButton;
@end
