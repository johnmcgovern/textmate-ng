// **A hand-written ObjC declaration of a class Swift defines** (rule 23).
// FileBrowserViewController.swift is the implementation; this file is what
// ObjC++ consumers `#import`, and it is deliberately **not** in this framework's
// bridging header — importing both spellings would declare the class twice.
//
// Nothing checks this against the Swift at build time. A drift is an
// unrecognized selector at runtime, which is what the
// -instancesRespondToSelector: tests in t_file_browser_view_controller.mm guard
// (rule 18). Keep the two in step by hand.
//
// The other bridging headers in the repo do import this file — DocumentWindow's
// does, and must, because DocumentWindowController.swift calls -goToURL:,
// -newFile: and the rest. That is fine and is the whole point of the
// arrangement: DocumentWindow does not *define* the class, so for its Swift this
// is just an ObjC class like any other.
#import "FileBrowserNotifications.h"

// FBOperation and FileBrowserDelegate moved to FileBrowserTypes.h so the Swift
// half can import them without also importing the declaration of a class Swift
// defines. FileBrowserTypes.h is exported alongside this header, and imported
// here, so every consumer of this header is unchanged.
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

// The one C++-typed selector, implemented in FileBrowserViewControllerCxx.mm
// rather than in the Swift, and pinned from outside the framework by
// DocumentWindowSupport.mm. The Swift importer drops it when another module's
// bridging header pulls this file in, which is what makes the rest of this
// declaration usable from Swift at all.
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
//
// Not API, and no ObjC++ in this framework calls them any more — the four are
// kept because dropping them from this declaration would be a second change
// riding along inside the flip, and because DocumentWindow's bridging header
// pulls this file in, so removing them changes what its Swift can see.
@property (nonatomic) FileItem* fileItem;
- (NSComparator)itemComparator;
- (NSArray<FileItem*>*)arrangeChildren:(NSArray<FileItem*>*)children inParent:(FileItem*)parentOrNil;
- (void)rearrangeChildrenInParent:(FileItem*)item;
@end

// The (DiskOperations) category that used to be declared here needs no
// declaration at all now: Swift both defines those methods
// (FileBrowserDiskOperations.swift) and calls them, so
// FileBrowserDiskOperations.h is deleted along with the flip. FBOperation itself
// is in FileBrowserTypes.h, imported above.
