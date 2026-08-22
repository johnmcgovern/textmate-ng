// OakRolloverButton is forward-declared, deliberately, and this header must not
// import it.
//
// Nine frameworks' bridging headers import this file (plus OakTextView's
// LiveSearchView.h), and it used to pull OakRolloverButton.h in at line 1. That
// transitive import is what rule 21 is about: the moment OakRolloverButton is
// defined in Swift, its hand-declared header (rule 23) arrives inside OakAppKit's
// *own* bridging header through this file, collides with OakAppKit-Swift.h, and
// every consumer splits into __ObjC.OakRolloverButton vs OakAppKit.OakRolloverButton.
//
// Only OakCreateCloseButton's return type needs the name here, and a return type
// needs nothing but the name. Callers that use the returned button at all import
// <OakAppKit/OakRolloverButton.h> themselves — OakAppKit, OakTabBarView, FileBrowser
// and OakFilterList each do. Swift consumers have no choice about this: a forward
// declaration imports as an opaque type that is not even an NSButton, so `.target`
// on the result of OakCreateCloseButton does not compile without the real header.
@class OakRolloverButton;

typedef NS_ENUM(NSUInteger, OakBackgroundFillViewStyle) {
	OakBackgroundFillViewStyleNone = 0,
	OakBackgroundFillViewStyleHeader,
};

@interface OakBackgroundFillView : NSView
@property (nonatomic) OakBackgroundFillViewStyle style;
@property (nonatomic) NSColor* activeBackgroundColor;
@property (nonatomic) NSColor* inactiveBackgroundColor;
@property (nonatomic) NSGradient* activeBackgroundGradient;
@property (nonatomic) NSGradient* inactiveBackgroundGradient;
@property (nonatomic) BOOL active;
@end

NSFont* OakStatusBarFont ();
NSFont* OakControlFont ();

NSTextField* OakCreateLabel (NSString* label = @"", NSFont* font = nil, NSTextAlignment alignment = NSTextAlignmentLeft, NSLineBreakMode lineBreakMode = NSLineBreakByTruncatingMiddle);
NSButton* OakCreateCheckBox (NSString* label);
NSButton* OakCreateButton (NSString* label, NSBezelStyle bezel = NSBezelStyleRounded);
NSPopUpButton* OakCreatePopUpButton (BOOL pullsDown = NO, NSString* initialItemTitle = nil, NSView* labelView = nil);
NSPopUpButton* OakCreateActionPopUpButton (BOOL bordered = NO);
NSComboBox* OakCreateComboBox (NSView* labelView = nil);
OakRolloverButton* OakCreateCloseButton (NSString* accessibilityLabel = @"Close document");
NSView* OakCreateNSBoxSeparator ();

OakBackgroundFillView* OakCreateVerticalLine (OakBackgroundFillViewStyle style);
void OakSetupKeyViewLoop (NSArray<NSView*>* views);
void OakAddAutoLayoutViewsToSuperview (NSArray<NSView*>* views, NSView* superview);
