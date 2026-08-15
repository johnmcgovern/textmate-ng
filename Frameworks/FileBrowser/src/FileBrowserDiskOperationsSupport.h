// The two fragments of FileBrowserDiskOperations that cannot be Swift, kept in
// ObjC++ behind C++-free signatures so the rest of the file can be (rule 25).
//
// 1. The symlink/copy path arithmetic. `path::device`, `path::relative_to` and
//    `path::is_child` are C++ (io/path.h), and the relative-symlink rule they
//    implement — link relative to the destination's directory when source and
//    destination are on the same device, absolute otherwise — is worth moving
//    verbatim rather than re-deriving (rule 6).
//
// 2. -presentError:, which is an *override* of NSResponder's method: it presents
//    the error as a sheet on the file browser's window instead of app-modally.
//    A Swift extension cannot override an inherited method, so this one stays a
//    category on the ObjC++ side. Nothing else here needs to.
// The full declaration, not a forward one: the category below needs the class
// defined, both here and where the bridging header pulls this in.
#import "FileBrowserViewController.h"

@interface FileBrowserDiskOperationsSupport : NSObject
// The destination path for a symbolic link at destURL pointing at srcURL:
// relative to destURL's directory when the two are on the same device (so the
// link survives the pair being moved together), and nil when they are not — the
// caller then links to the source URL itself.
+ (NSString*)symbolicLinkDestinationForURL:(NSURL*)srcURL atURL:(NSURL*)destURL;

// YES when destURL is inside srcURL — copying a directory into itself.
+ (BOOL)isURL:(NSURL*)destURL childOfURL:(NSURL*)srcURL;
@end

@interface FileBrowserViewController (DiskOperationsSupport)
- (BOOL)presentError:(NSError*)error;
@end
