// The C++ side of SCMManager, wrapped so the manager itself can become Swift.
//
// SCMRepository held two things Swift cannot: a `scm::driver_t const*` (a borrowed
// pointer to a C++ singleton driver) and a `std::map<std::string,
// scm::status::type>` (owned value state). This is the DWScopeContext /
// FSEventStream pattern applied to both — an ObjC-shaped class owns each, and the
// to-be-Swift manager holds only pointers.
//
// This header is deliberately free of C++ so the Swift bridging header can import
// it. The raw `std::map` the two external consumers still iterate lives behind
// SCMSupportCxx.h, which is not bridging-header-safe. See there.

#import <Foundation/Foundation.h>
#import <TMFileReference/TMSCMStatus.h>

NS_ASSUME_NONNULL_BEGIN

@class SCMStatus;

// One version-control driver (git/hg/p4/svn), wrapping `scm::driver_t const*`.
// The drivers are process-static singletons the wrapper borrows, so an SCMDriver
// owns no C++ lifetime — it is a typed handle, created only by the two class
// methods below.
@interface SCMDriver : NSObject
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

// scm::scm_enabled_for_path — whether SCM status should be shown for this path at
// all, independent of which driver (if any) claims it.
+ (BOOL)isSCMEnabledForPath:(NSString*)path;

// Walks the ordered driver table and returns the first driver that has a working
// copy at `path` (driver_t::has_info_for_directory), or nil if none does.
+ (nullable SCMDriver*)driverWithInfoForDirectory:(NSString*)path;

@property (nonatomic, readonly) BOOL tracksDirectories;

// driver_t::status / driver_t::variables for a working-copy directory. Both are
// the expensive calls SCMRepository runs on a background queue; statusForDirectory
// returns an immutable snapshot that then crosses back to the main thread as one
// pointer rather than a map.
- (SCMStatus*)statusForDirectory:(NSString*)path;
- (NSDictionary<NSString*, NSString*>*)variablesForDirectory:(NSString*)path;
@end

// An immutable snapshot of a working copy's per-file status, wrapping
// `std::map<std::string, scm::status::type>`. Created by -[SCMDriver
// statusForDirectory:]; never mutated after.
@interface SCMStatus : NSObject
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

// path (file-system representation) -> TMSCMStatus, for every entry the driver
// reported. This is what SCMRepository walks to build its TMFileReference set;
// the raw map, for the two ObjC++ consumers that still want scm::status:: bitmask
// arithmetic, is -rawStatus in SCMSupportCxx.h.
@property (nonatomic, readonly) NSDictionary<NSString*, NSNumber*>* entries;
@end

NS_ASSUME_NONNULL_END
