#import "TMPlugInSupport.h"
#import "TMPlugInAPI.h"
#import <OakSystem/application.h>   // oak::application_t::relaunch
#import <crash/info.h>              // crash_reporter_info_t
#import <io/path.h>                 // path::join / temp
#import <ns/ns.h>

@implementation TMPlugInSupport
+ (NSString*)crashMarkerPathForIdentifier:(NSString*)identifier
{
	return to_ns(path::join(path::temp(), "load_" + to_s(identifier)));
}

+ (id)instantiatePlugInClass:(Class)cl controller:(id)controller identifier:(NSString*)identifier
{
	crash_reporter_info_t info("bad plug-in: %s", [identifier UTF8String]);

	if(id instance = [cl alloc])
	{
		if([instance respondsToSelector:@selector(initWithPlugInController:)])
				return [instance initWithPlugInController:controller];
		else	return [instance init];
	}
	return nil;
}

+ (void)relaunchApplication
{
	oak::application_t::relaunch();
}
@end
