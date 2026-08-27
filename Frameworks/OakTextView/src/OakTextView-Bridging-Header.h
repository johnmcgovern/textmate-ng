// The ObjC surface OakTextView's Swift code sees. Two files so far: OakChoiceMenu,
// the completion pop-up, and OTVStatusBar — leaves, not the editor.
//
// Prelude first, its C and C++ layers plus Cocoa only, never prelude.m/.mm — the
// reasoning is CommitWindow-Bridging-Header.h's and has not changed.
//
// Keep this short, and keep hand-declared headers for this framework's own Swift
// classes out of it (rule 43): OakChoiceMenu.h and OTVStatusBar.h are absent for
// exactly that reason, while the constants and the delegate protocol beside them
// are here because Swift needs to read them.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

// OakCreateLabel, which builds both the sizing probe and the row views;
// OakStatusBarFont and the auto-layout helpers, which build the status bar.
#import <OakAppKit/OakUIConstructionFunctions.h>

// -setKeyEquivalentString:, which binds a grammar's shortcut in the status bar's
// grammar menu. OakAppKit's own hand-declared header, so rule 43 does not apply.
#import <OakAppKit/NSMenuItem Additions.h>

// The five key-action codes -didHandleKeyEvent: returns.
#import "OakChoiceMenuConstants.h"

// OTVStatusBar's two bundles::query calls, and the model objects they return.
#import "OTVStatusBarSupport.h"
#import <TMBundleModel/TMBundleItem.h>

// OTVStatusBar declares `delegate` with this type, so Swift has to see it.
#import "OTVStatusBarDelegate.h"

// OakTextView itself: OakDocumentView holds one and drives it. Its theme_ptr and
// bundles::item_ptr members cannot cross into Swift and are answered by
// OakDocumentViewSupport instead; the importer simply drops them.
#import "OakTextView.h"
#import "OakDocumentViewSupport.h"
