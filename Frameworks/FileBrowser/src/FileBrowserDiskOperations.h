// The (DiskOperations) category on FileBrowserViewController, split out of
// FileBrowserViewController.h so that header can go in the Swift bridging
// header.
//
// The two are pulled in opposite directions. The Swift that implements this
// category has to *see* FileBrowserViewController (the class is still ObjC++),
// so the bridging header must import FileBrowserViewController.h — but it must
// not see a declaration of a method the Swift itself defines, which is an
// invalid redeclaration. FBOperation stays in FileBrowserViewController.h: the
// Swift signatures need it, so it has to be on the bridging header's side of
// this line.
//
// Only FileBrowserViewController.mm calls these (measured — nothing outside the
// framework references performOperation: or FBOperation), so it imports this
// header directly and the public header no longer re-exports it.
#import "FileBrowserViewController.h"

@interface FileBrowserViewController (DiskOperations)
- (NSArray<NSURL*>*)performOperation:(FBOperation)op withURLs:(NSDictionary<NSURL*, NSURL*>*)urls unique:(BOOL)makeUnique select:(BOOL)selectDestinationURLs;
- (NSArray<NSURL*>*)performOperation:(FBOperation)op sourceURLs:(NSArray<NSURL*>*)srcURLs destinationURLs:(NSArray<NSURL*>*)destURLs unique:(BOOL)makeUnique select:(BOOL)selectDestinationURLs;
@end
