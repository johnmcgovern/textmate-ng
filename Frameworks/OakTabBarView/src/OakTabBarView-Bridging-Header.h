// The ObjC surface the OakTabBarView Swift code sees (Phase 4).
//
// Prelude first (C/C++ layers + Cocoa only, never prelude.m/.mm — see
// CommitWindow-Bridging-Header.h), because the Swift Clang importer compiles
// this standalone with no GCC_PREFIX_HEADER.
//
// Deliberately absent: OakTabBarView.h. It declares the OakTabBarView class,
// and the module is also called OakTabBarView, so the generated
// OakTabBarView-Swift.h emits `namespace OakTabBarView` and clang rejects the
// pair. Swift reaches those types through OTBSwiftClasses.h instead.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

#import <OakFoundation/OakFoundation.h>

#import "OakAnimatorProxy.h"
#import "OTBObjCClasses.h"
