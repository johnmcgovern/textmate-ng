// The directory walk behind -enumerateDocumentsAtPaths:options:usingBlock:,
// OakDocumentController's other C++ piece, behind an ObjC face (rule 25):
// a path::glob_list_t built from the option keys, a deque of directories, a
// set of inodes seen, path::entries, and the link handling. Moved verbatim
// (rule 6).
//
// The walk reports the open documents that live in each directory before the
// directory's files, and it asks the controller for those through the block —
// which one the controller answers with depends on the IgnoreOrdering option,
// so the flag is passed along.
#import <Foundation/Foundation.h>

@class OakDocument;

NS_ASSUME_NONNULL_BEGIN

typedef NSArray<OakDocument*>* _Nonnull (^OakDocumentWalkOpenDocuments)(NSString* directory, BOOL ignoreOrdering);

@interface OakDocumentWalk : NSObject
+ (void)enumerateDocumentsAtPaths:(NSArray<NSString*>*)items options:(nullable NSDictionary*)someOptions openDocumentsInDirectory:(OakDocumentWalkOpenDocuments)openDocuments usingBlock:(void(^)(OakDocument* document, BOOL* stop))block NS_SWIFT_NAME(enumerateDocuments(atPaths:options:openDocumentsInDirectory:using:));
@end

NS_ASSUME_NONNULL_END
