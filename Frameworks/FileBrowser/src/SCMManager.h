// The C++-typed members — SCMRepository's `status` map and
// -addObserverToFileAtURL:usingBlock: — live in SCMManagerCxx.h so this header
// stays importable from a Swift bridging header. See that file for why.

@interface SCMRepository : NSObject
@property (nonatomic, readonly) NSURL* URL;
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) BOOL tracksDirectories;
@property (nonatomic, readonly) BOOL hasStatus;
@property (nonatomic, readonly) NSDictionary<NSString*, NSString*>* variables;
@end

@interface SCMManager : NSObject
@property (class, readonly) SCMManager* sharedInstance;

- (id)addObserverToRepositoryAtURL:(NSURL*)url usingBlock:(void(^)(SCMRepository*))handler;
- (void)removeObserver:(id)someObserver;

- (SCMRepository*)repositoryAtURL:(NSURL*)url;
@end
