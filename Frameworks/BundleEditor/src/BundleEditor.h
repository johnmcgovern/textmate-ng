// The public surface, and deliberately C++-free (rule 11).
//
// This header used to open with `#include <bundles/bundles.h>` for the sake of
// one selector, which put the whole class out of reach of any Swift bridging
// header. -revealBundleItem: now lives in BundleEditorCxx.h alongside the other
// C++ shims, and what is left here is what a Swift consumer can use: the same
// split TMBundleItem.h / TMBundleModelCxx.h already makes in the framework this
// one depends on.
//
// The class itself is defined in BundleEditor.swift; this is its hand
// declaration (rule 23), and it is kept out of this framework's own bridging
// header for the reason given there.
#import <TMBundleModel/TMBundleItem.h>

@interface BundleEditor : NSWindowController <NSBrowserDelegate>
@property (class, readonly) BundleEditor* sharedInstance;

// Selects the item, opening its bundle in the browser. nil is accepted and
// selects nothing, matching the Swift.
//
// This is the ObjC-shaped half of -revealBundleItem:, which BEInterop.mm
// forwards to. It was reachable only through a private category in that file
// until now; the app needs it by name once AppController is Swift, and it is
// already what the C++ shim calls.
- (void)revealItem:(nullable TMBundleItem*)item;

- (IBAction)browserSelectionDidChange:(id)sender;
@end
