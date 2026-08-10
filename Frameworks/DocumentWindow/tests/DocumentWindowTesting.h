// The class-extension surface of DocumentWindow's controllers that the tests
// drive.
//
// In its own header because ide/gen_xctest.rb wraps each test file's body in
// `namespace <basename>`, and an ObjC declaration may only appear at global
// scope — but every `#import` is hoisted to the top, so a declaration reached
// through one is fine. The same reason Find's FindTesting.h and FFKVORecorder.h
// are headers.
//
// Declaring these here is not a back door. Every member exists today, in a class
// extension, and this file is what **pins** it: a Swift port has to keep each one
// reachable from ObjC under exactly this spelling, or this stops compiling.
#import "../src/SelectGrammarViewController.h"
#import "../src/OakRunCommandWindowController.h"
#import "../src/DWOutputType.h"
#import "../src/ProjectLayoutView.h"

@class BundleGrammar;

@interface SelectGrammarViewController (Testing)
// The sentence shown in the strip, and the two properties it is derived from.
// `grammar` is set by -showGrammars:forView:completionHandler: in production;
// the tests set it directly so the decision table can be driven without a
// document view.
@property (nonatomic) BundleGrammar* grammar;
@property (nonatomic, readonly) NSString* labelString;
- (void)didClickButton:(id)sender;
@end

@interface OakRunCommandWindowController (Testing)
// Where the output goes, and the two controls the tests drive. All three are
// class-extension members today; declaring them here pins the spellings the port
// has to keep.
@property (nonatomic) DWOutputType    outputType;
@property (nonatomic) NSComboBox*     commandComboBox;
@property (nonatomic) NSPopUpButton*  resultPopUpButton;
@property (nonatomic) NSButton*       executeButton;
- (void)commandChanged:(NSNotification*)notification;
@end

@interface ProjectLayoutView (Testing)
// The two grab strips, which decide where the cursor changes and where a click
// starts a drag. Private today; pinned here so the port keeps them.
@property (nonatomic, readonly) NSRect fileBrowserResizeRect;
@property (nonatomic, readonly) NSRect htmlOutputResizeRect;
@property (nonatomic, readonly) NSView* htmlOutputDivider;
@end
