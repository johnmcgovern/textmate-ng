// The ObjC surface HTMLOutput's Swift code sees. This framework's first Swift
// file is HOStatusBar, the bar along the bottom of an output window — a leaf,
// not the web view.
//
// Prelude first, its C and C++ layers plus Cocoa only, never prelude.m/.mm — the
// reasoning is CommitWindow-Bridging-Header.h's and has not changed.
//
// Keep this short, and keep hand-declared headers for this framework's own Swift
// classes out of it (rule 43): HOStatusBar.h is absent for exactly that reason.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

// OakCreateNSBoxSeparator, OakStatusBarFont and OakAddAutoLayoutViewsToSuperview,
// which build the bar.
#import <OakAppKit/OakUIConstructionFunctions.h>

// HOFileHandleScheme's handler and the two scheme constants the configuration is
// built from.
#import "../HOFileHandleSchemeSupport.h"
#import "../HOLocalURLRewriter.h"
#import "../HTMLOutput.h"
