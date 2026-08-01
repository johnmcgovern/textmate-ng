// The ObjC surface the BundleEditor Swift code sees (Phase 4).
//
// Prelude first (C/C++ layers + Cocoa only, never prelude.m/.mm — see
// CommitWindow-Bridging-Header.h), because the Swift Clang importer compiles
// this standalone with no GCC_PREFIX_HEADER.
//
// Deliberately absent: BundleEditor.h. It declares the BundleEditor class and
// the module is also called BundleEditor, so the generated
// BundleEditor-Swift.h emits `namespace BundleEditor` and clang rejects the
// pair — the collision this framework recorded first. The Swift defines that
// class itself (@objc(BundleEditor)); its C++-typed public method is supplied
// by an ObjC++ category in BEInterop.mm.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

#import <OakAppKit/OakKeyEquivalentView.h>
#import <OakAppKit/OakUIConstructionFunctions.h>

// Deliberately absent here too: BESwiftClasses.h. It hand-declares the classes
// this framework implements in Swift, for the framework's ObjC++ — letting
// Swift see those declarations as well would be a redefinition of its own
// types.
#import "BEEntry.h"
#import "BESupport.h"

#import <TMBundleModel/TMBundleItem.h>
#import <BundlesManager/BundlesManager.h>
#import <OakAppKit/NSImage Additions.h>
#import <OakAppKit/OakSound.h>
#import <OakCommand/OakCommand.h>          // OakRevealBundleItemNotification
#import <OakFoundation/OakStringListTransformer.h>
#import <TMFileReference/TMFileReference.h>
#import <document/OakDocument.h>

// OakDocumentView pulls in OakTextView.h, which is ObjC++ — the importer parses
// it and omits the members it cannot represent (the std::map delegate method,
// the theme_ptr property), which costs nothing here because the Swift never
// calls them. The one it would otherwise need, -updateEnvironment:forCommand:,
// lives in BEInterop.mm for exactly that reason.
#import <OakTextView/OakDocumentView.h>
