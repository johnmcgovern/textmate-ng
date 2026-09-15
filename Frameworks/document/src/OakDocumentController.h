// Hand-declared (rule 23): this class is defined in OakDocumentController.swift,
// except for the two window wrappers below the category line, which are
// OakDocumentControllerCxx.mm's (rule 37) and DocumentWindow's.
//
// It must stay out of this framework's bridging header, where it would collide
// with the generated document-Swift.h (rule 43). Its ObjC++ consumers and the
// four bridging headers that import it are unchanged. Nothing checks this file
// against the Swift at build time; the selectors are pinned by
// tests/t_document_controller.mm (rule 18).
#import <text/types.h>
#import "OakDocumentControllerConstants.h"

@class OakDocument;

@interface OakDocumentController : NSObject
@property (class, readonly) OakDocumentController* sharedInstance;

- (OakDocument*)untitledDocument;
- (OakDocument*)documentWithPath:(NSString*)aPath;
- (OakDocument*)findDocumentWithIdentifier:(NSUUID*)anUUID;
- (NSArray<OakDocument*>*)documents;
- (NSArray<OakDocument*>*)openDocuments;

- (NSInteger)lruRankForDocument:(OakDocument*)aDocument;
- (void)didTouchDocument:(OakDocument*)aDocument;

- (void)enumerateDocumentsAtPath:(NSString*)aDirectory options:(NSDictionary*)someOptions usingBlock:(void(^)(OakDocument* document, BOOL* stop))block;
- (void)enumerateDocumentsAtPaths:(NSArray*)items options:(NSDictionary*)someOptions usingBlock:(void(^)(OakDocument* document, BOOL* stop))block;

// For use by OakDocument
- (void)register:(OakDocument*)aDocument;
- (void)unregister:(OakDocument*)aDocument;
- (void)update:(OakDocument*)aDocument;
- (NSUInteger)firstAvailableUntitledCount;

// Wrappers for OakDocumentWindowControllerCategory
- (void)showDocument:(OakDocument*)aDocument;
- (void)showDocument:(OakDocument*)aDocument inProject:(NSUUID*)identifier bringToFront:(BOOL)bringToFront;
@end

@interface OakDocumentController (OakDocumentWindowControllerCategory)
- (void)showDocument:(OakDocument*)aDocument andSelect:(text::range_t const&)selection inProject:(NSUUID*)identifier bringToFront:(BOOL)bringToFront;
- (void)showDocuments:(NSArray<OakDocument*>*)someDocument;
- (void)showFileBrowserAtPath:(NSString*)aPath;
@end
