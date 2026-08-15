// The C++ fragment of the SCM data source, kept in ObjC++ so the rest of
// FileItemSCMStatus can be Swift.
//
// These two methods walk SCMRepository's status — a std::map<std::string,
// scm::status::type> reached through SCMManagerCxx.h — filtering by scm::status::
// bitmasks and collapsing parent/child paths with path::is_child. That is real
// C++ that would be a hazard to re-derive in Swift (rule 6), so it stays here;
// the Swift SCMStatusObserver calls these. The signatures are C++-free
// (SCMRepository* comes from the now-C++-free SCMManager.h), so the bridging
// header can import this.
#import "SCMManager.h"

@interface FileItemSCMStatusSupport : NSObject
+ (NSArray<NSURL*>*)unstagedURLsInRepository:(SCMRepository*)repository;
+ (NSArray<NSURL*>*)untrackedURLsInRepository:(SCMRepository*)repository;
@end
