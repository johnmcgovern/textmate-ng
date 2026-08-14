#import "FSEventStream.h"
#import <memory>

// The C++ FSEvents wrapper, moved verbatim from FSEventsManager.mm — the rule
// this project earned on FFResultNodeSupport.mm: C++ that has to move is copied,
// never retyped. It stores `this` in the FSEventStreamContext and casts it back
// in the C callback, so its address must be stable; a std::unique_ptr member of
// this (never-moved) ObjC object gives it exactly the heap identity the original
// `new fs_events_t(...)` did.

namespace
{
	struct fs_events_t
	{
		FSEventStreamRef _eventStream = nullptr;
		NSSet<NSURL*>* _observedURLs;
		void(^_callback)(NSURL*);

		fs_events_t (NSArray<NSURL*>* urls, void(^callback)(NSURL*)) : _callback(callback)
		{
			_observedURLs = [NSSet setWithArray:urls];
			if(_observedURLs.count)
			{
				NSArray* pathsToWatch = [_observedURLs.allObjects valueForKey:@"path"];

				FSEventStreamContext contextInfo = { 0, this, nullptr, nullptr, nullptr };
				if(_eventStream = FSEventStreamCreate(kCFAllocatorDefault, &fs_events_t::callback, &contextInfo, (__bridge CFArrayRef)pathsToWatch, kFSEventStreamEventIdSinceNow, 0.5, kFSEventStreamCreateFlagNone))
				{
					FSEventStreamScheduleWithRunLoop(_eventStream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
					FSEventStreamStart(_eventStream);
				}
			}
		}

		~fs_events_t ()
		{
			if(_eventStream)
			{
				FSEventStreamStop(_eventStream);
				FSEventStreamInvalidate(_eventStream);
				FSEventStreamRelease(_eventStream);
			}
		}

		static void callback (ConstFSEventStreamRef streamRef, void* clientCallBackInfo, size_t numEvents, void* eventPaths, FSEventStreamEventFlags const eventFlags[], FSEventStreamEventId const eventIds[])
		{
			fs_events_t* object = static_cast<fs_events_t*>(clientCallBackInfo);
			for(size_t i = 0; i < numEvents; ++i)
			{
				char const* cString = ((char const* const*)eventPaths)[i];
				object->_callback([NSURL fileURLWithFileSystemRepresentation:cString isDirectory:YES relativeToURL:nil]);
			}
		}
	};
}

@implementation FSEventStream
{
	std::unique_ptr<fs_events_t> _fsEvents;
}

- (instancetype)initWithURLs:(NSArray<NSURL*>*)urls callback:(void(^)(NSURL*))callback
{
	if(self = [super init])
		_fsEvents = std::make_unique<fs_events_t>(urls, callback);
	return self;
}
@end
