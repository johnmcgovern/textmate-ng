// The surface of SoftwareUpdate and OakDownloadManager that the tests drive but
// consumers do not need.
//
// In its own header because ide/gen_xctest.rb wraps each test file's body in
// `namespace <basename>` and an ObjC declaration may only appear at global
// scope — but every #import is hoisted, so a declaration reached through one is
// fine. Same arrangement as Find/tests/FindTesting.h and FFKVORecorder.h.
//
// Declaring these here is not a back door: both methods exist, and this file is
// what pins their ObjC spellings. A port that renamed one would stop compiling
// here rather than failing silently at runtime (rule 64).
#import "../src/SoftwareUpdate.h"
#import "../src/OakDownloadManager.h"

@interface SoftwareUpdate (Testing)
+ (NSString*)mediaTypeFromContentType:(NSString*)contentType;
@end

@interface OakDownloadManager (Testing)
// Unpacks a verified archive. Pinned because the whole point of separating it
// from the download is that extraction happens *after* verification, and that
// ordering is not otherwise reachable from a test — a real download needs a
// server. See ide/SOFTWARE_UPDATE_PLAN.md step 1.
- (BOOL)extractArchiveAtURL:(NSURL*)fileURL intoDirectory:(NSURL*)directory error:(NSError**)error;
@end
