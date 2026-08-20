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

// The SCM data source (FileItemSCMStatus.swift): the ObjC++ helper holding the
// scm-map walk. **SCMManager.h is deliberately absent as of its port** — Swift
// defines SCMManager/SCMRepository now (SCMManager.swift), so importing the
// hand-written declaration here would give each two, per this file's opening note.
// Its ObjC++ consumers (FileItemSCMStatusSupport.mm, FileItemObserverSupport.mm)
// import that header directly, and so does the test bundle; the support headers
// below name SCMRepository only through a forward declaration. SCMSupport.h (the
// C++-free SCMDriver / SCMStatus boundary) still comes in here — SCMManager.swift
// needs it, and it used to arrive through SCMManager.h.
#import "SCMSupport.h"
#import "FileItemSCMStatusSupport.h"

// FSEventStream, which FSEventsManager.swift owns one of. This is the ObjC shell
// 3f6bcc0c wrapped the std::shared_ptr<fs_events_t> in, kept C++-free for
// exactly this import — see its header comment.
#import "FSEventStream.h"

// The ObjC++ helper for the git-deleted-files walk. **FSEventsManager.h is
// deliberately absent as of its port** — Swift defines that class now
// (FSEventsManager.swift), so importing the hand-written declaration here would
// give it two, per this file's opening note. Its ObjC++ caller (SCMManager.mm)
// imports that header directly, and so does the test bundle.
#import "FileItemObserverSupport.h"

// FBOperation, which FileBrowserDiskOperations.swift's signatures are built
// from. Imported in its own right, not smuggled in through
// FileBrowserViewController.h below, so that when the controller becomes Swift
// only that one line has to go.
#import "FileBrowserTypes.h"

// **FileBrowserViewController.h is deliberately absent, as of the flip.** Swift
// defines that class now (FileBrowserViewController.swift), so importing the
// hand-written declaration here would give it two — exactly the rule this file's
// opening note states, and the one line the whole header split was arranged to
// make removable. FileBrowserViewControllerInternal.h and FileBrowserActions.h
// went with it: both existed only to let peeled sections and the .mm reach
// across the ObjC++/Swift line inside this class, and there is no line left.
#import "FileBrowserNotifications.h"
#import "FileBrowserDiskOperationsSupport.h"
#import <OakAppKit/OakSound.h>

// The C++ lifted out of FileBrowserViewController ahead of its port — the glob
// filter that decides which children show, the binary-file test, the bundle
// action-menu items and the rest. C++-free signatures, so this is importable
// here, and it stays ObjC++ permanently.
#import "FileBrowserViewControllerSupport.h"

// OakOpenWithMenuDelegate, which -openWithMenuAction: sends
// -openDocumentURLs:withApplicationURL:, and OakZoomingIcon for the open
// animation. Both arrived with the controller's own translation; neither was
// needed while those methods were ObjC++.
#import <OakAppKit/OakOpenWithMenu.h>
#import <OakAppKit/OakZoomingIcon.h>

// -updateTitle: and -setDynamicTitle:, which the peeled -validateMenuItem: uses
// to retitle menu items. The header carries C++-typed selectors alongside them,
// which is fine here for the same reason it is fine in BundleMenu's bridging
// header: the importer drops what it cannot express and leaves the rest.
#import <OakAppKit/NSMenuItem Additions.h>
