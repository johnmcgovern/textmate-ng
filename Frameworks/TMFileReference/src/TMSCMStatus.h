// A file's version-control status, in a form that crosses the ObjC boundary.
//
// This exists to close an ABI trap rather than for tidiness. TMFileReference's
// public property used to be typed `scm::status::type` — a C++ unscoped enum
// whose underlying type the compiler picks, and whose largest value (128) fits
// in `unsigned int`, so it is **4 bytes**. Any hand-written ObjC or Swift
// declaration of that property would use `NSUInteger`/`Int`, which is 8. That
// mismatch is not a compile error and not a warning; it is silent corruption of
// whatever sits next to it.
//
// Declaring it NS_OPTIONS(NSUInteger, …) removes the trap at its root: both
// sides now agree on the width because both sides are reading the same ObjC
// declaration. The conversion to and from the C++ enum happens explicitly, at
// the handful of places that still speak C++.
//
// **The two are pinned to each other by t_scm_status.mm, and nothing else.**
// This said "by static_assert in TMFileReference.mm" until 2026-08-05; that file
// was ported to Swift in 8601c693 and the assertions went with it, unnoticed,
// because the runtime table kept passing. Swift has no static_assert over an
// imported C++ enum, so the test *is* the guarantee here — the lesson being that
// a compile-time guard living in a file that may be ported is not permanent.
// Find's equivalent (FFFindOptions) carries both, for exactly this reason.
//
// NS_OPTIONS and not NS_ENUM: this is genuinely a bitmask. Callers test it with
// `status & (modified|added|deleted|conflicted)` (FileItemSCMStatus.mm,
// FileChooser.mm), and `mixed` exists precisely to describe a directory whose
// contents disagree.
//
// Deliberately free of C++ so a Swift bridging header can import it.
#import <Foundation/Foundation.h>

typedef NS_OPTIONS(NSUInteger, TMSCMStatus) {
	TMSCMStatusUnknown     = 0,   // we should always know a file's state, so this should not happen
	TMSCMStatusNone        = 1,   // known and clean
	TMSCMStatusUnversioned = 2,   // neither tracked nor ignored
	TMSCMStatusModified    = 4,
	TMSCMStatusAdded       = 8,   // locally marked for tracking
	TMSCMStatusDeleted     = 16,  // locally marked for deletion
	TMSCMStatusConflicted  = 32,
	TMSCMStatusIgnored     = 64,
	TMSCMStatusMixed       = 128, // a directory whose contents have differing states
};
