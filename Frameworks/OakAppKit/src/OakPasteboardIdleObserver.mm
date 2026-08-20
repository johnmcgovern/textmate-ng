#import "OakPasteboardIdleObserver.h"

// Ported from OakPasteboard.mm's event_loop_idle_callback_t (rule 6): same
// CFRunLoopObserver, same BeforeWaiting/order-100/main-run-loop behaviour, same
// auto-start on first construction. The std::set of raw pointers became a weak
// NSHashTable — non-owning as the raw pointers were, and the pasteboards are
// permanent singletons regardless — and the callback reaches the singleton the way
// the C++ static callback reached idle_callback().

@implementation OakPasteboardIdleObserver
{
	BOOL _running;
	CFRunLoopObserverRef _observer;
	NSHashTable<id<OakPasteboardIdleObserving>>* _objects;
}

+ (instancetype)sharedInstance
{
	static OakPasteboardIdleObserver* instance = [self new];
	return instance;
}

static void OakPasteboardIdleCallback (CFRunLoopObserverRef observer, CFRunLoopActivity activity, void* info)
{
	OakPasteboardIdleObserver* instance = OakPasteboardIdleObserver.sharedInstance;
	for(id<OakPasteboardIdleObserving> object in instance->_objects)
		[object checkForExternalPasteboardChanges];
}

- (instancetype)init
{
	if(self = [super init])
	{
		_objects  = [NSHashTable weakObjectsHashTable];
		_observer = CFRunLoopObserverCreate(kCFAllocatorDefault, kCFRunLoopBeforeWaiting, true, 100, &OakPasteboardIdleCallback, NULL);
		[self start];
	}
	return self;
}

- (void)start
{
	if(_running)
		return;
	_running = YES;
	CFRunLoopAddObserver(CFRunLoopGetCurrent(), _observer, kCFRunLoopCommonModes);
}

- (void)stop
{
	if(!_running)
		return;
	_running = NO;
	CFRunLoopRemoveObserver(CFRunLoopGetCurrent(), _observer, kCFRunLoopCommonModes);
}

- (void)addObject:(id<OakPasteboardIdleObserving>)object
{
	[_objects addObject:object];
}
@end
