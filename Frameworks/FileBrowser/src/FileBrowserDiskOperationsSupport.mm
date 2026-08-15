#import "FileBrowserDiskOperationsSupport.h"
#import "FileBrowserViewController.h"
#import <io/path.h>
#import <ns/ns.h>

@implementation FileBrowserDiskOperationsSupport
+ (NSString*)symbolicLinkDestinationForURL:(NSURL*)srcURL atURL:(NSURL*)destURL
{
	char const* src = srcURL.fileSystemRepresentation;
	char const* dst = destURL.URLByDeletingLastPathComponent.fileSystemRepresentation;
	if(path::device(src) == path::device(dst))
	{
		std::string target = path::relative_to(src, dst);
		return to_ns(target);
	}
	return nil;
}

+ (BOOL)isURL:(NSURL*)destURL childOfURL:(NSURL*)srcURL
{
	return path::is_child(destURL.fileSystemRepresentation, srcURL.fileSystemRepresentation);
}
@end

@implementation FileBrowserViewController (DiskOperationsSupport)
- (BOOL)presentError:(NSError*)error
{
	[self presentError:error modalForWindow:self.view.window delegate:nil didPresentSelector:nullptr contextInfo:nullptr];
	return YES;
}
@end
