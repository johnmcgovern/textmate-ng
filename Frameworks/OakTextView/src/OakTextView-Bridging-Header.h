// The ObjC surface OakTextView's Swift code sees. Everything portable in this
// framework is now Swift: OakChoiceMenu, OTVStatusBar, OakDocumentView, OTVHUD
// and LiveSearchView.
//
// Prelude first, its C and C++ layers plus Cocoa only, never prelude.m/.mm — the
// reasoning is CommitWindow-Bridging-Header.h's and has not changed.
//
// Keep this short, and keep hand-declared headers for this framework's own Swift
// classes out of it (rule 43). All five are absent for exactly that reason —
// OakChoiceMenu.h, OTVStatusBar.h, OakDocumentView.h, OTVHUD.h and
// LiveSearchView.h — while the constants and the delegate protocol beside them
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
#import "GutterView.h"
#import <document/OakDocument.h>

// What OakDocumentView drives besides the gutter and the text view.
#import <OakAppKit/OakAppKit.h>            // OakIsAlternateKeyOrMouseEvent
#import <OakAppKit/NSImage Additions.h>    // +imageNamed:inSameBundleAsClass:
#import <OakAppKit/OakPasteboard.h>
#import <OakAppKit/OakPasteboardChooser.h>
#import <OakFilterList/SymbolChooser.h>    // itself a Swift class, behind a hand declaration
#import <BundleMenu/BundleMenu.h>
