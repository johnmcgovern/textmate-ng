// Syntax-highlighted rendering for the Quick Look preview extension.
//
// This is the half of the old .qlgenerator worth keeping: the buffer setup,
// grammar lookup and theme application that turn a file into a styled
// NSAttributedString. Only the CFPlugIn entry points around it died with the
// legacy API — see PROJECT_PHASES.md, "QuickLook".
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// The highlighted contents of `url`, or nil when the file has no grammar this
// build can resolve — the caller then falls back to plain text rather than
// showing nothing. `backgroundOut` receives the theme's background colour for
// the resolved file type, so the preview's view can match it.
//
// Reads at most `maxSize` bytes: a preview of a 400 MB file is still a preview.
NSAttributedString* _Nullable TMQLCreateAttributedString (NSURL* url, size_t maxSize, NSColor* _Nullable * _Nullable backgroundOut);

NS_ASSUME_NONNULL_END
