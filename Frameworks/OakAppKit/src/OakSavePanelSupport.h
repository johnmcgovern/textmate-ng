// The C++ half of OakSavePanel: a box for `encoding::type`, and the rule that
// decides what encoding a file being saved should get.
//
// encoding::type blocks this port three ways at once — it is an ivar on the
// accessory controller (rule 20), a parameter of the entry point, and a
// parameter of that entry point's **completion block** (rule 15). The last is
// the one that cannot be worked around in Swift at all, which is why the box
// exists rather than a pair of NSStrings passed around loose.
//
// nil means NULL_STR in both halves. That is not a convenience: kCharsetNoEncoding
// *is* NULL_STR, so a default-constructed encoding::type carries nothing in
// either half and the two cases genuinely are the same one.
#import <Cocoa/Cocoa.h>

@interface OakEncodingOptions : NSObject
@property (nonatomic, readonly) NSString* newlines;
@property (nonatomic, readonly) NSString* charset;
+ (instancetype)optionsWithNewlines:(NSString*)newlines charset:(NSString*)charset;
@end

@interface OakSavePanelSupport : NSObject
// -encodingForURL:'s rule, whole. Each half is filled from settings only when it
// is unset, and the charset goes through encoding::type's setter — which
// **uppercases** — while the newlines do not.
+ (OakEncodingOptions*)resolveOptions:(OakEncodingOptions*)options forURL:(NSURL*)url fileType:(NSString*)fileType;

// What +initialize did. Idempotent, and it has to run before the accessory view
// is built: the line-endings pop-up binds through this transformer by name.
+ (void)registerValueTransformers;
@end
