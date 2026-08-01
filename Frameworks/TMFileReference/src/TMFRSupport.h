// The one thing in TMFileReference that Swift cannot reach (Phase 4).
//
// Not exported — this is for the framework's own Swift, through the bridging
// header.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// The badge drawn over a symbolic link's icon, still only reachable through
// Carbon's IconRef API.
//
// GetIconRef, ReleaseIconRef and -[NSImage initWithIconRef:] all import into
// Swift fine; `kOnSystemDisk` does not — it is an old <CarbonCore/Files.h>
// constant that Swift's importer drops, and hardcoding its −32768 across the
// boundary is exactly the kind of magic number that rots silently when the SDK
// moves. So the call stays here, where the constant is in scope.
//
// nil when the system has no such icon, which the caller treats as "draw no
// badge" rather than as an error.
NSImage* _Nullable TMAliasBadgeImage (void);

NS_ASSUME_NONNULL_END
