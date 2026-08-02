// The ObjC surface the CrashReporter Swift code sees (Phase 4).
//
// Prelude first (C/C++ layers + Cocoa only, never prelude.m/.mm — see
// CommitWindow-Bridging-Header.h), because the Swift Clang importer compiles
// this standalone with no GCC_PREFIX_HEADER.
//
// Deliberately absent: CrashReporter.h. It declares the CrashReporter class and
// the module is also called CrashReporter, so the generated
// CrashReporter-Swift.h would emit `namespace CrashReporter` and clang would
// reject the pair — the collision BundleEditor recorded first. The Swift defines
// that class itself, as @objc(CrashReporter).
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

#import <Preferences/Keys.h> // kUserDefaultsDisableCrashReportingKey, …

#import "CRSupport.h"
