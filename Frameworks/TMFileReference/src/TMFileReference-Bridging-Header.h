// The ObjC surface the TMFileReference Swift code sees (Phase 4).
//
// Prelude first (C/C++ layers + Cocoa only, never prelude.m/.mm — see
// CommitWindow-Bridging-Header.h), because the Swift Clang importer compiles
// this standalone with no GCC_PREFIX_HEADER.
//
// Deliberately absent: TMFileReference.h. It declares the TMFileReference
// class and the module is also called TMFileReference, so the generated
// TMFileReference-Swift.h would emit `namespace TMFileReference` and clang
// would reject the pair — the collision BundleEditor recorded first. The Swift
// defines that class itself (@objc(TMFileReference)); TMSCMStatus.h carries the
// status type, which is why it is a header of its own rather than part of
// TMFileReference.h.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

#import "TMSCMStatus.h"
#import "TMFRSupport.h"

// For TMURLWillCloseNotification, whose definition stays in ObjC because it is
// an exported C symbol. Declaring it here rather than importing
// TMFileReference.h, which would collide with the generated Swift header.
extern NSNotificationName const TMURLWillCloseNotification;
