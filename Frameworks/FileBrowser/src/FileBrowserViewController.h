#import "FileBrowserNotifications.h"

// FBOperation and FileBrowserDelegate moved to FileBrowserTypes.h so the Swift
// half can import them without also importing the declaration of a class Swift
// will define. FileBrowserTypes.h is exported alongside this header, and
// imported here, so every consumer of this header is unchanged.
//
// Quoted, not <FileBrowser/FileBrowserTypes.h>: a target's farm include dirs are
// its dependencies', not its own, so the angle form does not resolve from inside
// this framework.
#import "FileBrowserTypes.h"

@class FileItem;

@interface FileBrowserViewController : NSViewController
@property (nonatomic, weak) id <FileBrowserDelegate> delegate;

@property (nonatomic, readonly) NSURL*           URL;
@property (nonatomic, readonly) NSString*        path; // Returns self.URL.filePathURL.path
@property (nonatomic, readonly) NSURL*           directoryURLForNewItems;
@property (nonatomic, readonly) NSArray<NSURL*>* selectedFileURLs;

@property (nonatomic, readonly) NSView*          headerView;
@property (nonatomic, readonly) NSOutlineView*   outlineView;
@property (nonatomic, readonly) id               sessionState;

- (void)setupViewWithState:(id)state;
- (std::map<std::string, std::string>)variables;

- (void)goToURL:(NSURL*)url;
- (void)selectURL:(NSURL*)url withParentURL:(NSURL*)parentURL;
- (NSURL*)newFile:(id)sender;
- (NSURL*)newFolder:(id)sender;

- (void)reload:(id)sender;
- (void)deselectAll:(id)sender;
- (void)toggleShowInvisibles:(id)sender;

- (BOOL)canGoBack;
- (BOOL)canGoForward;

- (void)goBack:(id)sender;
- (void)goForward:(id)sender;
- (void)goToParentFolder:(id)sender;

- (void)goToComputer:(id)sender;
- (void)goToHome:(id)sender;
- (void)goToDesktop:(id)sender;
- (void)goToFavorites:(id)sender;
- (void)goToSCMDataSource:(id)sender;
- (void)orderFrontGoToFolder:(id)sender;

// ======================================================
// = Private (FileBrowserViewController DiskOperations) =
// ======================================================
@property (nonatomic) FileItem* fileItem;
- (NSComparator)itemComparator;
- (NSArray<FileItem*>*)arrangeChildren:(NSArray<FileItem*>*)children inParent:(FileItem*)parentOrNil;
- (void)rearrangeChildrenInParent:(FileItem*)item;
@end

// The (DiskOperations) category that used to be declared here lives in
// FileBrowserDiskOperations.h, and FBOperation itself in FileBrowserTypes.h
// (imported above): Swift implements that category, so the bridging header must
// see the option set but not the method declarations.
