// Public ObjC surface for the Terminal pane — see the note in Preferences.h.
// AppController.mm calls +updateMateIfRequired at launch; that is the whole
// cross-target API. The class itself is implemented in TerminalPreferences.swift
// as @objc(TerminalPreferences), which is also the name TerminalPreferences.xib
// names as its File's Owner.
@interface TerminalPreferences : NSViewController
+ (void)updateMateIfRequired;
@end
