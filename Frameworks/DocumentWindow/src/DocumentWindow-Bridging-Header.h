// The ObjC surface the DocumentWindow Swift code sees (Phase 4).
//
// Prelude first (C/C++ layers + Cocoa only, never prelude.m/.mm — see
// CommitWindow-Bridging-Header.h), because the Swift Clang importer compiles
// this standalone with no GCC_PREFIX_HEADER.
//
// Deliberately absent: SelectGrammarViewController.h, and any other header
// declaring a class the Swift defines itself. Importing one would give the class
// two declarations and collide with the generated DocumentWindow-Swift.h — the
// arrangement Find, TMFileReference and BundleEditor all use. That is why
// SelectGrammarResponse.h exists as a separate file: the enum is needed, the
// class declaration beside it is not.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

// OakCreateButton / OakCreateLabel / OakCreateNSBoxSeparator /
// OakAddAutoLayoutViewsToSuperview. Five other frameworks already bridge these.
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakUIConstructionFunctions.h>

// Bundle and BundleGrammar (pure ObjC), and BundlesManager for -installBundles:.
// BundlesManager.h also declares one `bundles::item_ptr*` method, which the
// importer drops — nothing here calls it.
#import <BundlesManager/Bundle.h>
#import <BundlesManager/BundlesManager.h>

// -addAuxiliaryView:atEdge: / -removeAuxiliaryView:, which is how the
// select-grammar strip attaches itself above a document. The header reaches
// OakTextView.h, which is C++-heavy; none of that is used from Swift.
#import <OakTextView/OakDocumentView.h>

// OakNotEmptyString, and the history list behind the command combo box.
#import <OakFoundation/OakFoundation.h>
#import <OakFoundation/OakHistoryList.h>

// kUserDefaultsHTMLOutputPlacementKey, which ProjectLayoutView observes.
#import <Preferences/Keys.h>

#import "SelectGrammarResponse.h"
#import "DWOutputType.h"
#import "DocumentWindowSupport.h"
