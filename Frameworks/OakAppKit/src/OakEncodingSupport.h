// The C++ half of OakEncodingPopUpButton, plus the one thing Swift cannot
// express at all.
//
// Two separate blockers live here. The first is ordinary: Charsets.plist is read
// with path:: and plist::, and the charset list was a std::vector<charset_t>.
// The second is not — the pop-up's +initialize registers the default encoding
// list and migrates a pre-2.0-beta.10 spelling, and **Swift cannot define
// +initialize**, so that work has to keep an ObjC home no matter how the button
// itself is written.
#import <Cocoa/Cocoa.h>

// One row of Charsets.plist.
@interface OakCharset : NSObject
// The full display name, e.g. "Western – Mac OS Roman".
@property (nonatomic, readonly) NSString* name;
@property (nonatomic, readonly) NSString* code;
// -name split on " – ", and **nil for both when it does not split into exactly
// two parts**. The pop-up's menu skips those rows; the customize list does not,
// which is why the split is exposed rather than applied.
@property (nonatomic, readonly) NSString* group;
@property (nonatomic, readonly) NSString* title;
@end

@interface OakEncodingSupport : NSObject
// Charsets.plist, preferring ~/Library/Application Support/TextMate over the
// copy in the framework bundle. Read once per call, as it always was.
+ (NSArray<OakCharset*>*)charsets;

// The old +initialize, callable. Registers the eight default encodings and
// rewrites a legacy list in place; idempotent, so every initialiser can call it.
// It must run before the enabled list is read, which +initialize guaranteed by
// running before the first message to the class — a caller now has to say so.
+ (void)registerDefaultEncodings;

// @"availableEncodings" — the key the preference survives under.
@property (class, readonly) NSString* availableEncodingsKey;
@end
