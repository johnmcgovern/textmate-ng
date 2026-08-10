// The framework-internal surface of DocumentWindowController.
//
// It exists because OakDocumentControllerWindows.mm — the category on
// OakDocumentController that decides *which* window a document opens in — used
// to live inside DocumentWindowController.mm and reach straight into its file
// statics. Splitting those 171 lines out means naming what they actually depend
// on, which is this.
//
// Written before the Swift port rather than during it, on purpose: this is the
// list of members the port has to keep reachable from ObjC, and having it as a
// header means a mistake is a compile error rather than an unrecognized selector
// at runtime. Same job FindTesting.h did for Find, except this one is production
// code rather than test scaffolding.
//
// Not in default.rave's `headers` line — nothing outside this framework needs it.
#import "DocumentWindowController.h"

@class FileBrowserViewController;
@class KVDB;
@class OakDocument;

@interface DocumentWindowController (Private)

// ==========================================
// = tracking document controller instances =
// ==========================================
//
// Class methods rather than the file statics they replace, so a second file can
// see them. `allControllers` is the live registry keyed by identifier — setting
// a controller's identifier is what adds and removes it, and dropping the last
// reference is what closes the window.
@property (class, readonly) NSMutableDictionary<NSUUID*, DocumentWindowController*>* allControllers;

// Front-to-back, un-miniaturised windows first, filtered to those still in the
// registry. Order matters: "the frontmost scratch window" is the first element.
@property (class, readonly) NSArray<DocumentWindowController*>* sortedControllers;

// The RecentProjects.db behind per-folder session restore.
@property (class, readonly) KVDB* sharedProjectStateDB;

// A document that can be replaced without asking: untitled, unedited, empty, and
// not on disk. Used to decide whether a window counts as "scratch".
+ (BOOL)isDisposableDocument:(OakDocument*)document;

// ==========================================
// = What the window-picking category needs =
// ==========================================

// Readwrite here; the public header exposes it readonly.
@property (nonatomic, readwrite) NSArray<OakDocument*>* documents;
@property (nonatomic, readonly) FileBrowserViewController* fileBrowser;

// The identifier of this window's disposable document, or nil if it has none.
@property (nonatomic, readonly) NSUUID* disposableDocument;

- (void)insertDocuments:(NSArray<OakDocument*>*)documents atIndex:(NSInteger)index selecting:(OakDocument*)selectDocument andClosing:(NSArray<NSUUID*>*)closeDocuments;
- (void)openAndSelectDocument:(OakDocument*)document activate:(BOOL)activateFlag;
- (void)setupControllerForProject:(NSDictionary*)project skipMissingFiles:(BOOL)skipMissing;
- (void)bringToFront;
@end
