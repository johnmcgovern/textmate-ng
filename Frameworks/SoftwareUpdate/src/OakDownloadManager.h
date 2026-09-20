// Hand-declared (rule 23): this class is defined in OakDownloadManager.swift.
//
// It must stay out of any bridging header, where it would collide with the
// generated -Swift.h (rule 43). Two consumers import it, both still ObjC++:
// BundlesManager.mm, which calls both entry points, and SoftwareUpdate.mm.
//
// The selectors here are pinned by t_software_update.mm (rule 18) — nothing
// checks a hand declaration against the Swift at build time, and a drift is an
// unrecognized selector at runtime.
//
// The completion blocks' nullability is the Swift definition's: (Bool, Error?)
// and (URL?, Error?). Under NS_ASSUME_NONNULL an unmarked NSError* imports as a
// non-optional Error, and BundlesManager.swift reading one that is nil would
// trap, so the two are marked (rule 44).
NS_ASSUME_NONNULL_BEGIN

@interface OakDownloadManager : NSObject
@property (class, readonly) OakDownloadManager* sharedInstance;
@property (nonatomic) NSString* userAgentString;
- (void)downloadFileAtURL:(NSURL*)serverURL replacingFileAtURL:(NSURL*)localFileURL publicKeys:(NSDictionary<NSString*, NSString*>*)publicKeys completionHandler:(void(^)(BOOL wasUpdated, NSError* _Nullable error))completionHandler;
- (id <NSProgressReporting>)downloadArchiveAtURL:(NSURL*)serverURL forReplacingURL:(nullable NSURL*)localURL publicKeys:(NSDictionary<NSString*, NSString*>*)publicKeys completionHandler:(void(^)(NSURL* _Nullable extractedArchiveURL, NSError* _Nullable error))completionHandler;

// The same download, verified against a digest from a signed index instead of a
// signature in the response headers. Used by the software updater, and since
// 2026-09-20 by BundlesManager too — the header-signature variant above needs
// S3 object metadata, which the bundle mirror's host cannot provide.
- (id <NSProgressReporting>)downloadArchiveAtURL:(NSURL*)serverURL forReplacingURL:(nullable NSURL*)localURL expectedSHA256:(NSString*)expectedSHA256 expectedSize:(int64_t)expectedSize completionHandler:(void(^)(NSURL* _Nullable extractedArchiveURL, NSError* _Nullable error))completionHandler;
@end

NS_ASSUME_NONNULL_END

// ============================================================
// = TMUpdateManifest                                         =
// ============================================================

// Declared here rather than in a header of its own because this is the only
// file BundlesManager's bridging header already imports from this framework,
// and the pair it needs is small. Rule 23: these signatures must match the
// @objc names on the Swift side exactly — verifiedPayloadFromData:keys:error:
// and embeddedKeys — or the call compiles and traps at runtime.
NS_ASSUME_NONNULL_BEGIN

@interface TMUpdateManifest : NSObject
@property (nonatomic, readonly) NSString* version;
@property (nonatomic, readonly) NSURL*    url;
@property (nonatomic, readonly) NSString* sha256;
@property (nonatomic, readonly) int64_t   size;
@property (nonatomic, readonly) NSString* minimumSystemVersion;

// The signed bytes out of a wrapper, once the signature over them verifies
// against one of `keys`. Returns nil and sets `error` if it does not. Used by
// BundlesManager for the bundle index, whose payload is a plist rather than the
// JSON the method below expects — which is why the two are separate.
+ (nullable NSData*)verifiedPayloadFromData:(NSData*)data keys:(NSDictionary<NSString*, NSString*>*)keys error:(NSError**)error;

// `now` is a parameter so expiry is testable without waiting a month; `keys` so
// the pins can use a throwaway keypair instead of J23's real one.
+ (nullable TMUpdateManifest*)manifestFromData:(NSData*)data keys:(NSDictionary<NSString*, NSString*>*)keys now:(NSDate*)now error:(NSError**)error;

// The keys this build carries, from Info.plist's TMUpdateManifestKeys.
+ (NSDictionary<NSString*, NSString*>*)embeddedKeys;
@end

NS_ASSUME_NONNULL_END
