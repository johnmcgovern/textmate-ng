// The ObjC surface this framework's Swift sees. Compiled standalone by the Swift
// Clang importer — no GCC_PREFIX_HEADER — so includes are explicit. Every header
// here was probed against these exact flags at the project's own -std=c++2a
// before being added (rule 55, rule 62), with a control that fails.
//
// Deliberately absent:
//   * SoftwareUpdate.h and OakDownloadManager.h — hand-written declarations of
//     classes this module now defines in Swift. Importing either would collide
//     with the generated -Swift.h (rule 23, rule 43). Swift sees those classes
//     directly; only ObjC++ consumers need the headers.
#import <Cocoa/Cocoa.h>

// The user-defaults keys and channel names, and the version comparator. Both
// stay ObjC++ because Swift can call a global but never export one (rule 19).
#import "SoftwareUpdateConstants.h"
#import "OakCompareVersionStrings.h"

// os_activity_initiate is a macro; see the header.
#import "SoftwareUpdateSupport.h"

#import <OakAppKit/OakAppKit.h>                    // OakIsAlternateKeyOrMouseEvent
#import <OakAppKit/OakSound.h>                     // OakPlayUISound
#import <OakAppKit/OakTransitionViewController.h>
#import <OakAppKit/OakUIConstructionFunctions.h>   // OakAddAutoLayoutViewsToSuperview
#import <OakAppKit/NSImage Additions.h>            // +imageNamed:inSameBundleAsClass:
