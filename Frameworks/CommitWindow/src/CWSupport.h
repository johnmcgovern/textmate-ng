// The deliberately-ObjC boundary the Swift port sits on (Phase 4 pilot).
// Everything here exists because Swift cannot express it directly:
//
//  * NSConnection/Distributed Objects is unavailable in Swift (not merely
//    deprecated — never exposed), so the client reply channel is wrapped.
//  * `variables` (std::map) and `performBundleItem:` (bundles::item_ptr) are
//    C++-typed ObjC selectors; a Swift class cannot implement them, so
//    CWInteropAdapter conforms/responds on the window controller's behalf.
//  * The engine calls (path::escape, format_string::expand, io::exec,
//    bundles::query) are exposed as ObjC-clean functions — the roadmap's
//    "expose a clean interface at the boundary, then move the caller" recipe.
#import <Cocoa/Cocoa.h>
#import <OakTextView/OakDocumentView.h> // OakTextViewDelegate — CWInteropAdapter conforms

NS_ASSUME_NONNULL_BEGIN

// path::escape — shell-escape a path exactly the way bundle scripts expect
// (byte-identical to what the ObjC++ implementation produced).
NSString* CWEscapedShellPath (NSString* path);

// path::display_name — Finder-style display name for a path.
NSString* CWDisplayNameForPath (NSString* path);

// format_string::expand — expand ${var}-style patterns against variables.
NSString* CWExpandFormatString (NSString* format, NSDictionary<NSString*, NSString*>* variables);

// io::exec via /bin/sh -c. Returns captured stdout, or nil on failure
// (converting io::exec's NULL_STR sentinel to nil at the boundary — never let
// the sentinel cross into Swift).
NSString* _Nullable CWRunShellCommand (NSDictionary<NSString*, NSString*>* environment, NSString* command);

// bundles::query — grammar scope for an SCM's commit-message grammar
// (e.g. "git" → "text.git-commit"), falling back to "text.plain".
NSString* CWCommitMessageGrammarForSCMName (NSString* _Nullable scmName);

// Stands in for the Swift window controller wherever a C++-typed selector can
// arrive: as the text view's delegate (`variables`) and as the window's
// delegate (`performBundleItem:` is dispatched to the key window's delegate by
// AppController Commands.mm).
@interface CWInteropAdapter : NSObject <NSWindowDelegate, OakTextViewDelegate>
@property (nonatomic, copy, nullable) NSString*           projectDirectory;
@property (nonatomic, weak, nullable) OakDocumentView*    documentView;
@property (nonatomic, weak, nullable) NSWindowController* windowController;
@end

// The Distributed-Objects reply to CommitWindowTool. stdoutString nil ⇒ failure
// reply (return code only). Returns NO when the client's port has gone away —
// callers then must not treat the reply as delivered.
@interface CWClientChannel : NSObject
+ (BOOL)replyToClientPortName:(NSString*)portName stdoutString:(NSString* _Nullable)stdoutString returnCode:(int)returnCode continueFlag:(BOOL)continueFlag;
@end

NS_ASSUME_NONNULL_END
