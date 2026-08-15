// The ObjC surface FileBrowser's Swift code sees (Phase 4).
//
// Prelude first (the C/C++ layers + Cocoa only, never prelude.m/.mm — see
// CommitWindow-Bridging-Header.h), because the Swift Clang importer compiles
// this standalone with no GCC_PREFIX_HEADER.
//
// Deliberately absent: any header that declares a class the Swift defines
// itself — OFBHeaderView.h and the rest as they port — since importing one would
// give the class two declarations and collide with the generated
// FileBrowser-Swift.h. The framework's ObjC++ reaches those hand-written headers
// directly instead.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

// OakCreateNSBoxSeparator / OakAddAutoLayoutViewsToSuperview /
// OakSetupKeyViewLoop / OakCreateActionPopUpButton, and the NSVisualEffectView
// chrome the header/actions views are built from.
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakUIConstructionFunctions.h>

// +[NSImage imageNamed:inSameBundleAsClass:], for OFBActionsView's bundle-local
// button images (SearchTemplate, FavoritesTemplate, SCMTemplate).
#import <OakAppKit/NSImage Additions.h>

// The outline view's delegate protocol (its class is defined in Swift, so only
// the protocol half is safe to import here) and the C++ key-equivalent helper it
// calls. Both are C++-free headers.
#import "FileBrowserOutlineViewDelegate.h"
#import "FileBrowserOutlineViewKeyBindings.h"

// OakFinderTag / OakFinderTagManager and OakRolloverButton (with its rollover
// notification names), for OFBFinderTagsChooser's swatch buttons.
#import <OakAppKit/OakFinderTag.h>
#import <OakAppKit/OakRolloverButton.h>

// FileItemTableCellView: TMFileReference (the icon/closable source it observes)
// and the FileItem(EditingName) binding support (which pulls in FileItem itself —
// still ObjC, so importable here for now).
#import <TMFileReference/TMFileReference.h>
#import "FileItemEditingName.h"
