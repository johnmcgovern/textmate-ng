// Hand-written ObjC declaration of the Swift SCMRepository / SCMManager
// (SCMManager.swift), for the ObjC++ consumers that cannot import the generated
// FileBrowser-Swift.h (rule 23, rule 43): FileItemObserverSupport.mm and
// FileItemSCMStatusSupport.mm walk `repository.status.rawStatus` and read
// `-tracksDirectories`, and the test bundle drives the manager directly.
//
// **Kept out of the Swift bridging header** — Swift defines these classes, so
// importing this there would collide with FileBrowser-Swift.h's own declarations.
// The support headers that name SCMRepository in a signature forward-declare it
// (`@class SCMRepository;`) so they stay bridging-header-safe; their .mm files
// import this for the full interface. Nothing checks this declaration against the
// Swift at build time — t_scm_manager.mm's selector-surface tests (rule 18) are the
// guard against drift.
//
// `status` is an SCMStatus (SCMSupport.h) — the ObjC++ wrapper the raw std::map
// moved into — so nothing here forces C++. The two consumers that still want the
// raw map reach it through SCMStatus's own Cxx category (SCMSupportCxx.h).
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
