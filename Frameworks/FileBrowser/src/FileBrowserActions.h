// The action methods implemented in FileBrowserActions.swift, declared for the
// ObjC++ that still refers to them.
//
// FileBrowserViewController.mm builds the action menu, and every item names its
// action with @selector(...). Once those methods moved to Swift the compiler
// could no longer see them, and each one became an -Wundeclared-selector
// warning — a typo there produces a menu item that is silently dead, which is
// rule 18's failure mode exactly. These declarations restore the check.
//
// **Not in the bridging header, and that is the whole arrangement.** Swift
// defines these methods; if the bridging header saw this file too, the selectors
// would have two declarations and collide. Only the .mm imports it — the same
// split FileBrowserDiskOperations.h uses, and the reason
// FileBrowserViewControllerInternal.h (which *is* in the bridging header) must
// never declare anything Swift implements.
//
// The obvious alternative does not work here: importing the generated
// FileBrowser-Swift.h in the .mm collides with the hand-written headers for the
// classes already ported (FileItem.h, FileBrowserView.h, FileBrowserOutlineView.h,
// rule 23) — the generated header declares those classes as well, and clang
// rejects the second interface. That is worth knowing before trying it; the
// handoff's note that this framework "could self-import FileBrowser-Swift.h"
// holds only for a framework without those hand-written headers.
//
// Nothing checks these against the Swift at build time beyond the selector
// names, so a drift in argument or return type is a runtime problem. Keep them
// in step by hand, as FindSupport.mm does for the same reason.
#import "FileBrowserViewController.h"

// Forward-declared rather than imported: OFBFinderTagsChooser is a Swift class
// behind a hand-written header, and this file only needs its name.
@class OFBFinderTagsChooser;

@interface FileBrowserViewController (Actions)
- (void)openSelectedItems:(id)sender;
- (void)showOriginal:(id)sender;
- (void)showEnclosingFolder:(id)sender;
- (void)showPackageContents:(id)sender;
- (void)showSelectedEntriesInFinder:(id)sender;
- (void)editSelectedEntries:(id)sender;
- (void)addSelectedEntriesToFavorites:(id)sender;
- (void)removeSelectedEntriesFromFavorites:(id)sender;
- (void)executeBundleCommand:(id)sender;
- (void)duplicateSelectedEntries:(id)sender;
- (void)delete:(id)sender;
- (void)didChangeFinderTag:(OFBFinderTagsChooser*)finderTagsChooser;

// The pasteboard family. Same reason as the rest: the action menu names these
// with @selector, and the inactive-key-equivalent table keys on them too.
- (void)cut:(id)sender;
- (void)copy:(id)sender;
- (void)copyAsPathname:(id)sender;
- (void)paste:(id)sender;
- (void)pasteNext:(id)sender;
- (void)createLinkToPasteboardItems:(id)sender;

// Quick Look. -toggleQuickLookPreview: is named by the action menu here and by
// FileBrowserOutlineViewKeyBindings.mm; -imageRectOfItem: is called by
// -openItems:animate:, which is still ObjC++.
- (void)toggleQuickLookPreview:(id)sender;
- (NSRect)imageRectOfItem:(FileItem*)item;
@end
