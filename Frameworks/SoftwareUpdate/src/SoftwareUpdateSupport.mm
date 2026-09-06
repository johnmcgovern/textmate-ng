#import "SoftwareUpdateSupport.h"
#import <os/activity.h>

void SURunInSoftwareUpdateCheckActivity (void(^block)(void))
{
	os_activity_initiate("Software update check", OS_ACTIVITY_FLAG_DEFAULT, block);
}
