// The surface of EncodingWindowController that the tests drive but its one
// consumer, OakDocument, does not need.
//
// In its own header because ide/gen_xctest.rb wraps each test file's body in
// `namespace <basename>` and an ObjC declaration may only appear at global
// scope — but every #import is hoisted, so a declaration reached through one is
// fine. Same arrangement as Find/tests/FindTesting.h.
//
// Declaring these here is not a back door: every member exists today as a
// private property or method of the class, and this file is what pins their
// ObjC spellings. A port that renamed one would stop compiling here rather than
// failing silently at runtime (rule 64).
#import "../src/EncodingView.h"
#import <OakAppKit/OakEncodingPopUpButton.h>

@interface EncodingWindowController (Testing)
@property (nonatomic, readonly) NSObjectController*     objectController;
@property (nonatomic, readonly) NSTextField*            explanation;
@property (nonatomic, readonly) OakEncodingPopUpButton* popUpButton;
@property (nonatomic, readonly) NSTextView*             textView;
@property (nonatomic, readonly) NSButton*               learnCheckBox;
@property (nonatomic, readonly) NSButton*               openButton;
@property (nonatomic, readonly) NSButton*               cancelButton;

- (void)performOpenDocument:(id)sender;
- (void)performCancelOperation:(id)sender;
@end
