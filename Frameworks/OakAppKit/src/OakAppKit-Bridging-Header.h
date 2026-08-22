// The ObjC surface the OakAppKit Swift code sees (Phase 4).
//
// Prelude first — its C and C++ layers plus Cocoa only, never prelude.m/.mm,
// which would pull WebKit/Quartz/AddressBook through the importer on every Swift
// compile. The reasoning is CommitWindow-Bridging-Header.h's and has not changed.
//
// This framework is the bottom of the UI stack: 31 other files import
// OakUIConstructionFunctions.h and 16 import OakAppKit.h, so almost nothing here
// depends on anything above it. That is why the list below is short, and it is
// expected to stay short — a header appearing here that belongs to a *consumer*
// of OakAppKit is a layering mistake, not a missing import.
//
// Unlike BundleEditor and Find, this framework's ObjC++ can import its own
// generated OakAppKit-Swift.h directly. That header emits `namespace OakAppKit`
// from the module name under SWIFT_OBJC_INTEROP_MODE=objcxx, which clang rejects
// only when the framework also has an ObjC *class* of that name — BundleEditor
// does and needed BESwiftClasses.h; OakAppKit has no such class, only free
// functions in OakAppKit.h. Check before adding one.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

// OakNotEmptyString / OakIsEmptyString.
#import <OakFoundation/OakFoundation.h>

// This framework's own headers, for the classes and free functions the Swift
// calls. OakUIConstructionFunctions declares OakControlFont and
// OakCreateCloseButton; their C++ default arguments are simply invisible to
// Swift, which spells the arguments out instead.
#import "OakView.h"
// OakRolloverButton itself is deliberately absent: it is defined in
// OakRolloverButton.swift, so importing its hand declaration here would collide
// with the generated OakAppKit-Swift.h (rule 43). Only the two notification
// names it posts are needed on this side, and Swift cannot export those
// (rule 19), so they live in their own C header — as OakPasteboard's do.
#import "OakRolloverButtonConstants.h"
#import "OakUIConstructionFunctions.h"
#import "OakAppKitSupport.h"
#import "OakAppKit.h" // OakPerformTableViewActionFromSelector / OakPerformTableViewActionResult (OakPasteboardSelector.swift)
// The styler behind OakSyntaxFormatter.swift. The formatter's own header is
// deliberately absent for the same reason OakPasteboard's and
// OakRolloverButton's are: Swift defines the class, so its hand declaration
// would collide with the generated OakAppKit-Swift.h (rule 43).
#import "OakSyntaxFormatterSupport.h"

// The C++-free boundaries OakPasteboard.swift stands on: the exported constants, the
// SQLite store, the run-loop idle observer (and its protocol), and the selector
// panel it drives. OakPasteboard.h itself is deliberately absent — Swift defines
// OakPasteboard / OakPasteboardEntry, so importing the hand-declaration here would
// collide with the generated OakAppKit-Swift.h.
#import "OakPasteboardConstants.h"
#import "OakPasteboardDatabase.h"
#import "OakPasteboardIdleObserver.h"
