// The types FileBrowser's public interface is built from, split out of
// FileBrowserViewController.h so the Swift half can import them. The FindTypes.h
// arrangement, one framework later.
//
// The split exists for one reason: FileBrowserViewController.h declares
// `@interface FileBrowserViewController`, and that class is the last port left
// here. Once Swift defines it, a bridging header that imported
// FileBrowserViewController.h would declare the class twice — but the Swift
// genuinely needs FBOperation (FileBrowserDiskOperations.swift's signatures are
// built from it) and will need FileBrowserDelegate (the `delegate` property), so
// those move here and the bridging header imports this file instead.
//
// Both headers are exported (see default.rave), and FileBrowserViewController.h
// imports this one, so no consumer outside the framework changed:
// `#import <FileBrowser/FileBrowserViewController.h>` still brings in
// everything it used to. That matters more here than it did for Find —
// DocumentWindow reaches this framework from three files, one of which is its
// *bridging header*, so DocumentWindowController.swift sees FileBrowserDelegate
// (it declares `@preconcurrency FileBrowserDelegate`) and the controller class
// through these declarations.
//
// No Foundation import, matching this framework's other public headers, which
// lean on the PCH.
@class FileBrowserViewController;

@protocol FileBrowserDelegate
- (void)fileBrowser:(FileBrowserViewController*)fileBrowser openURLs:(NSArray*)someURLs;
- (void)fileBrowser:(FileBrowserViewController*)fileBrowser closeURL:(NSURL*)anURL;
@end

typedef NS_OPTIONS(NSUInteger, FBOperation) {
	FBOperationLink      = 0x0001,
	FBOperationCopy      = 0x0002,
	FBOperationDuplicate = 0x0004,
	FBOperationMove      = 0x0008,
	FBOperationRename    = 0x0010,
	FBOperationTrash     = 0x0020,
	FBOperationNewFile   = 0x0040,
	FBOperationNewFolder = 0x0080,
};
