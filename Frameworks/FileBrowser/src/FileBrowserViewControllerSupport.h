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

// The device a path lives on, which is how the drag handler decides move vs
// copy: a drag within one device moves, across devices copies (and the option
// key inverts it).
//
// `dev_t` looks like it belongs on the other side of this boundary, but it is
// plain C — an int32_t from <sys/types.h> — so it imports into Swift as-is.
// Returning it, rather than a same-device BOOL over a pair of paths, is what
// lets the caller keep stat-ing the drop target once for the whole drag instead
// of once per dragged item.
// Two spellings, deliberately: -[NSURL fileSystemRepresentation] and
// -[NSString fileSystemRepresentation] are different methods, and the drag
// handler used one of each. Rather than route both through a single signature
// and assume they agree on every path, each caller keeps the conversion it had.
//
// NS_SWIFT_NAME on the second one only, and that asymmetry is the point: the
// importer leaves `deviceForPath:` alone but trims the trailing URL off its
// sibling, so the pair arrives in Swift as device(forPath:) / device(for:)
// (rule 28). Pinning restores the symmetry. Safe to pin here — both were added
// this session and nothing outside this framework calls either.
+ (dev_t)deviceForPath:(NSString*)path;
+ (dev_t)deviceForURL:(NSURL*)url NS_SWIFT_NAME(device(forURL:));

// The key-equivalent string of an event, per ns::to_s(NSEvent*) — modifier
// prefixes and all. The comparison against it stays with the caller, which is
// the only thing that knows an arrow key means "move the Quick Look selection".
+ (NSString*)eventStringForEvent:(NSEvent*)event;

@end
