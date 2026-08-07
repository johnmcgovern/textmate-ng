// The ObjC surface the Find Swift code sees (Phase 4).
//
// Prelude first (C/C++ layers + Cocoa only, never prelude.m/.mm — see
// CommitWindow-Bridging-Header.h), because the Swift Clang importer compiles
// this standalone with no GCC_PREFIX_HEADER.
//
// Deliberately absent: Find.h, FFResultNode.h, FFDocumentSearch.h and
// FFResultsViewController.h. Each declares a class the Swift defines itself
// (@objc(Find), @objc(FFResultNode) and friends); importing them would give those
// classes two declarations and collide with the generated Find-Swift.h. Same
// arrangement as TMFileReference.
//
// FindTypes.h is here in Find.h's place: it carries FFSearchTarget, FindDelegate
// and FindMatch, which the Swift genuinely needs, without carrying
// `@interface Find`. That split is the whole reason FindTypes.h exists.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

// OakCreateLabel / OakCreateCheckBox / OakCreateNSBoxSeparator /
// OakAddAutoLayoutViewsToSuperview / OakSetupKeyViewLoop, and
// OakIsAlternateKeyOrMouseEvent. Four other frameworks already bridge these; none
// of the three is C++.
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakAppKit/NSColor Additions.h>

// -setIconForFile:, for the folder rows of the “In:” pop-up. The header also
// declares three std::string-typed selectors, which the importer drops; the two
// ObjC-clean spellings next to them exist for exactly that reason.
#import <OakAppKit/NSMenuItem Additions.h>

// The find and replace pasteboards, their change notification, and the option
// keys an entry carries. OakPasteboardEntry also has a find::options_t property
// the importer drops — Find reads the three BOOLs beside it instead.
#import <OakAppKit/OakPasteboard.h>
#import <OakAppKit/OakTransitionViewController.h>

// OakNotEmptyString, OakObserveUserDefaults and the OakUserDefaultsObserver
// protocol Find conforms to.
#import <OakFoundation/OakFoundation.h>
#import <OakFoundation/OakHistoryList.h>

// OakDocumentMatch and OakDocument. The header carries C++ members
// (`text::range_t range`, `std::map captures`) that the importer drops; the
// properties Swift actually reads are all ObjC, and everything downstream of the
// two dropped ones goes through FindSupport.h. BundleEditor and CommitWindow
// already bridge this header, so the arrangement is established.
#import <document/OakDocument.h>

// The document enumerator and its kSearch* option keys.
#import <document/OakDocumentController.h>

#import "CommonAncestor.h"
#import "FFFindAction.h"
#import "FFFindOptions.h"
#import "FFResultNodeSupport.h"
#import "FFDocumentSearchSupport.h"
#import "FindTypes.h"
#import "FindSupport.h"

// This framework's remaining ObjC++ view controllers, which Find owns and drives.
#import "FFStatusBarViewController.h"
#import "FFTextFieldViewController.h"
#import "FFFolderMenu.h"

// For the two exported notification names, whose definitions stay in ObjC
// because a Swift NSNotification.Name extension emits no C symbol and consumers
// link against one. Declared here rather than importing FFDocumentSearch.h,
// which would collide with the generated Swift header.
extern NSNotificationName const FFDocumentSearchDidReceiveResultsNotification;
extern NSNotificationName const FFDocumentSearchDidFinishNotification;
