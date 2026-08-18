#import "SCMManager.h"
#import "SCMSupport.h"
#import "FSEventsManager.h"
#import <ns/ns.h>
#import <TMFileReference/TMFileReference.h>

// No C++ left on any ivar or method signature below — the `scm::driver_t const*`
// and `std::map` both moved to SCMSupport (SCMDriver / SCMStatus), which is what
// clears this file for the Swift port. It stays ObjC++ for now so the app and the
// existing tests judge those shims before any translation (the
// DocumentWindowController two-commit shape).

@class SCMRepositoryObserver;

@interface SCMRepository ()
{
	BOOL _needsUpdate;
	BOOL _updating;
	NSTimer* _updateTimer;
	NSDate* _noUpdateBefore;
	NSMutableSet<TMFileReference*>* _fileReferences;
}
@property (nonatomic, readwrite) SCMStatus* status;
@property (nonatomic, readwrite) NSDictionary<NSString*, NSString*>* variables;
@property (nonatomic, readonly) SCMDriver* driver;
@property (nonatomic, readonly) NSMutableArray<SCMRepositoryObserver*>* observers;
@property (nonatomic) id fsEventsObserver;
- (instancetype)initWithURL:(NSURL*)url driver:(SCMDriver*)driver;
- (SCMRepositoryObserver*)addObserver:(void(^)(SCMRepository*))handler;
- (void)removeObserver:(SCMRepositoryObserver*)observer;
@end

@class SCMDirectoryObserver;

@interface SCMDirectory : NSObject
@property (nonatomic, readonly) NSURL* URL;
@property (nonatomic, readonly) SCMRepository* repository;
@property (nonatomic, readonly) SCMRepositoryObserver* repositoryObserver;
@property (nonatomic, readonly) NSMutableArray<SCMDirectoryObserver*>* observers;
- (instancetype)initWithURL:(NSURL*)url;
- (SCMDirectoryObserver*)addObserver:(void(^)(SCMRepository*))handler;
- (void)removeObserver:(SCMDirectoryObserver*)observer;
@end

@interface SCMManager ()
@property (nonatomic, readonly) NSMapTable<NSURL*, SCMRepository*>* repositories;
@property (nonatomic, readonly) NSMapTable<NSURL*, SCMDirectory*>*  directories;
- (SCMDirectory*)directoryAtURL:(NSURL*)url;
@end

// ===========================================
// = Helper classes for observer identifiers =
// ===========================================

@interface SCMRepositoryObserver : NSObject
@property (nonatomic, readonly) void(^handler)(SCMRepository*);
@property (nonatomic) SCMRepository* repository;
- (instancetype)initWithBlock:(void(^)(SCMRepository*))handler;
- (void)remove;
@end

@implementation SCMRepositoryObserver
- (instancetype)initWithBlock:(void(^)(SCMRepository*))handler
{
	if(self = [super init])
		_handler = handler;
	return self;
}

- (void)remove
{
	[self.repository removeObserver:self];
}
@end

@interface SCMDirectoryObserver : NSObject
@property (nonatomic, readonly) void(^handler)(SCMRepository*);
@property (nonatomic) SCMDirectory* directory;
- (instancetype)initWithBlock:(void(^)(SCMRepository*))handler;
- (void)remove;
@end

@implementation SCMDirectoryObserver
- (instancetype)initWithBlock:(void(^)(SCMRepository*))handler
{
	if(self = [super init])
		_handler = handler;
	return self;
}

- (void)remove
{
	[self.directory removeObserver:self];
}
@end

// ===========================================

@implementation SCMRepository
- (instancetype)initWithURL:(NSURL*)url driver:(SCMDriver*)driver
{
	if(self = [super init])
	{
		_URL               = url;
		_driver            = driver;
		_enabled           = [SCMDriver isSCMEnabledForPath:url.path];
		_tracksDirectories = driver.tracksDirectories;
		_noUpdateBefore    = [NSDate distantPast];
		_observers         = [NSMutableArray array];

		if(_enabled == YES)
		{
			[self tryUpdateStatusInBackground];

			__weak SCMRepository* weakSelf = self;
			_fsEventsObserver = [FSEventsManager.sharedInstance addObserverToDirectoryAtURL:url observeSubdirectories:YES usingBlock:^(NSURL* url){
				_noUpdateBefore = [_noUpdateBefore laterDate:[NSDate dateWithTimeIntervalSinceNow:NSApp.isActive ? 0.5 : 3]];
				[weakSelf tryUpdateStatusInBackground];
			}];
		}

		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
	}
	return self;
}

- (void)dealloc
{
	[NSNotificationCenter.defaultCenter removeObserver:self name:NSApplicationDidBecomeActiveNotification object:NSApp];
	[FSEventsManager.sharedInstance removeObserver:_fsEventsObserver];
}

- (void)applicationDidBecomeActive:(NSNotification*)aNotification
{
	if(_updateTimer)
		[self updateStatusInBackground:nil];
}

- (void)tryUpdateStatusInBackground
{
	if(_updating)
	{
		_needsUpdate = YES;
		return;
	}

	NSTimeInterval delayUpdate = [_noUpdateBefore timeIntervalSinceNow];
	if(delayUpdate > 0)
	{
		[_updateTimer invalidate];
		_updateTimer = [NSTimer scheduledTimerWithTimeInterval:delayUpdate target:self selector:@selector(updateStatusInBackground:) userInfo:nil repeats:NO];
	}
	else
	{
		[self updateStatusInBackground:nil];
	}
}

