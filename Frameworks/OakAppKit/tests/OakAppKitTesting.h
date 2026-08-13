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
