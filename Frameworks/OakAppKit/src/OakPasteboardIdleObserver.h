// The run-loop idle observer that OakPasteboard used to keep as a file-static C++
// singleton (event_loop_idle_callback_t, holding a std::set<OakPasteboard*>). Pulled
// out ahead of the Swift port: a CFRunLoopObserver is C API and the set is an
// NSHashTable, so nothing here is C++ and the pasteboard need only conform to the
// protocol and register itself. C++-free, so a Swift bridging header can import it.
#import <Foundation/Foundation.h>

@protocol OakPasteboardIdleObserving <NSObject>
// Called once per run-loop idle (kCFRunLoopBeforeWaiting), on the main thread.
- (void)checkForExternalPasteboardChanges;
@end

@interface OakPasteboardIdleObserver : NSObject
+ (instancetype)sharedInstance;
- (void)addObject:(id<OakPasteboardIdleObserving>)object;
- (void)start;
- (void)stop;
@end
