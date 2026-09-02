// Split out of AppController.h (rule 11).
//
// That header declares `@interface AppController` *and* this free function, and
// the two want opposite things once the class is Swift: the class declaration
// becomes a hand declaration that must stay **out** of the bridging header
// (rule 43, or the class gets two interfaces), while a free function Swift calls
// must be **in** it. So they cannot share a file, and splitting now is cheaper
// than splitting during the flip.
//
// No consumer changed: AppController.h imports this, so `#import
// "AppController.h"` still yields everything it did. That is the arrangement
// Find.h/FindTypes.h already uses.
//
// Reaching it from Swift is settled rather than assumed. The rule 61 probe put
// AppController.h itself — a strict superset of this file — into the app's
// bridging header and called OakOpenDocuments([]) from Swift; it compiled,
// linked, and honoured the C++ default argument. This header is deliberately
// not in the bridging header yet, because nothing in Swift calls it; add it when
// something does.
//
// THE FLIP HAS A CHOICE TO MAKE HERE, and it is worth making deliberately.
// All four call sites — one in AppController.mm, three in
// AppController Documents.mm — end up in Swift. At that point this can either
// stay a C++-linkage free function defined in ObjC++ (Swift calls it, per rule
// 61) or become a Swift static method (Swift cannot *export* a global, rule 19,
// so the free-function spelling would have to go). Nothing outside these files
// calls it, so the second is available and is probably the tidier end state.
#import <Foundation/Foundation.h>

// Opens each path: a directory shows a file browser, a `.tmbundle`-family item
// or `.tmplugin` is installed rather than opened unless treatFilePackageAsFolder
// is YES (or Option is held), and everything else becomes a document.
void OakOpenDocuments (NSArray* paths, BOOL treatFilePackageAsFolder = NO);
