// The ObjC surface document's Swift code sees. This framework's first Swift file
// is EncodingView, the "Unknown Encoding" sheet — a leaf. OakDocument itself is
// the engine's ObjC face and stays ObjC++ (see NEXT_SESSION_HANDOFF.md, the
// 2026-09-14 survey), so this header will never carry it.
//
// Prelude first (C/C++ layers + Cocoa only, never prelude.m/.mm — see
// CommitWindow-Bridging-Header.h): the OakAppKit headers below assume it.
//
// Deliberately absent: EncodingView.h, the hand-written declaration of a class
// this module defines in Swift (rule 23, rule 43).
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

// The transcode-and-highlight preview, behind a C++-free face (rule 25).
#import "EncodingViewSupport.h"

// OakCreateLabel / OakCreateCheckBox / OakCreateButton and
// OakAddAutoLayoutViewsToSuperview, which build the sheet. The C++ default
// arguments do not reach Swift; every call spells every argument.
#import <OakAppKit/OakUIConstructionFunctions.h>

// The encoding pop-up: a hand declaration of an OakAppKit Swift class, which is
// fine to consume across the boundary (only subclassing is not, rule 56).
#import <OakAppKit/OakEncodingPopUpButton.h>
