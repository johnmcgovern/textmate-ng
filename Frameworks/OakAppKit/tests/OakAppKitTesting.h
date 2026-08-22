// The internal surface of OakAppKit's leaves that the tests drive.
//
// In its own header for the reason FindTesting.h and DocumentWindowTesting.h
// are: ide/gen_xctest.rb wraps each test file's body in `namespace <basename>`,
// and an ObjC declaration may only appear at global scope — but every `#import`
// is hoisted, so a declaration reached through one is fine.
//
// Every member here exists today in a class extension. Declaring it pins the
// spelling a Swift port has to keep reachable from ObjC, so a mistake is a
// compile error rather than an unrecognized selector at runtime.
#import "../src/OakFinderTag.h"
#import "../src/OakBorderlessPanel.h"
#import "../src/OakZoomingIcon.h"
#import "../src/NSImage Additions.h"
#import "../src/OakRolloverButton.h"
#import "../src/OakEncodingPopUpButton.h"
#import "../src/OakOpenWithMenu.h"
#import "../src/OakSavePanel.h" // brings <file/encoding.h> with it
#import "../src/OakSavePanelCxx.h"
#import <OakFoundation/OakFoundation.h> // OakUserDefaultsObserver

@interface OakFinderTag (Testing)
// The label is what maps a tag to one of Finder's seven colours; the public
// header exposes only -labelColor and -hasLabelColor derived from it. Tests need
// to construct a tag at a known label, because the mapping is a table and a
// table is what a port gets subtly wrong.
- (instancetype)initWithDisplayName:(NSString*)name label:(NSUInteger)label;
+ (instancetype)tagWithDisplayName:(NSString*)name label:(NSUInteger)label;
@property (nonatomic, readonly) NSUInteger label;
@end

@interface OakFinderTagManager (Testing)
// Parses the `com.apple.metadata:_kMDItemUserTags` bplist. Already split out
// from +finderTagsForURL: in the ObjC++, which is what lets the parsing be
// tested without putting an xattr on a file.
+ (NSArray<OakFinderTag*>*)finderTagsFromData:(NSData*)data;
@end

@interface OakRolloverButton (Testing)
// The two booleans the whole class is a function of. Both live in a class
// extension today and are set only from AppKit callbacks — window main/key
// notifications for one, tracking areas for the other — neither of which a test
// process can drive reliably. Declaring them lets the image table be tested as
// the table it is.
@property (nonatomic) BOOL active;
@property (nonatomic) BOOL mouseInside;
@end

@interface OakEncodingPopUpButton (Testing) <OakUserDefaultsObserver>
// All three live in the .mm's class extension today, and all three are reached
// by @selector() rather than through a header — the two menu actions are wired
// with -setTarget:/-addItemWithTitle:action:, and the callback comes from a
// protocol the class adopts privately. Nothing but a test notices when one is
// renamed, which is exactly what pinning them is for.
- (void)selectEncoding:(NSMenuItem*)sender;
- (void)customizeAvailableEncodings:(id)sender;
@end

@interface OakOpenWithApplicationInfo (Testing)
// The initialiser and the three writable halves, all of which live in the .mm's
// class extension. -displayName is a function of the three flags and cannot be
// exercised without them.
//
// Note the getter names: `defaultApplication` is what the sort descriptors use
// as a KVC key, `isDefaultApplication` is what -menuNeedsUpdate: calls. A Swift
// port has to keep *both* spellings, which is rule 4's whole point.
- (instancetype)initWithBundleURL:(NSURL*)url;
@property (nonatomic, readwrite, getter = isDefaultApplication) BOOL defaultApplication;
@property (nonatomic, readwrite, getter = hasMultipleVersions)  BOOL multipleVersions;
@property (nonatomic, readwrite, getter = hasMultipleCopies)    BOOL multipleCopies;
@end

// OakEncodingSaveOptionsViewController is declared only in OakSavePanel.mm — it
// is the save panel's accessory view and the whole of its behaviour. The panel
// itself cannot be tested (it wants a window and a modal sheet), so this is
// where the coverage has to go.
@interface OakEncodingSaveOptionsViewController : NSViewController
// Box-based since the OakSavePanelSupport split: these are the spellings the
// Swift port keeps, so the pins mean the same thing on both sides of it.
- (instancetype)initWithOptions:(OakEncodingOptions*)someEncodingOptions fileType:(NSString*)aFileType;
- (OakEncodingOptions*)resolvedOptionsForURL:(NSURL*)anURL;
- (void)updateSettingsWithOptions:(OakEncodingOptions*)options;
@property (nonatomic) NSString* fileType;
@property (nonatomic) NSString* lineEndings;
@property (nonatomic) NSString* encoding;
@property (nonatomic) NSSavePanel* savePanel;
@end
