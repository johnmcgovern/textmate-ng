// The ObjC surface OakTextView's Swift code sees. This framework's first Swift
// file is OakChoiceMenu, the completion pop-up — a leaf, not the editor.
//
// Prelude first, its C and C++ layers plus Cocoa only, never prelude.m/.mm — the
// reasoning is CommitWindow-Bridging-Header.h's and has not changed.
//
// Keep this short, and keep hand-declared headers for this framework's own Swift
// classes out of it (rule 43): OakChoiceMenu.h is absent for exactly that reason,
// while the constants beside it are here because Swift needs to read them.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

// OakCreateLabel, which builds both the sizing probe and the row views.
#import <OakAppKit/OakUIConstructionFunctions.h>

// The five key-action codes -didHandleKeyEvent: returns.
#import "OakChoiceMenuConstants.h"
