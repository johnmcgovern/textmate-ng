// The class-extension surface of Find that the tests drive.
//
// In its own header because ide/gen_xctest.rb wraps each test file's body in
// `namespace <basename>`, and an ObjC declaration may only appear at global
// scope — but every `#import` is hoisted to the top, so a declaration reached
// through one is fine. `@interface Find (Testing)` written inline fails with
// "Objective-C declarations may only appear in global scope"; the same reason
// FFKVORecorder lives in a header.
//
// Declaring these here is not a back door. Both members exist on Find today,
// in its class extension, and this file is what **pins** them: a Swift port has
// to keep `-acceptMatches:` and `results` reachable from ObjC under exactly
// these spellings, or this stops compiling. That is the guarantee, and it is
// cheaper than exporting them from Find.h where consumers would see them.
#import "../src/Find.h"

@class FFResultNode;
@class OakDocumentMatch;

@interface Find (Testing)
- (void)acceptMatches:(NSArray<OakDocumentMatch*>*)matches;
@property (nonatomic) FFResultNode* results;
@end
