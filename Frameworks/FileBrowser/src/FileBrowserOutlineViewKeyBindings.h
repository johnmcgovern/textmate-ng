// The one C++ fragment of FileBrowserOutlineView, kept in ObjC++ so the rest of
// the class can be Swift.
//
// -performKeyEquivalent: matched an NSEvent against a table of key strings built
// with ns::to_s(NSEvent*) and utf8::to_s — a well-tested key-equivalent format
// (modifier prefixes + character) that would be a hazard to re-derive in Swift
// (rule 6). So the table and the match stay here, verbatim; the Swift override
// calls this and, on a hit, sends the returned action itself, so the
// send-or-fall-through-to-super control flow stays in Swift and identical to the
// original.
//
// Returns the matched action selector, or nil if the event matches nothing (the
// caller then defers to super). C++-free signature, so the bridging header can
// import it.
#import <Cocoa/Cocoa.h>

SEL _Nullable FileBrowserOutlineViewActionForEvent(NSEvent* anEvent);
