// The C++ side of the SCMManager boundary.
//
// SCMManager.h was a *public* header carrying two C++ spellings: SCMRepository's
// `status` map, whose element type scm::status::type an interop-mode importer
// drops, and -addObserverToFileAtURL:usingBlock:, whose block took a
// scm::status::type — rule 15, which makes the whole method uncallable from
// Swift rather than merely awkward. Either one keeps a Swift bridging header
// from importing SCMManager.h at all (rule 21 cascade), which would block every
// Swift file in this framework.
//
// The second of those is gone: that method had no callers anywhere and was
// deleted 2026-08-18 rather than carried further. Only the status map is left,
// so this header is one property away from being unnecessary.
//
// So the split TMBundleModelCxx.h and DWScopeContextCxx.h already make: the
// public header (SCMManager.h) is C++-free, and the C++ members move here, where
// only the ObjC++ that still speaks both languages reaches them —
// FileItemObserver.mm and FileItemSCMStatus.mm iterate the raw status map with
// scm::status:: bitmasks and path::parent, and converting that to Foundation at
// every call site would be churn in service of nothing while those files are
// themselves still ObjC++.
//
// This header contains C++ and therefore must NOT be reachable from any Swift
// bridging header.
#import "SCMManager.h"
#import <scm/status.h>

@interface SCMRepository (Cxx)
// path (fileSystemRepresentation) -> status for every tracked entry the driver
// reported. The synthesized getter of the readwrite property in SCMManager.mm's
// class extension backs this; it is declared here rather than in SCMManager.h
// only so the public header stays C++-free.
@property (nonatomic, readonly) std::map<std::string, scm::status::type> status;
@end
