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

// Declared here rather than in the header (see the note there): the header is in
// the bridging header, and a category on FileBrowserViewController needs the
// class declared, which Swift must not see a second time now that it defines the
// class itself.
//
// Nothing sends -presentError: by that declaration — AppKit and
// FileBrowserDiskOperations.swift both reach it as NSResponder's method — so the
// declaration exists only to let this file compile the implementation.
@interface FileBrowserViewController (DiskOperationsSupport)
- (BOOL)presentError:(NSError*)error;
@end

@implementation FileBrowserViewController (DiskOperationsSupport)
// The nil is the point. AppKit declares modalForWindow: nonnull, and the browser
// has no window until it is installed in one; ObjC passes the nil through and
// AppKit falls back to an app-modal alert. That is why this line did not move
// into the Swift class with the rest of the overrides at the flip.
- (BOOL)presentError:(NSError*)error
{
	[self presentError:error modalForWindow:self.view.window delegate:nil didPresentSelector:nullptr contextInfo:nullptr];
	return YES;
}
@end
