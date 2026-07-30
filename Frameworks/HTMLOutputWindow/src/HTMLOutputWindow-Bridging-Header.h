// The ObjC surface the HTMLOutputWindow Swift code sees (Phase 4).
//
// Prelude first (C/C++ layers + Cocoa only, never prelude.m/.mm — see
// CommitWindow-Bridging-Header.h), because the Swift Clang importer compiles
// this standalone with no GCC_PREFIX_HEADER.
//
// <HTMLOutput/HTMLOutput.h> declares OakHTMLOutputView, whose
// -loadRequest:environment:autoScrolls: takes a std::map. That is fine here: the
// importer parses the header because SWIFT_OBJC_INTEROP_MODE=objcxx, and simply
// omits the members it cannot represent. This controller never calls that one —
// it uses -init, -stopLoadingWithUserInteraction:completionHandler:,
// -isRunningCommand, and two KVC key paths — so nothing is lost.
//
// Deliberately absent: HTMLOutputWindow.h. It declares the class this module
// implements in Swift, so importing it would collide with the generated
// HTMLOutputWindow-Swift.h declarations.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

#import <HTMLOutput/HTMLOutput.h>
