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
