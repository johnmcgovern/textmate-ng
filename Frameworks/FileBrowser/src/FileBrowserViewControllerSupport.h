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
@end
