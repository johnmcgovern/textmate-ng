#import "FSEventsManager.h"
#import "FSEventStream.h"

@class FSEventsDirectory;

@interface FSEventsClient : NSObject
@property (nonatomic, readonly) void(^handler)(NSURL*);
@property (nonatomic, readonly) BOOL observeSubdirectories;
@property (nonatomic) FSEventsDirectory* directory;
- (instancetype)initWithBlock:(void(^)(NSURL*))handler observeSubdirectories:(BOOL)flag;
- (void)removeFromDirectory;
@end

@interface FSEventsDirectory : NSObject
@property (nonatomic, readonly) NSURL* URL;
@property (nonatomic, readonly) NSMutableArray<FSEventsClient*>* clients;
- (instancetype)initWithURL:(NSURL*)url;
- (void)addClient:(FSEventsClient*)observer;
- (void)removeClient:(FSEventsClient*)observer;
- (void)didObserveChangeInDirectoryAtURL:(NSURL*)url;
@end

@interface FSEventsManager ()
{
	NSMapTable<NSURL*, FSEventsDirectory*>* _directories;
	FSEventStream* _fsEvents;
}
@end

@implementation FSEventsManager
+ (instancetype)sharedInstance
{
	static FSEventsManager* sharedInstance = [self new];
	return sharedInstance;
}

- (instancetype)init
{
	if(self = [super init])
	{
		_directories = [NSMapTable strongToWeakObjectsMapTable];
	}
	return self;
}

- (void)reloadDirectoryAtURL:(NSURL*)url
{
	[[_directories objectForKey:url] didObserveChangeInDirectoryAtURL:url];
}

- (void)resetObservers
{
	_fsEvents = [[FSEventStream alloc] initWithURLs:_directories.keyEnumerator.allObjects callback:^(NSURL* originalURL){
		NSURL* url = originalURL;
		while(true)
		{
			[[_directories objectForKey:url] didObserveChangeInDirectoryAtURL:originalURL];

			NSNumber* isVolume;
			if([url getResourceValue:&isVolume forKey:NSURLIsVolumeKey error:nil] && isVolume.boolValue)
				break;

			NSURL* parentURL;
			if(![url getResourceValue:&parentURL forKey:NSURLParentDirectoryURLKey error:nil] || [url isEqual:parentURL])
				break;

			url = parentURL;
		}
	}];
}

- (id)addObserverToDirectoryAtURL:(NSURL*)url usingBlock:(void(^)(NSURL*))handler
{
	return [self addObserverToDirectoryAtURL:url observeSubdirectories:NO usingBlock:handler];
}

- (id)addObserverToDirectoryAtURL:(NSURL*)url observeSubdirectories:(BOOL)flag usingBlock:(void(^)(NSURL*))handler
{
	FSEventsDirectory* directory = [_directories objectForKey:url];
	if(!directory)
	{
		directory = [[FSEventsDirectory alloc] initWithURL:url];
		[_directories setObject:directory forKey:url];
		[self resetObservers];
	}

	FSEventsClient* newClient = [[FSEventsClient alloc] initWithBlock:handler observeSubdirectories:flag];
	[directory addClient:newClient];
	return newClient;
}

- (void)removeObserver:(id)someObserver
{
	FSEventsClient* client = someObserver;
	FSEventsDirectory* directory = client.directory;

	[client removeFromDirectory];

	if(directory.clients.count == 0)
		[self resetObservers];
}
@end

@implementation FSEventsDirectory
- (instancetype)initWithURL:(NSURL*)url
{
	if(self = [super init])
	{
		_URL     = url;
		_clients = [NSMutableArray array];
	}
	return self;
}

- (void)didObserveChangeInDirectoryAtURL:(NSURL*)url
{
	BOOL changeInCurrentDirectory = [url isEqual:_URL];
	for(FSEventsClient* client in _clients)
	{
		if(changeInCurrentDirectory || client.observeSubdirectories)
			client.handler(url);
	}
}

- (void)addClient:(FSEventsClient*)observer
{
	observer.directory = self;
	[_clients addObject:observer];
}

- (void)removeClient:(FSEventsClient*)observer
{
	[_clients removeObject:observer];
	observer.directory = nil;
}
@end

@implementation FSEventsClient
- (instancetype)initWithBlock:(void(^)(NSURL*))handler observeSubdirectories:(BOOL)flag
{
	if(self = [super init])
	{
		_handler = handler;
		_observeSubdirectories = flag;
	}
	return self;
}

- (void)removeFromDirectory
{
	[_directory removeClient:self];
}
@end
