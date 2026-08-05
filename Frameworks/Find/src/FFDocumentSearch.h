#import "FFFindOptions.h"

extern NSNotificationName const FFDocumentSearchDidReceiveResultsNotification;
extern NSNotificationName const FFDocumentSearchDidFinishNotification;

@interface FFDocumentSearch : NSObject
// Set up the search with these options
@property (nonatomic, copy) NSString* searchString;
@property (nonatomic) FFFindOptions options;

@property (nonatomic) NSArray* paths;

// Required, despite reading as optional: an empty file-glob list matches *no*
// files, so leaving this nil produces an instant, entirely empty search rather
// than an unfiltered one. Pinned by t_document_search.mm.
@property (nonatomic) NSString* glob;

@property (nonatomic) BOOL searchFolderLinks;
@property (nonatomic) BOOL searchFileLinks;
@property (nonatomic) BOOL searchBinaryFiles;
@property (nonatomic) BOOL searchHiddenFolders;

// Start the search, observing the currentPath, and prematurely stop it if desired.
- (void)start;
- (void)stop;

@property (nonatomic, readonly) NSString*      currentPath;
@property (nonatomic, readonly) NSTimeInterval searchDuration;
@property (nonatomic, readonly) NSUInteger     scannedFileCount;
@property (nonatomic, readonly) NSUInteger     scannedByteCount;
@end
