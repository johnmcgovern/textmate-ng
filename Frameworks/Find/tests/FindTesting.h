// The class-extension surface of Find that the tests drive.
//
// In its own header because ide/gen_xctest.rb wraps each test file's body in
// `namespace <basename>`, and an ObjC declaration may only appear at global
// scope — but every `#import` is hoisted to the top, so a declaration reached
// through one is fine. `@interface Find (Testing)` written inline fails with
// "Objective-C declarations may only appear in global scope"; the same reason
// FFKVORecorder lives in a header.
//
// Declaring these here is not a back door. Every member exists on Find today,
// and this file is what **pins** them: a Swift port has to keep each one
// reachable from ObjC under exactly these spellings, or this stops compiling.
// That is the guarantee, and it is cheaper than exporting them from Find.h where
// consumers would see them.
#import "../src/Find.h"
#import "../src/FFFindAction.h"
#import "../src/FFFindOptions.h"

@class FFResultNode;
@class OakDocumentMatch;

@interface Find (Testing)
- (void)acceptMatches:(NSArray<OakDocumentMatch*>*)matches;
@property (nonatomic) FFResultNode* results;

// The option check boxes, which the assembly below reads. Declared here rather
// than in Find.h for the same reason as the rest of this file: they are the
// inputs a test has to set, and no consumer outside the framework sets them.
@property (nonatomic) BOOL ignoreCase;
@property (nonatomic) BOOL ignoreWhitespace;
@property (nonatomic) BOOL regularExpression;
@property (nonatomic) BOOL wrapAround;
@property (nonatomic) BOOL fullWords;

- (FFFindOptions)findOptionsForAction:(FindActionTag)action;

+ (NSString*)replacedStatusStringForCount:(NSUInteger)count findString:(NSString*)findString regularExpression:(BOOL)regularExpression;
+ (NSString*)replacementStatusStringForReplacementCount:(NSUInteger)replaceCount fileCount:(NSUInteger)fileCount;
+ (NSString*)resultCountStringForCount:(NSUInteger)count searchString:(NSString*)searchString;
+ (NSString*)shownResultCountStringForCount:(NSUInteger)count searchString:(NSString*)searchString;
+ (NSString*)searchedFilesSuffixForFileCount:(NSUInteger)fileCount seconds:(NSString*)seconds;
@end
