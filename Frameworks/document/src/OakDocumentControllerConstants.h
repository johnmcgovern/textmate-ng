// The enumeration option keys, split out of OakDocumentController.h and .mm
// (rule 11): OakDocumentController.h declares a class that becomes Swift, so it
// cannot enter this framework's bridging header (rule 43), and Swift can call a
// global but never export one (rule 19), so the keys keep being defined by an
// ObjC++ translation unit and declared where the Swift can see them.
// OakDocumentController.h imports this, so no consumer changed.
#import <Foundation/Foundation.h>

extern NSString* kSearchFollowDirectoryLinksKey;
extern NSString* kSearchFollowFileLinksKey;
extern NSString* kSearchDepthFirstSearchKey;
extern NSString* kSearchIgnoreOrderingKey;
extern NSString* kSearchExcludeDirectoryGlobsKey;
extern NSString* kSearchExcludeFileGlobsKey;
extern NSString* kSearchExcludeGlobsKey;
extern NSString* kSearchDirectoryGlobsKey;
extern NSString* kSearchFileGlobsKey;
extern NSString* kSearchGlobsKey;
