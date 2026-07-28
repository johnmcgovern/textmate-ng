// Bridging header for the BundleEditorTests bundle.
//
// The classes under test are implemented in Swift but are *internal* to the
// BundleEditor module, so the test bundle cannot `import BundleEditor`. It does
// not need to: they are @objc, the test bundle links libBundleEditor.a, and the
// -ObjC linker flag force-loads the archive's ObjC metadata — so declaring the
// ObjC interface is enough to use them typed from Swift. BESwiftClasses.h is
// exactly that declaration and is already maintained for the framework's own
// ObjC++ (see the note in it for why the generated *-Swift.h cannot be used).
//
// Recompiling the Swift sources into the test bundle instead would be wrong: two
// copies of an @objc class with the same runtime name would collide.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

#import "../src/BESwiftClasses.h"
