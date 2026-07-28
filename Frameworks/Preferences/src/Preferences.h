// The framework's public ObjC surface. Deliberately hand-written and unchanged
// by the Phase 4 Swift port: `Preferences` and `TerminalPreferences` are now
// implemented in Swift (@objc(Preferences) / @objc(TerminalPreferences)), but
// consumers in other targets — AppController.mm — keep importing this header and
// need no edits. Cross-target use of a generated *-Swift.h would otherwise mean
// exporting build-directory headers through the include farm.
//
// Do not import this header from ObjC++ inside this framework: the generated
// Preferences-Swift.h declares the same classes and the two would collide.
//
// PreferencesPaneProtocol used to live here. It moved to PreferencesPane.swift:
// it is framework-internal (no target outside Preferences ever referenced it),
// and leaving it here would have forced the Swift side to import this header
// for the protocol and thereby re-collide on the class declarations below.
@interface Preferences : NSWindowController
@property (class, readonly) Preferences* sharedInstance;
@end
