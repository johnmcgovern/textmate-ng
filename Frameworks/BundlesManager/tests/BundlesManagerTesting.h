// The surface of BundlesManager that the tests drive but consumers do not need.
//
// In its own header because ide/gen_xctest.rb wraps each test file's body in
// `namespace <basename>` and an ObjC declaration may only appear at global
// scope — but every #import is hoisted, so a declaration reached through one is
// fine. Same arrangement as Find/tests/FindTesting.h.
//
// Declaring these here is not a back door: both exist today, and this file is
// what pins their ObjC spellings. A port that renamed one would stop compiling
// here rather than failing silently at runtime (rule 64).
#import "../src/BundlesManager.h"
#import "../src/Bundle.h"

@interface BundlesManager (Testing)
// Readwrite for the tests only; BundlesManager.h says readonly. The Preferences
// pane binds an NSArrayController's content to this key, which is what the KVO
// pin drives through.
@property (nonatomic) NSArray<Bundle*>* bundles;

// BundlesFromIndex, the parser that turns the remote index, the local index and
// the Bundles directory into the model. Pure over its three paths, which is
// what makes it the piece that can be pinned exactly before the port.
+ (NSArray<Bundle*>*)bundlesFromRemoteIndexAtPath:(NSString*)remoteIndexPath localIndexPath:(NSString*)localIndexPath installDirectory:(NSString*)installDir previousBundles:(NSDictionary<NSUUID*, Bundle*>*)cache;
@end

// textSummary is not in Bundle.h: nothing calls it by name. The Preferences
// pane binds a table column to "arrangedObjects.textSummary", which is why it
// exists and why its spelling is pinned here.
@interface Bundle (Testing)
@property (nonatomic, readonly) NSString* textSummary;
@end
