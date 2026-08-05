// The ObjC surface the Find Swift code sees (Phase 4).
//
// Prelude first (C/C++ layers + Cocoa only, never prelude.m/.mm — see
// CommitWindow-Bridging-Header.h), because the Swift Clang importer compiles
// this standalone with no GCC_PREFIX_HEADER.
//
// Deliberately absent: FFResultNode.h. It declares the FFResultNode class,
// which the Swift defines itself (@objc(FFResultNode)); importing it would give
// the class two declarations and collide with the generated Find-Swift.h. Same
// arrangement as TMFileReference.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

// OakDocumentMatch and OakDocument. The header carries C++ members
// (`text::range_t range`, `std::map captures`) that the importer drops; the
// properties Swift actually reads are all ObjC. BundleEditor and CommitWindow
// already bridge this header, so the arrangement is established.
#import <document/OakDocument.h>

#import "FFResultNodeSupport.h"
