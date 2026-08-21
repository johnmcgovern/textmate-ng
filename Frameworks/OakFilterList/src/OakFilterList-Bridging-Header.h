// The ObjC surface OakFilterList's Swift code sees. This framework's first Swift files
// are the ui/ leaves (pure AppKit, nothing needed here) and OakAbbreviations, which
// calls OakFoundation's OakIsEmptyString — the same C helpers half the Swift in the
// tree already uses.
//
// Prelude first, its C and C++ layers plus Cocoa only, never prelude.m/.mm — that would
// drag WebKit/Quartz/AddressBook through the importer on every Swift compile. The
// reasoning is CommitWindow-Bridging-Header.h's and has not changed.
//
// Keep this short. OakFilterList sits high on the UI stack (it is subclassed by the
// choosers, not depended on by lower layers), so a header for a *consumer* of this
// framework appearing here would be a layering mistake, not a missing import.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

// OakIsEmptyString / OakNotEmptyString (OakAbbreviations.swift).
#import <OakFoundation/OakFoundation.h>

// OakCreateLabel / OakAddAutoLayoutViewsToSuperview and the tmMatchedText* colours
// (OakFileTableCellView.swift).
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakAppKit/NSColor Additions.h>

// OakPerformTableViewActionFromSelector / OakPerformTableViewActionResult and
// OakStatusBarFont (OakChooser.swift).
#import <OakAppKit/OakAppKit.h>

// OakDocument (SymbolChooser.swift's TMDocument) and the C++ SymbolChooser left behind
// when the panel was ported. OakDocument's own C++-typed members — notably
// -enumerateSymbolsUsingBlock:, whose block takes a text::pos_t const& — simply do not
// import (rule 17); that method is exactly what SymbolChooserSupport exists to wrap.
#import <document/OakDocument.h>
#import "SymbolChooserSupport.h"

// FileChooser.swift: the scope bar and key-view-loop helpers it builds its titlebar from,
// the document controller it searches through, and its own two C++ boundaries.
#import <OakAppKit/OakScopeBarView.h>
#import <document/OakDocumentController.h>
#import "FileChooserItem.h"
#import "FileChooserSupport.h"

// BundleItemChooser.swift: the key-equivalent recorder and event-string formatter it hosts,
// and its own C++ boundary (which brings TMScopeContext with it).
#import <OakAppKit/OakKeyEquivalentView.h>
#import "BundleItemChooserSupport.h"
