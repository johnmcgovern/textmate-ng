// The types Find's public interface is built from, split out from Find.h so the
// Swift half can import them.
//
// The split exists for one reason: Find.h declares `@interface Find`, and the
// class is now defined in Find.swift as `@objc(Find)`. A bridging header that
// imported Find.h would give the class two declarations — the arrangement
// FFResultNode.h and TMFileReference already ran into. But Find.swift genuinely
// needs FFSearchTarget, FindDelegate and FindMatch, so those move here and the
// bridging header imports this file instead.
//
// Both headers are exported (see default.rave), and Find.h imports this one, so
// no consumer outside the framework changed: `#import <Find/Find.h>` still
// brings in everything it used to.
//
// This header keeps the C++ — `text::range_t` in two FindMatch properties, in
// its initialiser, and in FindDelegate's -selectRange:inDocument:. Swift imports
// those declarations without complaint under this project's interop mode but
// never names the type: FindMatch is constructed through FindSupport.h, and
// -selectRange:inDocument: is called through it too.
#import <text/types.h>

@class OakDocument;

// A file's first and last match, in the ranges OakTextView steps through with ⌘G
// once a folder search has finished. Implemented in FindSupport.mm rather than
// Find.swift: two of its three properties are text::range_t, and OakTextView.mm
// constructs one directly from ranges it computes itself.
@interface FindMatch : NSObject
@property (nonatomic, readonly) NSUUID* UUID;
@property (nonatomic, readonly) text::range_t firstRange;
@property (nonatomic, readonly) text::range_t lastRange;
- (instancetype)initWithUUID:(NSUUID*)uuid firstRange:(text::range_t const&)firstRange lastRange:(text::range_t const&)lastRange;
@end

typedef NS_ENUM(NSInteger, FFSearchTarget) {
	FFSearchTargetDocument = 0,
	FFSearchTargetSelection,
	FFSearchTargetOpenFiles,
	FFSearchTargetProject,
	FFSearchTargetFileBrowserItems,
	FFSearchTargetOther,
};

@protocol FindDelegate <NSObject>
- (void)selectRange:(text::range_t const&)range inDocument:(OakDocument*)aDocument;
- (void)bringToFront;
@end
