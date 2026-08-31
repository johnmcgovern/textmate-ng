#import "HOFileHandleSchemeSupport.h"
#import <OakSystem/process.h>

NSString* const kHOFileHandleURLScheme   = @"x-txmt-filehandle";
NSString* const kHOLocalFilePathPrefix   = @"/__tm_local__";
NSString* const kHOSyncCommandPathPrefix = @"/__tm_sync__";
NSString* const kHOSyncCommandHeader     = @"X-TextMate-Command";
NSString* const kHOTMFileURLScheme       = @"tm-file";

@implementation HOFileHandleSchemeSupport
+ (void)killProcessGroupInBackground:(pid_t)processGroup
{
	oak::kill_process_group_in_background(processGroup);
}
@end
