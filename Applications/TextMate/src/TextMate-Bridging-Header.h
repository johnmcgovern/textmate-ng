// Phase 3 (Swift interop foundation): the ObjC surface Swift sees. The Swift
// Clang importer compiles this standalone — no GCC_PREFIX_HEADER — so includes
// must be explicit. Deliberately NOT the full prelude: prelude.mm drags in
// WebKit/Quartz/AddressBook, which the C++-interop importer would re-parse on
// every Swift compile, and the headers exposed here need only Foundation and
// <string>. (The TMText module shim, whose <oak/oak.h> chain genuinely assumes
// the prelude, does include it — see build_swift_module_farm in
// ide/seed_xcodeproj.rb.) Parsed as ObjC++ via SWIFT_OBJC_INTEROP_MODE=objcxx.
#import <Foundation/Foundation.h>
#include <string>
#include <OakFoundation/OakFoundation.h>

// The bundle list the About window's Bundles page is built from — summarised, not
// the real thing. <BundlesManager/BundlesManager.h> cannot come in here: it pulls
// plist/, oak/algorithm.h and boost, which this header's deliberately-minimal
// prelude cannot parse. See AboutBundlesSupport.h.
#include "AboutBundlesSupport.h"

// The plug-in protocols. TMPlugInController.swift conforms to the first and
// hands itself to plug-ins as `id <TMPlugInController>`; the class declaration
// in TMPlugInController.h stays out of here (rule 43).
#include "TMPlugInAPI.h"

// The extracted C++ boundary the controller calls. Foundation-only, like
// AboutBundlesSupport.h.
#include "TMPlugInSupport.h"

// AppKit, for the Swift menu construction in MainMenu.swift. The header above
// this line needs only Foundation; NSMenu does not.
#import <Cocoa/Cocoa.h>

// +delegateUsingSelector:, which MBMenuItem's `.delegate` field used to reach.
// This is the only part of MenuBuilder a bridging header can take —
// MenuBuilder.h itself is `typedef std::vector<MBMenuItem> MBMenu` and cannot
// come in here, which is the whole reason MainMenu.swift restates the builder.
#import <MenuBuilder/MBMenuDelegate.h>

// ============================================================================
// = The AppController flip
// ============================================================================
//
// AppController.swift and its two extensions call into these. Every one was
// probed against this header, compiled standalone at the project's own
// -std=c++2a, before being added (rule 55, rule 62) — several of them declare
// C++-typed methods that the importer simply drops (rule 17), which is fine;
// what matters is that the header parses.
//
// AppController.h itself is deliberately absent: it is the hand-written ObjC
// declaration of a Swift class and would collide with the generated
// TextMate-Swift.h (rule 23, rule 43).

// The app's own extracted boundaries — Foundation-only by construction.
#import "AppControllerSupport.h"
#import "TxMtURLSupport.h"
#import "OakMainMenu.h"
#import "Favorites.h"

// Two free-function headers. Rule 61 measured that both the calls and their
// default arguments reach Swift under SWIFT_OBJC_INTEROP_MODE=objcxx.
#import "RMateServer.h"      // setup_rmate_server
#import "ODBEditorSuite.h"   // DidHandleODBEditorEvent

#import <BundleEditor/BundleEditor.h>
#import <BundlesManager/BundlesManager.h>
#import <BundleMenu/BundleMenu.h>
#import <CommitWindow/CommitWindow.h>
#import <CrashReporter/CrashReporter.h>
#import <DocumentWindow/DocumentWindowController.h>
#import <Find/Find.h>
#import <OakAppKit/NSAlert Additions.h>
#import <OakAppKit/NSMenuItem Additions.h>
#import <OakAppKit/NSSavePanel Additions.h>
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakPasteboard.h>
#import <OakFilterList/BundleItemChooser.h>
#import <OakFoundation/NSString Additions.h>
#import <OakTextView/OakDocumentView.h>
#import <OakTextView/OakTextViewConstants.h>
#import <Preferences/Keys.h>
#import <Preferences/Preferences.h>
#import <Preferences/TerminalPreferences.h>
#import <SoftwareUpdate/SoftwareUpdate.h>
#import <TMBundleModel/TMBundleItem.h>
#import <document/OakDocument.h>
#import <document/OakDocumentController.h>
#import <theme/ThemeUUIDs.h>
