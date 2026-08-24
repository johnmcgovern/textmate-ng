// Hand-declared (rule 23): OakChoiceMenu is defined in OakChoiceMenu.swift.
//
// The declaration below is unchanged; the five `extern NSUInteger const` that
// used to sit above it moved to OakChoiceMenuConstants.h, which Swift *can*
// import (it just cannot export them). Imported by OakTextView.mm, and kept out
// of this framework's bridging header (rule 43).
#import "OakChoiceMenuConstants.h"

@interface OakChoiceMenu : NSWindowController
@property (nonatomic) NSArray* choices;
@property (nonatomic) NSUInteger choiceIndex;
@property (nonatomic, readonly) NSString* selectedChoice;
@property (nonatomic) NSFont* font;
- (void)showAtTopLeftPoint:(NSPoint)aPoint forView:(NSView*)aView;
- (BOOL)isVisible;
- (NSUInteger)didHandleKeyEvent:(NSEvent*)anEvent;
@end
