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
#import <Security/Security.h>

@class TMUpdateManifest;

@interface SoftwareUpdate (Testing)
+ (NSString*)mediaTypeFromContentType:(NSString*)contentType;
@end

@interface OakDownloadManager (Testing)
// Unpacks a verified archive. Pinned because the whole point of separating it
// from the download is that extraction happens *after* verification, and that
// ordering is not otherwise reachable from a test — a real download needs a
// server. See ide/SOFTWARE_UPDATE_PLAN.md step 1.
- (BOOL)extractArchiveAtURL:(NSURL*)fileURL intoDirectory:(NSURL*)directory error:(NSError**)error;

// The update channel's ECDSA verification, pinned in t_software_update.mm with a
// keypair generated in the test. Nothing in the app reaches these yet — the
// manifest that will carry the signature is step 4 of the plan.
+ (SecKeyRef)publicKeyFromBase64X963String:(NSString*)string;

// The update channel's download: size and checksum from a signed manifest, no
// signature on the archive itself. Pinned end-to-end over a file:// URL, which a
// URLSession data task delivers through the delegate exactly as it does an HTTP
// one (measured 2026-09-08).
- (id<NSProgressReporting>)downloadArchiveAtURL:(NSURL*)serverURL forReplacingURL:(NSURL*)localURL expectedSHA256:(NSString*)sha256 expectedSize:(int64_t)size completionHandler:(void(^)(NSURL* extractedArchiveURL, NSError* error))completionHandler;
- (BOOL)data:(NSData*)data hasValidECDSASignature:(NSData*)signature usingPublicKey:(SecKeyRef)publicKey;
@end

// The signed update manifest (step 4). `now` is a parameter so expiry is testable
// without waiting a month; `keys` so the pins can use a throwaway keypair instead
// of J23's real one.
@interface TMUpdateManifest : NSObject
@property (nonatomic, readonly) NSString* version;
@property (nonatomic, readonly) NSURL*    url;
@property (nonatomic, readonly) NSString* sha256;
@property (nonatomic, readonly) int64_t   size;
@property (nonatomic, readonly) NSString* minimumSystemVersion;

+ (TMUpdateManifest*)manifestFromData:(NSData*)data keys:(NSDictionary<NSString*, NSString*>*)keys now:(NSDate*)now error:(NSError**)error;
@end

// The last two checks before the running application is replaced (step 5).
// `requirement` is a parameter so the mechanism can be pinned against a bundle
// that exists on the test machine, with a control that must fail (rule 59).
@interface TMUpdateVerification : NSObject
@property (class, readonly) NSString* designatedRequirement;
+ (BOOL)checkCodeSignatureOfBundleAtURL:(NSURL*)url requirement:(NSString*)requirement error:(NSError**)error;
+ (BOOL)checkBundleAtURL:(NSURL*)url matchesManifest:(TMUpdateManifest*)manifest error:(NSError**)error;
@end
