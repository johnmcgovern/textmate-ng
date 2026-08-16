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

// FileItemTableCellView: TMFileReference, the icon/closable source it observes.
#import <TMFileReference/TMFileReference.h>

// What FileItem.swift reads (never FileItem.h itself — Swift defines that class):
// the kURLLocation* globals, OakNotEmptyString, and the show-file-extensions
// default key. OakFinderTag.h (above) supplies OakFinderTagManager.
#import "FileItemLocations.h"
#import <OakFoundation/OakFoundation.h>
#import <Preferences/Keys.h>

// The SCM data source (FileItemSCMStatus.swift): SCMManager/SCMRepository — the
// C++-free public header — and the ObjC++ helper holding the scm-map walk.
#import "SCMManager.h"
#import "FileItemSCMStatusSupport.h"

// The directory observers (FileItemObserver.swift): FSEventsManager (C++-free)
// and the ObjC++ helper for the git-deleted-files walk.
#import "FSEventsManager.h"
#import "FileItemObserverSupport.h"

// FBOperation, which FileBrowserDiskOperations.swift's signatures are built
// from. Imported in its own right, not smuggled in through
// FileBrowserViewController.h below, so that when the controller becomes Swift
// only that one line has to go.
#import "FileBrowserTypes.h"

// FileBrowserDiskOperations.swift extends FileBrowserViewController, which is
// still ObjC++, so — uniquely, and only until it is ported — its declaration
// *is* wanted here. The (DiskOperations) category it implements lives in
// FileBrowserDiskOperations.h and is deliberately not imported: Swift defines
// those methods.
#import "FileBrowserViewController.h"
#import "FileBrowserNotifications.h"
#import "FileBrowserDiskOperationsSupport.h"
#import <OakAppKit/OakSound.h>

// The C++ lifted out of FileBrowserViewController ahead of its port — the glob
// filter that decides which children show, and the binary-file test. C++-free
// signatures, so this is importable here.
#import "FileBrowserViewControllerSupport.h"

// The private controller state a peeled-off Swift section reads (readonly —
// see the header). Temporary, and it goes away with the class extension when
// the controller itself becomes Swift.
#import "FileBrowserViewControllerInternal.h"
