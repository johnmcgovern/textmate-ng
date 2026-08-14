// The C++ side of the SCMManager boundary.
//
// SCMManager.h was a *public* header carrying two C++ spellings: SCMRepository's
// `status` map, whose element type scm::status::type an interop-mode importer
// drops, and -addObserverToFileAtURL:usingBlock:, whose block takes a
// scm::status::type — rule 15, which makes the whole method uncallable from
// Swift rather than merely awkward. Either one keeps a Swift bridging header
// from importing SCMManager.h at all (rule 21 cascade), which would block every
// Swift file in this framework.
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

@interface SCMManager (Cxx)
// Observes a single file's status, coalescing to fire only when it changes.
// Currently unused — kept in C++ form here rather than retyped to TMSCMStatus in
// the public header, since nothing calls it and its block hands out a raw
// scm::status::type.
- (id)addObserverToFileAtURL:(NSURL*)url usingBlock:(void(^)(scm::status::type))handler;
@end
