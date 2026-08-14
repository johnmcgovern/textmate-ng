// One live FSEvents stream, wrapped as an ObjC object.
//
// This exists so FSEventsManager can become Swift. That class held a
// std::shared_ptr<fs_events_t> ivar — the C++ FSEvents API wrapper — and a Swift
// @objc class cannot hold a shared_ptr. It is not a value to convert at a
// boundary; it is C++ state (an FSEventStreamRef scheduled on the run loop)
// whose lifetime is tied to the object.
//
// That is the same blocker DWScopeContext answered for DocumentWindowController,
// and the answer is the same: an ObjC-shaped class owns the C++, so the manager
// holds only a pointer to it. This header is deliberately free of C++ so a Swift
// bridging header could import it; the fs_events_t struct stays inside
// FSEventStream.mm.
//
// Lifetime, kept identical to the shared_ptr it replaces: creating a stream
// starts watching immediately, and releasing it (which -resetObservers does by
// assigning a fresh one over the old) stops, invalidates and releases the
// underlying FSEventStreamRef in -dealloc — the same ordering ~fs_events_t gave,
// so no callback can fire into a freed context.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface FSEventStream : NSObject
// Watches the given directory URLs; `callback` fires on the run loop with the
// directory URL that changed. An empty `urls` creates no underlying stream, as
// before.
- (instancetype)initWithURLs:(NSArray<NSURL*>*)urls callback:(void(^)(NSURL*))callback;
@end

NS_ASSUME_NONNULL_END
