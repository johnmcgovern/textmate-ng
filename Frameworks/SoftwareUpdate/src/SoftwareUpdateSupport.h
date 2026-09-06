// The one thing in SoftwareUpdate.mm that Swift cannot express.
//
// os_activity_initiate() is a C *macro* (SDK usr/include/os/activity.h:205) and
// Swift cannot call macros — measured, not assumed: `cannot find
// 'os_activity_initiate' in scope`. Dropping the activity would quietly ungroup
// the update check's log messages in Console, which is exactly the kind of
// invisible change a port should not make, so it gets a shim instead.
//
// One call site, so one single-purpose function rather than a general wrapper.
#import <Foundation/Foundation.h>

void SURunInSoftwareUpdateCheckActivity (void(^block)(void));
