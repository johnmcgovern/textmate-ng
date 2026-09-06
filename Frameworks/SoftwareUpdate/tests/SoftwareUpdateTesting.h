// The surface of SoftwareUpdate that the tests drive but consumers do not need.
//
// In its own header because ide/gen_xctest.rb wraps each test file's body in
// `namespace <basename>` and an ObjC declaration may only appear at global
// scope — but every #import is hoisted, so a declaration reached through one is
// fine. Same arrangement as Find/tests/FindTesting.h and FFKVORecorder.h.
//
// Declaring it here is not a back door: the method exists on SoftwareUpdate, and
// this file is what pins its ObjC spelling. A Swift port that renamed it would
// stop compiling here rather than failing silently at runtime (rule 64).
#import "../src/SoftwareUpdate.h"

@interface SoftwareUpdate (Testing)
+ (NSString*)mediaTypeFromContentType:(NSString*)contentType;
@end
