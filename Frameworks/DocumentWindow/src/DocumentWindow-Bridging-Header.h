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

// What DocumentWindowController itself needs. Deliberately absent from this list
// is DocumentWindowController.h: it declares the class, and the class is the
// Swift — importing it would give DocumentWindowController two declarations,
// exactly as importing Find.h into Find's bridging header would. The ObjC++
// category in DocumentWindowSupport.mm imports it instead, which is also why
// that file can call into the Swift but not the other way round.
//
// Several of these headers carry C++ in member signatures — OakDocument's
// scmStatus and variables, OakCommand's -executeWithInput:…, OakTextView's
// -updateEnvironment: — and the importer drops precisely those. That is the same
// bargain Find-Bridging-Header.h makes; the dropped members are reached through
// DocumentWindowSupport.h instead.
#import <document/OakDocument.h>
#import <document/OakDocumentController.h>
#import <OakTabBarView/OakTabBarView.h>
#import <FileBrowser/FileBrowserViewController.h>
#import <HTMLOutputWindow/HTMLOutputWindow.h>
#import <OakFilterList/FileChooser.h>
#import <OakAppKit/OakPasteboard.h>
#import <OakAppKit/NSMenuItem Additions.h>
#import <kvdb/kvdb.h>

// Find, FFSearchTarget and FindDelegate. FindTypes.h keeps the text::range_t in
// -selectRange:inDocument:, which the importer drops — the category implements
// that one.
#import <Find/Find.h>

#import "SelectGrammarResponse.h"
#import "DWOutputType.h"
#import "DWScopeContext.h"
#import "DocumentWindowSupport.h"
