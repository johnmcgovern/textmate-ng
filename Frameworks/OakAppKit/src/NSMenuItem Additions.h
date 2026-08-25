// Hand-declared (rule 23): this category is defined in
// "NSMenuItem Additions.swift".
//
// Five frameworks' bridging headers import this file, so it is the ObjC face of
// the Swift half — and it must not appear in OakAppKit's own bridging header,
// where it would collide with the generated OakAppKit-Swift.h (rule 43). It is
// already absent from it.
//
// The three std::string-typed selectors that used to be declared here moved to
// <OakAppKit/NSMenuItemCxx.h>; Swift cannot declare them (rule 17), and the
// bridging headers that import this file never used them.
@interface NSMenuItem (FileIcon)
- (void)updateTitle:(NSString*)newTitle;
- (void)setIconForFile:(NSString*)path;
- (void)setActivationString:(NSString*)anActivationString withFont:(NSFont*)aFont;

// nil means "no key equivalent"/"no tab trigger", which is what NULL_STR meant.
- (void)setInactiveKeyEquivalent:(NSString*)aKeyEquivalent;
- (void)setTabTrigger:(NSString*)aTabTrigger;

// Binds a key equivalent written with a modifier prefix ("@s" is ⌘S). Not
// -setKeyEquivalent:, which AppKit owns and which takes the key on its own.
// -setKeyEquivalentCxxString: forwards here; nil or an empty string clears both
// the key equivalent and its modifier mask.
- (void)setKeyEquivalentString:(NSString*)aKeyEquivalent;

- (void)setModifiedState:(BOOL)flag;
- (void)setDynamicTitle:(NSString*)title;
@end
