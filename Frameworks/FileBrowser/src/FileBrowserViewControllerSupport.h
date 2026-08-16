// The C++ of FileBrowserViewController, moved out ahead of the port so the
// controller itself can become Swift (rule 25, and step 2 of this framework's
// plan: boundary first, translation second).
//
// Unlike every earlier port here, the C++ is not one fragment — the survey found
// seven clusters spread across the file. They arrive in this class one commit at
// a time, each with a C++-free signature so the bridging header can import it,
// and each moved **verbatim** (rule 6) rather than re-derived.
//
// Present so far — the two settings-driven ones:
@class FileItem;

@interface FileBrowserViewControllerSupport : NSObject
// Which children of a directory the browser shows: the exclude/include glob
// lists from settings (`excludeInBrowser`, `includeFiles`, and the six other
// pairs), plus `excludeSCMDeleted` for items git reports as deleted, as an
// NSPredicate over FileItem. Hidden items are tested against the *include*
// globs and everything else against the *exclude* globs — that inversion is the
// whole point of the block and is easy to get backwards.
//
// The caller decides whether to filter at all; this is only reached when
// showExcludedItems is off.
+ (NSPredicate*)itemPredicateForDirectoryURL:(NSURL*)directoryURL;

// Whether a file is binary per the `binary` setting's glob (e.g. `*.pdf`), which
// decides whether double-clicking opens it in TextMate or hands it to Finder.
+ (BOOL)isBinaryURL:(NSURL*)url;

// The action-menu items contributed by bundles (semantic class
// `callback.file-browser.action-menu`), sorted by name with `text::less_t`.
//
// The boundary hands back *finished* NSMenuItems rather than the bundle items
// behind them: `bundles::item_ptr` is the rule-20 type that cannot cross into
// Swift, so nothing here may return one. Each item carries its bundle's UUID
// string as `representedObject`, which is what -executeBundleCommand: looks the
// command back up by; `action` is the caller's, since this class has no opinion
// about which selector runs them.
+ (NSArray<NSMenuItem*>*)actionMenuItemsWithAction:(SEL)action;

// Runs one of those items: `bundles::lookup` on the UUID the menu item carries,
// then OakCommand.
//
// This is the cluster that can never be Swift, rather than merely inconvenient
// to translate — OakCommand's own API is C++-typed on both sides
// (-initWithBundleCommand: takes a `bundle_command_t const&`, and
// -executeWithInput:variables:outputHandler: a `std::map`), so the call has to
// be made from ObjC++ wherever the controller ends up. `firstResponder` is the
// controller, which OakCommand holds weakly.
//
// A UUID that resolves to nothing is a no-op, exactly as the lookup's null
// item_ptr was.
+ (void)executeBundleCommandWithUUIDString:(NSString*)uuidString firstResponder:(NSResponder*)firstResponder;

// The path extension a new untitled file should get: the `attr.untitled`
// fileType setting for the directory, then the grammar extension of whichever
// bundle claims that scope. nil when no bundle does — the caller keeps its own
// default rather than having one imposed here.
+ (NSString*)pathExtensionForNewFileInDirectoryURL:(NSURL*)directoryURL;
@end
