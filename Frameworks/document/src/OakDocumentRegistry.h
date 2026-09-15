// The document registry — OakDocumentController's C++ model layer, behind an
// ObjC face (rule 25): three maps keyed by identifier, by path and by inode,
// under one mutex, holding each document weakly. Moved verbatim from
// OakDocumentController.mm (rule 6), including the inode check for the magic
// value zero-length files share on FAT volumes.
//
// The lookups that must be atomic with what follows them are here whole:
// -documentForPath: looks up by path, then by inode, then creates and adds,
// under one lock, as the original did — the walk calls it from a background
// queue while the main thread does the same.
#import <Foundation/Foundation.h>

@class OakDocument;

NS_ASSUME_NONNULL_BEGIN

@interface OakDocumentRegistry : NSObject
// The document for a path, creating and registering one if none is known;
// nil path means a new untitled document.
- (OakDocument*)documentForPath:(nullable NSString*)aPath;
- (nullable OakDocument*)documentForIdentifier:(NSUUID*)anUUID;

- (void)addDocument:(OakDocument*)aDocument;
- (void)removeDocument:(OakDocument*)aDocument;
- (void)updateDocument:(OakDocument*)aDocument;

// The lowest number no untitled document holds.
- (NSUInteger)firstAvailableUntitledCount;

// A snapshot of every registered document still alive.
- (NSArray<OakDocument*>*)documents;
@end

NS_ASSUME_NONNULL_END
