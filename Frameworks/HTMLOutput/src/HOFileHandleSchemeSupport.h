// The two things HOFileHandleScheme.swift cannot own itself.
//
//  1. The scheme's five string constants. Swift can *read* an `extern NSString*
//     const` but can never export one (rule 19), and HTMLOutput.h publishes
//     kHOFileHandleURLScheme to other frameworks — so the definitions stay in
//     ObjC++ permanently, the way OakChoiceMenuConstants.mm does.
//
//  2. oak::kill_process_group_in_background, a C++ free function in a namespace,
//     which Swift cannot call at all (rule 17).
//
// The sync-command protocol is here too, rather than in the hand declaration,
// because Swift needs to name it for the handler's `syncRunner` property while
// HOFileHandleScheme.h has to stay out of the bridging header (rule 43).
#import <Cocoa/Cocoa.h>

extern NSString* const kHOFileHandleURLScheme;
extern NSString* const kHOLocalFilePathPrefix;
extern NSString* const kHOSyncCommandPathPrefix;
extern NSString* const kHOSyncCommandHeader;
extern NSString* const kHOTMFileURLScheme;

// Main-actor, and stated here rather than assumed at the call site: the runner is
// driven from the web view and answers on the main thread, which is what makes it
// safe for the completion handler to touch the scheme task it closes over. Without
// the annotation Swift reads the block as non-isolated and refuses the capture —
// correctly, since nothing else in the type says where it runs.
NS_SWIFT_UI_ACTOR
@protocol HOSyncCommandRunner <NSObject>
- (void)runSyncCommand:(NSString*)aCommand completionHandler:(void(^)(NSString* output, NSString* error, int status))aCompletionHandler;
@end

@interface HOFileHandleSchemeSupport : NSObject
// Kills the command's whole process group. Called when a task is stopped —
// navigating away from a page mid-command has to take the command with it.
+ (void)killProcessGroupInBackground:(pid_t)processGroup;
@end
