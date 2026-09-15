// The ObjC surface BundlesManager's Swift sees. Compiled standalone by the Swift
// Clang importer — no GCC_PREFIX_HEADER — so includes are explicit.
//
// Deliberately absent: Bundle.h and BundlesManager.h, hand-written declarations
// of classes this module defines in Swift. Importing either would collide with
// the generated -Swift.h (rule 23, rule 43). Swift sees those classes directly;
// only ObjC++ consumers need the headers. BundlesManagerCxx.h and
// InstallBundleItems.h are absent for the other reason: they carry C++.
//
// Prelude first (C/C++ layers + Cocoa only, never prelude.m/.mm — see
// CommitWindow-Bridging-Header.h): OakFoundation.h assumes it, like every
// header in this tree.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

// The user-defaults keys, which stay ObjC++ because Swift can call a global but
// never export one (rule 19).
#import "BundlesManagerConstants.h"

// The C++ model layer and the one-liners, each behind a C++-free face (rule 25).
#import "BundlesIndexCache.h"
#import "BundlesManagerSupport.h"

// OakObserveUserDefaults and the OakUserDefaultsObserver protocol.
#import <OakFoundation/OakFoundation.h>

// The download manager (a hand declaration of a SoftwareUpdate Swift class —
// consuming one across the boundary is fine, only subclassing is not, rule 56)
// and the version comparator Bundle.isCompatible uses.
#import <SoftwareUpdate/OakDownloadManager.h>
#import <SoftwareUpdate/OakCompareVersionStrings.h>
