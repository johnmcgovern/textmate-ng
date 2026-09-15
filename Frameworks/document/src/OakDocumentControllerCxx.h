// The two selectors that cannot follow OakDocumentController into Swift.
//
// Rule 37: -showDocument: and -showDocument:inProject:bringToFront: are one-line
// wrappers that pass `text::range_t::undefined` to the DocumentWindow category,
// and Swift cannot spell that argument. They are declared in
// OakDocumentController.h, where their Swift and ObjC++ callers find them, and
// implemented here as a category, the OakHTMLOutputViewCxx shape.
#import "OakDocumentController.h"

@interface OakDocumentController (Cxx)
@end
