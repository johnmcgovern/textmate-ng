// The two fragments of FileBrowserDiskOperations that cannot be Swift, kept in
// ObjC++ behind C++-free signatures so the rest of the file can be (rule 25).
//
// 1. The symlink/copy path arithmetic. `path::device`, `path::relative_to` and
//    `path::is_child` are C++ (io/path.h), and the relative-symlink rule they
//    implement — link relative to the destination's directory when source and
//    destination are on the same device, absolute otherwise — is worth moving
//    verbatim rather than re-deriving (rule 6).
//
// 2. -presentError:, which is an *override* of NSResponder's method: it presents
//    the error as a sheet on the file browser's window instead of app-modally.
//    **Its category declaration is in the .mm, not here**, and that moved at the
//    flip: this header is in the bridging header, and once Swift defines
//    FileBrowserViewController it must not also see an ObjC declaration of that
//    class — which a category on it requires. Nothing calls -presentError:
//    by name from ObjC (AppKit and the Swift both reach it as NSResponder's),
//    so the declaration has no reason to be public.
//
// Why it did not become part of the Swift class along with everything else: the
// override is one line, `-presentError:modalForWindow:…`, and AppKit declares
// that window parameter **nonnull**. The ObjC++ passes `self.view.window`, which
// is nil whenever the browser is not in a window, and passing nil through was
// the behaviour. From Swift the parameter is a non-optional NSWindow, so a
// faithful translation has nowhere to put the nil: `view.window!` traps, and
// falling back to `super.presentError(_:)` presents app-modally and returns a
// different value. Rule 31 stopped applying at the flip; this replaced it.

@interface FileBrowserDiskOperationsSupport : NSObject
// The destination path for a symbolic link at destURL pointing at srcURL:
// relative to destURL's directory when the two are on the same device (so the
// link survives the pair being moved together), and nil when they are not — the
// caller then links to the source URL itself.
+ (NSString*)symbolicLinkDestinationForURL:(NSURL*)srcURL atURL:(NSURL*)destURL;

// YES when destURL is inside srcURL — copying a directory into itself.
+ (BOOL)isURL:(NSURL*)destURL childOfURL:(NSURL*)srcURL;
@end