- (void)updateStatusInBackground:(id)sender
{
	[_updateTimer invalidate];
	_updateTimer = nil;
	_needsUpdate = NO;
	_updating    = YES;

	__weak SCMRepository* weakSelf = self;

	NSURL* url = _URL;
	SCMDriver* driver = _driver;

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		SCMStatus* status = [driver statusForDirectory:url.path];
		NSDictionary<NSString*, NSString*>* variables = [driver variablesForDirectory:url.path];

		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf updateStatus:status variables:variables];
		});
	});
}

- (void)updateStatus:(SCMStatus*)status variables:(NSDictionary<NSString*, NSString*>*)variables
{
	_status    = status;
	_variables = variables;
	_hasStatus = YES;

	NSMutableSet<TMFileReference*>* fileReferences = [NSMutableSet set];
	[status.entries enumerateKeysAndObjectsUsingBlock:^(NSString* path, NSNumber* rawStatus, BOOL* stop){
		TMSCMStatus scmStatus = (TMSCMStatus)rawStatus.unsignedIntegerValue;
		if(scmStatus != TMSCMStatusNone)
		{
			TMFileReference* fileReference = [TMFileReference fileReferenceWithURL:[NSURL fileURLWithPath:path]];
			fileReference.SCMStatus = scmStatus;
			[fileReferences addObject:fileReference];
			[_fileReferences removeObject:fileReference];
		}
	}];

	for(TMFileReference* fileReference in _fileReferences)
		fileReference.SCMStatus = TMSCMStatusNone;
	_fileReferences = fileReferences;

	for(SCMRepositoryObserver* observer in [_observers copy])
		observer.handler(self);

	_updating       = NO;
	_noUpdateBefore = [_noUpdateBefore laterDate:[NSDate dateWithTimeIntervalSinceNow:1.5]];
	if(_needsUpdate)
		[self tryUpdateStatusInBackground];
}

- (SCMRepositoryObserver*)addObserver:(void(^)(SCMRepository*))handler
{
	SCMRepositoryObserver* observer = [[SCMRepositoryObserver alloc] initWithBlock:handler];
	observer.repository = self;
	[_observers addObject:observer];

	if(_hasStatus)
		handler(self);

	return observer;
}

- (void)removeObserver:(SCMRepositoryObserver*)observer
{
	[_observers removeObject:observer];
	observer.repository = nil;
}
@end

@implementation SCMDirectory
- (instancetype)initWithURL:(NSURL*)url
{
	if(self = [self init])
	{
		_URL        = url;
		_repository = [SCMManager.sharedInstance repositoryAtURL:url];
		_observers  = [NSMutableArray array];

		__weak SCMDirectory* weakSelf = self;
		_repositoryObserver = [_repository addObserver:^(SCMRepository* repository){
			for(SCMDirectoryObserver* observer in [weakSelf.observers copy])
				observer.handler(repository);
		}];
	}
	return self;
}

- (void)dealloc
{
	[_repository removeObserver:_repositoryObserver];
}

- (SCMDirectoryObserver*)addObserver:(void(^)(SCMRepository*))handler
{
	SCMDirectoryObserver* observer = [[SCMDirectoryObserver alloc] initWithBlock:handler];
	observer.directory = self;
	[_observers addObject:observer];

	if(_repository.hasStatus)
		handler(_repository);

	return observer;
}

- (void)removeObserver:(SCMDirectoryObserver*)observer
{
	[_observers removeObject:observer];
	observer.directory = nil;
}
@end

@implementation SCMManager
+ (instancetype)sharedInstance
{
	static SCMManager* sharedInstance = [self new];
	return sharedInstance;
}

- (instancetype)init
{
	if(self = [super init])
	{
		_directories  = [NSMapTable strongToWeakObjectsMapTable];
		_repositories = [NSMapTable strongToWeakObjectsMapTable];
	}
	return self;
}

- (SCMRepository*)repositoryAtURL:(NSURL*)url
{
	while(url)
	{
		if(SCMRepository* repository = [_repositories objectForKey:url])
			return repository;

		if(SCMDriver* driver = [SCMDriver driverWithInfoForDirectory:url.path])
		{
			SCMRepository* repository = [[SCMRepository alloc] initWithURL:url driver:driver];
			[_repositories setObject:repository forKey:url];
			return repository;
		}

		NSNumber* isVolume;
		if([url getResourceValue:&isVolume forKey:NSURLIsVolumeKey error:nil] && isVolume.boolValue)
			break;

		NSURL* parentURL;
		if(![url getResourceValue:&parentURL forKey:NSURLParentDirectoryURLKey error:nil] || [url isEqual:parentURL])
			break;

		url = parentURL;
	}
	return nil;
}

- (SCMDirectory*)directoryAtURL:(NSURL*)url
{
	SCMDirectory* directory = [_directories objectForKey:url];
	if(!directory)
	{
		directory = [[SCMDirectory alloc] initWithURL:url];
		[_directories setObject:directory forKey:url];
	}
	return directory;
}

- (id)addObserverToRepositoryAtURL:(NSURL*)url usingBlock:(void(^)(SCMRepository*))handler
{
	return [[self repositoryAtURL:url] addObserver:handler];
}

- (void)removeObserver:(id)someObserver
{
	[someObserver remove];
}
@end
