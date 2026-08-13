// All that is left of this file after the Swift port: the entry point itself.
//
// OakShowPopOutAnimation cannot be written in Swift. It is a C++ free function
// with a default argument, Swift cannot declare a global function visible to
// ObjC at all, and OakTextView.mm calls it both ways — with three arguments at
// :617 and four at :797. Rewriting the signature to suit the port would change a
// public API for the porter's convenience, so it keeps its exact shape and
// forwards to OakPopOutView.
//
// This is the same shape as OakIsAlternateKeyOrMouseEvent in OakAppKit.h and the
// two variadic NSAlert helpers: C++ or C-variadic free functions in a public
// header are a category of thing the Swift port works *around* rather than
// through. PROJECT_PHASES.md records free functions as the coupling survey's
// real blind spot; a default argument makes one doubly invisible, because the
// call sites do not even mention the parameter.
#import "OakPopOutAnimation.h"
#import "OakAppKit-Swift.h"

void OakShowPopOutAnimation (NSView* parentView, NSRect popOutRect, NSImage* anImage, BOOL hidePrevious)
{
	[OakPopOutView showInParentView:parentView popOutRect:popOutRect image:anImage hidePrevious:hidePrevious];
}
