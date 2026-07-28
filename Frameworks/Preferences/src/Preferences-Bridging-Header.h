// The ObjC/ObjC++ surface the Preferences Swift code sees (Phase 4).
//
// Compiled standalone by the Swift Clang importer, so the prelude comes first —
// its C/C++ layers plus Cocoa only, never prelude.m/.mm (see the note in
// CommitWindow-Bridging-Header.h: those drag WebKit/Quartz through the importer
// on every Swift compile, and would also put the `network` farm dir in play).
//
// Deliberately absent: Preferences.h and TerminalPreferences.h. Those declare
// the classes this module implements *in Swift*; importing them here would
// collide with the generated Preferences-Swift.h declarations.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

#import <BundlesManager/BundlesManager.h>
#import <MenuBuilder/MenuBuilder.h>
#import <OakAppKit/NSAlert Additions.h>
#import <OakAppKit/NSImage Additions.h>
#import <OakAppKit/OakEncodingPopUpButton.h>
#import <OakAppKit/OakScopeBarView.h>
#import <OakAppKit/OakTransitionViewController.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakFoundation/OakFoundation.h>
#import <OakFoundation/OakStringListTransformer.h>
#import <OakTabBarView/OakTabBarView.h>
#import <SoftwareUpdate/SoftwareUpdate.h>

#import "Keys.h"
#import "PWSupport.h"
