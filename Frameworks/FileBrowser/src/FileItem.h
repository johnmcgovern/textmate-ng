// Hand-written ObjC declaration of FileItem, which is implemented in
// FileItem.swift (Phase 4).
//
// It has more consumers than the view classes: FileBrowserViewController,
// FileBrowserDiskOperations, the FileItem(Observer) category in
// FileItemObserver.mm, and — importantly — the two ObjC++ subclasses
// SCMStatusFileItem and MountedVolumesFileItem, which inherit this class and
// override -initWithURL:, -localizedName and -parentURL. All import this header
// unchanged. It must never reach the Swift bridging header — it declares a class
// Swift defines.
//
// The kURLLocation* globals moved to FileItemLocations.h (Swift can't export a
// global); this re-imports it so consumers still get them from FileItem.h.
//
// Nothing checks this against the Swift at build time; a drift is an
// unrecognized selector at runtime, which is what t_file_item.mm guards.
#import "FileItemLocations.h"

@class OakFinderTag;

@interface FileItem : NSObject <QLPreviewItem>
@property (nonatomic) NSURL* URL;

@property (nonatomic, readonly) NSURL* fileReferenceURL;
@property (nonatomic, readonly) NSURL* resolvedURL;
@property (nonatomic, readonly) NSURL* parentURL;
@property (nonatomic, readonly) BOOL isDirectory;

@property (nonatomic, readonly) NSString* displayName;

@property (nonatomic) NSString* localizedName;
@property (nonatomic) NSString* disambiguationSuffix;
@property (nonatomic) NSString* toolTip;

@property (nonatomic, readonly) BOOL canRename;
@property (nonatomic, readonly) BOOL isApplication;

@property (nonatomic, getter=isMissing)          BOOL missing;
@property (nonatomic, getter=isHidden)           BOOL hidden;
@property (nonatomic, getter=hasHiddenExtension) BOOL hiddenExtension;
@property (nonatomic, getter=isSymbolicLink)     BOOL symbolicLink;
@property (nonatomic, getter=isPackage)          BOOL package;
@property (nonatomic, getter=isLinkToPackage)    BOOL linkToPackage;
@property (nonatomic, getter=isLinkToDirectory)  BOOL linkToDirectory;

@property (nonatomic) NSArray<OakFinderTag*>* finderTags;

@property (nonatomic) NSArray<FileItem*>* children;
@property (nonatomic) NSMutableArray<FileItem*>* arrangedChildren;

+ (instancetype)fileItemWithURL:(NSURL*)url;

+ (void)registerClass:(Class)klass forURLScheme:(NSString*)urlScheme;
+ (Class)classForURL:(NSURL*)url;

- (instancetype)initWithURL:(NSURL*)url;
- (void)updateFileProperties;
@end

@interface FileItem (Observer)
+ (id)addObserverToDirectoryAtURL:(NSURL*)url usingBlock:(void(^)(NSArray<NSURL*>*))handler;
+ (void)removeObserver:(id)someObserver;
@end
