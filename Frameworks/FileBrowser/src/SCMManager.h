// C++-free, so a Swift bridging header can import it. `status` is an SCMStatus
// (SCMSupport.h) — the ObjC++ wrapper the raw std::map moved into — so nothing
// here forces C++. The two consumers that still want the raw map reach it through
// SCMStatus's own Cxx category (SCMSupportCxx.h).
#import "SCMSupport.h"

@interface SCMRepository : NSObject
@property (nonatomic, readonly) NSURL* URL;
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) BOOL tracksDirectories;
@property (nonatomic, readonly) BOOL hasStatus;
@property (nonatomic, readonly) SCMStatus* status;
@property (nonatomic, readonly) NSDictionary<NSString*, NSString*>* variables;
@end

@interface SCMManager : NSObject
@property (class, readonly) SCMManager* sharedInstance;

- (id)addObserverToRepositoryAtURL:(NSURL*)url usingBlock:(void(^)(SCMRepository*))handler;
- (void)removeObserver:(id)someObserver;

- (SCMRepository*)repositoryAtURL:(NSURL*)url;
@end
