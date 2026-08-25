// The internal surface of OakTextView's leaves that the tests drive.
//
// In its own header for the reason OakAppKitTesting.h is: ide/gen_xctest.rb wraps
// each test file's body in `namespace <basename>`, and an ObjC declaration may
// only appear at global scope — but every `#import` is hoisted, so a declaration
// reached through one is fine.
//
// This is the first test bundle this framework has ever had. It covers the two
// leaves that are C++-free today; the framework's 6920 lines are otherwise
// unpinned, and OakTextView.mm itself (4633 of them) is not a porting candidate
// at all — it subclasses three C++ classes with virtual methods.
#import "../src/LiveSearchView.h"
#import "../src/OTVHUD.h"
#import "../src/OakChoiceMenu.h"
#import "../src/OTVStatusBar.h"

@interface LiveSearchView (Testing)
// Declared in the .mm's class extension. The separator is the only subview the
// public header does not expose, and its 1pt height constraint is the thing a
// port would round away.
@property (nonatomic) NSView* divider;
@end

@interface OTVHUD (Testing)
// -initWithView: is what +showHudForView:withText: caches on, and `lastView` is
// the key it caches by — a HUD is reused only while it is on the same view.
- (instancetype)initWithView:(NSView*)aView;
@property (nonatomic, weak) NSView* lastView;

// -setStringValue: is defined in the @implementation and declared nowhere at all;
// +showHudForView:withText: reaches it only because it is in the same file.
// Declaring it here pins the spelling a port has to keep — and makes the setter
// callable from outside, which it currently is not.
- (void)setStringValue:(NSString*)someText;
@end

@interface OakChoiceMenu (Testing)
// -doCommandBySelector: is NSResponder's, and the class overrides it to turn a
// selector into one of its private action codes. Declaring it lets the mapping be
// driven directly for the selectors that cannot be reached by synthesising a key
// event — the AndModifySelection and scroll* variants have no plain keystroke.
- (void)doCommandBySelector:(SEL)aSelector;
@end

@interface OTVStatusBar (Testing)
// Every control is a private property in the .mm. The status bar has no other
// observable surface — its public API is eight setters whose only effect is on
// these — so a test cannot say anything at all without them.
@property (nonatomic) NSTextField*   selectionField;
@property (nonatomic) NSPopUpButton* grammarPopUp;
@property (nonatomic) NSPopUpButton* tabSizePopUp;
@property (nonatomic) NSPopUpButton* bundleItemsPopUp;
@property (nonatomic) NSPopUpButton* symbolPopUp;
@property (nonatomic) NSButton*      macroRecordingButton;
@property (nonatomic) CGFloat        recordingTime;
@property (nonatomic) NSTimer*       recordingTimer;

// The two menu builders, so the menus can be driven without a real pop-up event.
- (void)setupTabSizeMenu:(id)sender;
- (void)grammarPopUpButtonWillPopUp:(NSNotification*)aNotification;
@end
