// The ObjC surface the OakTabBarView Swift code sees (Phase 4).
//
// Prelude first (C/C++ layers + Cocoa only, never prelude.m/.mm — see
// CommitWindow-Bridging-Header.h), because the Swift Clang importer compiles
// this standalone with no GCC_PREFIX_HEADER. The prelude supplies <string>,
// which "NSMenuItem Additions.h" needs for its std::string methods.
//
// Deliberately absent: OakTabBarView.h. It declares the OakTabBarView class,
// and the module is also called OakTabBarView, so the generated
// OakTabBarView-Swift.h emits `namespace OakTabBarView` and clang rejects the
// pair. The Swift code defines that class itself (@objc(OakTabBarView)); it
// reaches the delegate/data-source protocols through OakTabBarViewProtocols.h.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

#import <OakAppKit/OakUIConstructionFunctions.h> // OakCreateLabel
// OakTabView builds its close and overflow buttons directly, so it needs the
// class and not just the name. This used to arrive transitively through
// OakUIConstructionFunctions.h, which no longer imports it (rule 21).
#import <OakAppKit/OakRolloverButton.h>
#import <OakAppKit/NSMenuItem Additions.h>       // -setModifiedState:
#import <OakFoundation/OakFoundation.h>          // OakNotEmptyString
#import <TMFileReference/TMFileReference.h>       // +imageForURL:size:

#import "OakAnimatorProxy.h"
#import "OakTabBarViewProtocols.h"
