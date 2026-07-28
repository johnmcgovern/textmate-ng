// The ObjC surface the BundleEditor Swift code sees (Phase 4).
//
// Prelude first (C/C++ layers + Cocoa only, never prelude.m/.mm — see
// CommitWindow-Bridging-Header.h), because the Swift Clang importer compiles
// this standalone with no GCC_PREFIX_HEADER.
//
// Deliberately absent: BundleEditor.h. It declares the BundleEditor class,
// whose implementation is moving to Swift; importing it here would collide with
// the generated BundleEditor-Swift.h.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

#import <OakAppKit/OakKeyEquivalentView.h>
#import <OakAppKit/OakUIConstructionFunctions.h>

#import "BESupport.h"
