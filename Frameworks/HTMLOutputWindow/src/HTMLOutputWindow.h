#import <HTMLOutput/HTMLOutput.h>

// Implemented in Swift (@objc(HTMLOutputWindowController), see
// HTMLOutputWindow.swift). This header is hand-written and stays the public ObjC
// surface — the same pattern as Preferences.h — because the generated *-Swift.h
// cannot be exported through the include farm. Keep it in step by hand.
@interface HTMLOutputWindowController : NSWindowController
@property (nonatomic) OakHTMLOutputView* htmlOutputView;
- (instancetype)initWithIdentifier:(NSUUID*)anIdentifier;
@end
