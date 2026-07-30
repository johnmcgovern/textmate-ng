// The ObjC surface the BundleMenu Swift code sees (Phase 4).
//
// Prelude first (C/C++ layers + Cocoa only, never prelude.m/.mm — see
// CommitWindow-Bridging-Header.h), because the Swift Clang importer compiles
// this standalone with no GCC_PREFIX_HEADER. The prelude also supplies
// <string>, which "NSMenuItem Additions.h" needs for its std::string methods —
// the importer parses those and omits the ones it cannot represent, which is
// exactly why -setInactiveKeyEquivalent:/-setTabTrigger: were added alongside
// them.
//
// Deliberately absent: BundleMenu.h and TMBundleModelCxx.h. Both declare C++,
// and this framework's whole point is that the Swift never sees any: it works
// in TMBundleItem/TMScopeContext, and BundleMenuSupport.mm does the one
// conversion the framework's C++-typed public API still needs.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

#import <OakAppKit/NSMenuItem Additions.h> // -setInactiveKeyEquivalent: / -setTabTrigger:
#import <TMBundleModel/TMBundleItem.h>
#import <TMBundleModel/TMScopeContext.h>
