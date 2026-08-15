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
