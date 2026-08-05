// The ObjC surface the Find Swift code sees (Phase 4).
//
// Prelude first (C/C++ layers + Cocoa only, never prelude.m/.mm — see
// CommitWindow-Bridging-Header.h), because the Swift Clang importer compiles
// this standalone with no GCC_PREFIX_HEADER.
//
// Deliberately absent: FFResultNode.h, FFDocumentSearch.h and
// FFResultsViewController.h. Each declares a class the Swift defines itself
// (@objc(FFResultNode) and friends); importing them would give those classes two
// declarations and collide with the generated Find-Swift.h. Same arrangement as
// TMFileReference.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

// OakCreateLabel / OakCreateCheckBox / OakCreateNSBoxSeparator /
// OakAddAutoLayoutViewsToSuperview / OakSetupKeyViewLoop, and
// OakIsAlternateKeyOrMouseEvent. Four other frameworks already bridge these; none
// of the three is C++.
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakAppKit/NSColor Additions.h>

// OakDocumentMatch and OakDocument. The header carries C++ members
// (`text::range_t range`, `std::map captures`) that the importer drops; the
// properties Swift actually reads are all ObjC. BundleEditor and CommitWindow
// already bridge this header, so the arrangement is established.
#import <document/OakDocument.h>

// The document enumerator and its kSearch* option keys.
#import <document/OakDocumentController.h>

#import "CommonAncestor.h"
#import "FFFindOptions.h"
#import "FFResultNodeSupport.h"
#import "FFDocumentSearchSupport.h"

// For the two exported notification names, whose definitions stay in ObjC
// because a Swift NSNotification.Name extension emits no C symbol and consumers
// link against one. Declared here rather than importing FFDocumentSearch.h,
// which would collide with the generated Swift header.
extern NSNotificationName const FFDocumentSearchDidReceiveResultsNotification;
extern NSNotificationName const FFDocumentSearchDidFinishNotification;
