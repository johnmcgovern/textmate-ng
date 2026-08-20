// -findOptions returns a C++ find::options_t (rule 17), so it cannot be a method on
// the Swift OakPasteboardEntry; it stays in ObjC++ as a category. Its one consumer,
// OakTextView, ORs the result straight into its own find::options_t, so a boundary
// that returned an NSUInteger would only move the C++ conversion one call out — the
// smaller change is to keep the type here. The boolean flags it reads
// (fullWordMatch / ignoreWhitespace / regularExpression) stay Swift-visible on the
// class itself.
#import "OakPasteboard.h"
#import <regexp/find.h> // for find::options_t

@interface OakPasteboardEntry (FindOptions)
- (find::options_t)findOptions;
@end
