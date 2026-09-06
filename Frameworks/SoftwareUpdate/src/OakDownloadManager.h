// Hand-declared (rule 23): this class is defined in OakDownloadManager.swift.
//
// It must stay out of any bridging header, where it would collide with the
// generated -Swift.h (rule 43). Two consumers import it, both still ObjC++:
// BundlesManager.mm, which calls both entry points, and SoftwareUpdate.mm.
//
// The selectors here are pinned by t_software_update.mm (rule 18) — nothing
// checks a hand declaration against the Swift at build time, and a drift is an
// unrecognized selector at runtime.
NS_ASSUME_NONNULL_BEGIN

@interface OakDownloadManager : NSObject
@property (class, readonly) OakDownloadManager* sharedInstance;
@property (nonatomic) NSString* userAgentString;
- (void)downloadFileAtURL:(NSURL*)serverURL replacingFileAtURL:(NSURL*)localFileURL publicKeys:(NSDictionary<NSString*, NSString*>*)publicKeys completionHandler:(void(^)(BOOL wasUpdated, NSError* error))completionHandler;
- (id <NSProgressReporting>)downloadArchiveAtURL:(NSURL*)serverURL forReplacingURL:(nullable NSURL*)localURL publicKeys:(NSDictionary<NSString*, NSString*>*)publicKeys completionHandler:(void(^)(NSURL* extractedArchiveURL, NSError* error))completionHandler;
@end

NS_ASSUME_NONNULL_END
