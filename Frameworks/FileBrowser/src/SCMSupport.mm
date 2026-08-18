#import "SCMSupport.h"
#import "SCMSupportCxx.h"
#import "drivers/api.h"
#import <scm/scm.h>
#import <ns/ns.h>

namespace scm
{
	driver_t* git_driver ();
	driver_t* hg_driver ();
	driver_t* p4_driver ();
	driver_t* svn_driver ();
}

// SCMDriver constructs SCMStatus, whose @implementation is below it; this makes
// the designated initializer visible without exposing it in the public header.
@interface SCMStatus (Private)
- (instancetype)initWithMap:(scm::status_map_t const&)map;
@end

// ==========
// = Driver =
// ==========

@interface SCMDriver ()
{
	scm::driver_t* _driver; // process-static singleton, borrowed
}
@end

@implementation SCMDriver
- (instancetype)initWithDriver:(scm::driver_t*)driver
{
	if(self = [super init])
		_driver = driver;
	return self;
}

+ (BOOL)isSCMEnabledForPath:(NSString*)path
{
	return scm::scm_enabled_for_path(path.fileSystemRepresentation);
}

+ (SCMDriver*)driverWithInfoForDirectory:(NSString*)path
{
	// Order preserved from SCMManager's -repositoryAtURL:.
	static scm::driver_t* const drivers[] = { scm::git_driver(), scm::hg_driver(), scm::p4_driver(), scm::svn_driver() };
	for(scm::driver_t* driver : drivers)
	{
		if(driver && driver->has_info_for_directory(path.fileSystemRepresentation))
			return [[SCMDriver alloc] initWithDriver:driver];
	}
	return nil;
}

- (BOOL)tracksDirectories
{
	return _driver && _driver->tracks_directories();
}

- (SCMStatus*)statusForDirectory:(NSString*)path
{
	return [[SCMStatus alloc] initWithMap:_driver->status(path.fileSystemRepresentation)];
}

- (NSDictionary<NSString*, NSString*>*)variablesForDirectory:(NSString*)path
{
	NSMutableDictionary* variables = [NSMutableDictionary dictionary];
	for(auto pair : _driver->variables(path.fileSystemRepresentation))
		variables[to_ns(pair.first)] = to_ns(pair.second);
	return variables;
}
@end

// ==========
// = Status =
// ==========

@interface SCMStatus ()
{
	scm::status_map_t _map;
}
@end

@implementation SCMStatus
- (instancetype)initWithMap:(scm::status_map_t const&)map
{
	if(self = [super init])
		_map = map;
	return self;
}

- (scm::status_map_t const&)rawStatus
{
	return _map;
}

- (NSDictionary<NSString*, NSNumber*>*)entries
{
	NSMutableDictionary<NSString*, NSNumber*>* entries = [NSMutableDictionary dictionary];
	for(auto const& pair : _map)
	{
		// stringWithFileSystemRepresentation:, not to_ns — the original loop in
		// -updateStatus: built the key this way, and it is the correct decode for
		// a non-UTF8 path.
		NSString* path = [NSFileManager.defaultManager stringWithFileSystemRepresentation:pair.first.data() length:pair.first.size()];
		entries[path] = @((TMSCMStatus)pair.second);
	}
	return entries;
}
@end
