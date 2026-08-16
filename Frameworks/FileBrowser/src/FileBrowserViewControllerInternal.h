// The private surface of FileBrowserViewController that a *peeled-off* Swift
// section needs to reach.
//
// The controller keeps its real private state in a class extension inside
// FileBrowserViewController.mm, which Swift cannot see. As sections of the
// class move out into Swift extensions ahead of the port (the shape
// FileBrowserDiskOperations established), each one may need a property that
// lives there. Rather than widen the public header — those properties are not
// API, and nothing outside this framework should reach them — they are
// re-declared here, **readonly**, and this header goes in the bridging header.
//
// Readonly is the point, not an accident: the class extension keeps the
// readwrite declaration, so a peeled section can read this state but cannot
// start writing it from Swift, which would move behaviour rather than move
// code. Redeclaring a class-extension property as readonly in a category is
// accepted by clang with no diagnostic (checked, not assumed).
//
// **This header is temporary.** Every property on it exists because the class
// is still ObjC++; when the class itself becomes Swift, the class extension and
// this file both go away and the properties become ordinary private state
// again. If it is still here after the port, something was missed.
#import "FileBrowserViewController.h"

@interface FileBrowserViewController (Internal)

// Read by the NSOutlineViewDataSource section (-outlineView:isItemExpandable:).
// Both are driven from FileBrowserView and written only by their custom setters
// in the controller, which reload the outline view.
@property (nonatomic, readonly) BOOL canExpandPackages;
@property (nonatomic, readonly) BOOL canExpandSymbolicLinks;

@end
