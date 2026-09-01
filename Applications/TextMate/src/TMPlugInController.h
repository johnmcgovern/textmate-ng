// Hand-written ObjC declaration of the Swift TMPlugInController
// (TMPlugInController.swift), for AppController.mm and for plug-ins. Kept out of
// the bridging header — Swift defines the class — and out of any .mm that also
// imports TextMate-Swift.h (rule 43). The protocols moved to TMPlugInAPI.h,
// which the bridging header *does* take; this include keeps the public header
// whole for anything that was importing it.
#import "TMPlugInAPI.h"

@interface TMPlugInController : NSObject <TMPlugInController>
@property (class, readonly) TMPlugInController* sharedInstance;
- (void)loadAllPlugIns:(id)sender;
- (CGFloat)version;
- (void)installPlugInAtPath:(NSString*)aPath;
@end
