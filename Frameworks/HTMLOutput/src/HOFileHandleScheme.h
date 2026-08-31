// Hand-declared (rule 23): these classes are defined in HOFileHandleScheme.swift.
//
// This file must not appear in HTMLOutput-Bridging-Header.h, where it would
// collide with the generated HTMLOutput-Swift.h (rule 43). The scheme's string
// constants, the sync-command protocol and the one C++ call moved to
// "HOFileHandleSchemeSupport.h" so Swift can still see them, and the
// stream rewriter to "HOLocalURLRewriter.h".
//
// The prose explaining *why* this scheme exists — the same-origin rewrite, the
// synchronous XMLHttpRequest bridge, and why the file handle is parked in a
// registry rather than read off the request — is in HOFileHandleSchemeSupport.h,
// beside the constants it describes.
#import <WebKit/WebKit.h>
#import "HOFileHandleSchemeSupport.h"
#import "HOLocalURLRewriter.h"

// Main thread only.
@interface HOFileHandleJob : NSObject
@property (nonatomic, readonly) NSFileHandle* fileHandle;
@property (nonatomic, readonly) pid_t processIdentifier;
@end

@interface HOFileHandleRegistry : NSObject
@property (class, readonly) HOFileHandleRegistry* sharedInstance;
- (void)registerJobForURL:(NSURL*)aURL fileHandle:(NSFileHandle*)aFileHandle processIdentifier:(pid_t)aProcessIdentifier;
- (HOFileHandleJob*)claimJobForURL:(NSURL*)aURL; // one-shot: also removes the entry
- (void)discardJobForURL:(NSURL*)aURL;
@end

@interface HOFileHandleSchemeHandler : NSObject <WKURLSchemeHandler>
// Set while the JavaScript API is installed; nil when the command opted out via
// disableJavaScriptAPI, which also disables the synchronous bridge.
@property (nonatomic, weak) id <HOSyncCommandRunner> syncRunner;
@end
