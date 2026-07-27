// Phase 4 pilot: the ObjC/ObjC++ surface the CommitWindow Swift code sees.
//
// Compiled standalone by the Swift Clang importer (no GCC_PREFIX_HEADER), so
// the prelude comes first — but only its C and C++ layers plus Cocoa, NOT
// prelude.m/.mm: those pull WebKit/Quartz/AddressBook through the importer on
// every Swift compile, and nothing exposed here needs them. The headers below
// are ObjC++ (OakDocumentView.h reaches theme/command/scm headers); the
// importer parses them because SWIFT_OBJC_INTEROP_MODE=objcxx.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakTextView/OakDocumentView.h>
#import <document/OakDocument.h>

#import "CommitWindow.h"
#import "CWSupport.h"
