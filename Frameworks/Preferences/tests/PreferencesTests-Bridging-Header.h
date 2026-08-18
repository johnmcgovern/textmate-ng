// Bridging header for the PreferencesTests bundle.
//
// TerminalPreferences is implemented in Swift but is internal to the Preferences
// module, so the test bundle cannot `import Preferences`. It does not need to:
// the class is @objc(TerminalPreferences), the test bundle links
// libPreferences.a, and -ObjC force-loads the archive's ObjC metadata — the
// hand-written TerminalPreferences.h declaration is enough to use it from Swift.
//
// Importing that header is safe *here* precisely because it is unsafe inside the
// framework: there is no generated Preferences-Swift.h in this target to collide
// with (see the note in Preferences.h).
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

// Preferences itself, for the construction test: `Preferences.sharedInstance` is
// the exact call -[AppController showPreferences:] makes, and it is what crashed
// in alpha.10 and alpha.11.
#import "../src/Preferences.h"
#import "../src/TerminalPreferences.h"
#import "../src/Keys.h"
