// The framework's public ObjC surface. Deliberately hand-written and unchanged
// by the Phase 4 Swift port: `Preferences` and `TerminalPreferences` are now
// implemented in Swift (@objc(Preferences) / @objc(TerminalPreferences)), but
// consumers in other targets — AppController.mm — keep importing this header and
// need no edits. Cross-target use of a generated *-Swift.h would otherwise mean
// exporting build-directory headers through the include farm.
//
// Do not import this header from ObjC++ inside this framework: the generated
// Preferences-Swift.h declares the same classes and the two would collide.
//
// PreferencesPaneProtocol used to live here. It moved to PreferencesPane.swift:
// it is framework-internal (no target outside Preferences ever referenced it),
// and leaving it here would have forced the Swift side to import this header
// for the protocol and thereby re-collide on the class declarations below.
@interface Preferences : NSWindowController
@property (class, readonly) Preferences* sharedInstance;
@end

// Which folders may set environment variables through their own
// `.tm_properties`. Implemented in FolderTrust.swift as @objc(TMFolderTrust);
// declared here for the same reason the two above are — AppController.mm and
// DocumentWindowController need it across a target boundary, and a generated
// *-Swift.h cannot cross one.
//
// Rule 23: these signatures must match the Swift @objc names exactly, or the
// call compiles and does not dispatch. The Swift side is deliberately named
// `hasBeenAskedAbout(_:)` rather than `hasBeenAsked(about:)` so that the Swift
// spelling and the selector are the same string — this type is reached both
// ways, from AppControllerSupport.mm through this header and from the
// framework's own Swift tests, and two names for one method across a boundary
// is how three of those tests started and never finished.
@interface TMFolderTrust : NSObject
@property (class, readonly) TMFolderTrust* shared;
// Is this path inside a folder the user vouched for? Trust is a prefix: a
// checkout is trusted along with everything in it.
- (BOOL)isTrusted:(NSString*)path;
// Has the user answered for this folder either way? Distinct from -isTrusted:,
// which a subfolder of a trusted root also answers yes to.
- (BOOL)hasBeenAskedAbout:(NSString*)folder;
- (void)trust:(NSString*)folder;
- (void)refuse:(NSString*)folder;
// Not the same as refusing: the folder is asked about again next time.
- (void)forget:(NSString*)folder;
@property (readonly) NSArray<NSString*>* trustedFolders;
@end
