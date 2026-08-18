// The C++ back door onto SCMStatus, for the two ObjC++ consumers that walk the
// raw status map with scm::status:: bitmasks and path:: operations.
//
// Replaces SCMManagerCxx.h, which carried the same map as a property on
// SCMRepository. It moved here with the map itself: SCMStatus now owns the
// std::map (see SCMSupport.h), so `repository.status.rawStatus` is where
// FileItemObserverSupport and FileItemSCMStatusSupport read it. Converting those
// two files to TMSCMStatus + NSString path arithmetic would be churn while they
// are themselves still ObjC++, which is the same call SCMManagerCxx.h made.
//
// Contains C++, so it must NOT be reachable from any Swift bridging header.

#import "SCMSupport.h"
#import <scm/status.h>

@interface SCMStatus (Cxx)
@property (nonatomic, readonly) scm::status_map_t const& rawStatus;
@end
