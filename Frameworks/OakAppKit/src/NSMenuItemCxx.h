// The three std::string-typed selectors of NSMenuItem (FileIcon), which cannot
// follow the rest of the category into Swift.
//
// Rule 17: a method whose parameter is a `std::string const&` is not merely
// awkward from Swift, it cannot be declared there at all. -setKeyEquivalentCxxString:
// still has ObjC++ callers (AppController Menus, OakTextView), so the selector has
// to keep an ObjC++ home; the other two are kept beside it because they are the
// same shape and were declared together.
//
// All three are now thin forwarders. Every behaviour lives in the Swift half, on
// the ObjC-clean spellings declared in "NSMenuItem Additions.h" — including
// -setKeyEquivalentString:, whose modifier-prefix parser used to live here.
//
// Split out of "NSMenuItem Additions.h" so that header can be a pure hand
// declaration of the Swift half, and because the five bridging headers that
// import it have no use for these.
#import <Cocoa/Cocoa.h>

@interface NSMenuItem (Cxx)
- (void)setKeyEquivalentCxxString:(std::string const&)aKeyEquivalent;
- (void)setInactiveKeyEquivalentCxxString:(std::string const&)aKeyEquivalent;
- (void)setTabTriggerCxxString:(std::string const&)aTabTrigger;
@end
