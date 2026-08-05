#import <Cocoa/Cocoa.h>

@class OakDocumentMatch;

// The C++ half of FFResultNode, split out so the class itself can be Swift
// (Phase 4). Everything here is attributed-string construction over std::string
// and text::/path:: helpers, plus one piece of text::pos_t arithmetic — none of
// it reachable from Swift, and none of it stateful. Same shape as BEInterop.mm
// and CRSupport.mm.
//
// The *decisions* stay in the Swift: which string to display, when to
// recompute an excerpt. These functions only build.

// The path shown for a file row, relative to the search's base directory, with
// the leading components dimmed and the file name bold. `base` may be nil.
NSAttributedString* FFPathComponentString (NSString* path, NSString* base, NSFont* font);

// The match excerpt with its line-number gutter, the match itself highlighted,
// and tabs/CRs made visible. `replacementString` nil shows the original text;
// non-nil substitutes it, expanding capture references when the match has any.
NSAttributedString* FFExcerptForMatch (OakDocumentMatch* match, NSString* replacementString, NSFont* font);

// How many lines the match spans. A match ending at column 0 does not count the
// line it stops on, unless it is empty.
NSUInteger FFLineSpanForMatch (OakDocumentMatch* match);
