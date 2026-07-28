// Public ObjC surface for the Terminal pane — see the note in Preferences.h.
// AppController.mm calls +updateMateIfRequired at launch; that is the whole
// cross-target API. The class itself is implemented in TerminalPreferences.swift
// as @objc(TerminalPreferences), which is also the name TerminalPreferences.xib
// names as its File's Owner.
//
// Nullability is annotated so Swift callers get non-Optional results — without
// it -init imports as returning TerminalPreferences? and every use needs
// unwrapping, which is noise given the Swift initializer cannot fail.
NS_ASSUME_NONNULL_BEGIN

@interface TerminalPreferences : NSViewController
// The Swift class's only designated initializer is `init()`; PreferencesPane
// declares its own designated init, so NSViewController's are NOT inherited.
// Spelling that out here matters: without it a caller working from this header
// (the nib tests) resolves -init to NSViewController's, which chains to
// -initWithNibName:bundle: and traps with "use of unimplemented initializer".
- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(NSNibName)aNibName bundle:(NSBundle*)aBundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder*)aCoder NS_UNAVAILABLE;

+ (void)updateMateIfRequired;
@end

NS_ASSUME_NONNULL_END
