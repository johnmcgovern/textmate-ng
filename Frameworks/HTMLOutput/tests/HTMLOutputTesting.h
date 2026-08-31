// Test-only declarations for HTMLOutput, mirroring OakTextViewTesting.h.
//
// Everything HTMLOutput exposes publicly is a view or a delegate; the behaviour
// worth pinning is one layer below that, in private properties and in four
// file-static functions. This header names both.
#import "../src/browser/HOStatusBar.h"
#import "../src/browser/HOBrowserView.h"
#import "../src/HOLocalURLRewriter.h"
#import <Cocoa/Cocoa.h>

@interface HOStatusBar (Testing)
// Every one of the public properties is a *facade* over one of these subviews —
// the bar has no backing storage of its own — so a test cannot say anything
// about it without them.
@property (nonatomic) NSView*              topDivider;
@property (nonatomic) NSView*              divider;
@property (nonatomic) NSButton*            goBackButton;
@property (nonatomic) NSButton*            goForwardButton;
@property (nonatomic) NSTextField*         statusTextField;
@property (nonatomic) NSProgressIndicator* progressIndicator;
@property (nonatomic) NSProgressIndicator* spinner;

// Which of the two indicators is installed. Not merely internal state: it decides
// which one is a subview and which layout branch -updateConstraints takes.
@property (nonatomic) BOOL indeterminateProgress;
@end

@interface HOBrowserView (Testing)
// The four file-static helpers, reachable — see the note beside their definitions
// in HOBrowserView.mm for why they are class methods rather than extern.
+ (BOOL)isProtocolRelativeURL:(NSURL*)url;
+ (NSURL*)rewrittenURL:(NSURL*)url;
+ (BOOL)isLoadableScheme:(NSURL*)url;
+ (NSString*)escapeHTML:(NSString*)str;
@end
