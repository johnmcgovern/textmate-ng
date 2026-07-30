@interface NSMenuItem (FileIcon)
- (void)updateTitle:(NSString*)newTitle;
- (void)setIconForFile:(NSString*)path;
- (void)setKeyEquivalentCxxString:(std::string const&)aKeyEquivalent;
- (void)setActivationString:(NSString*)anActivationString withFont:(NSFont*)aFont;
- (void)setInactiveKeyEquivalentCxxString:(std::string const&)aKeyEquivalent;
- (void)setTabTriggerCxxString:(std::string const&)aTabTrigger;

// ObjC-clean spellings of the two above, for Swift callers — a C++-typed
// selector is not merely awkward from Swift, it is uncallable. nil means "no
// key equivalent"/"no tab trigger", which is what NULL_STR meant.
- (void)setInactiveKeyEquivalent:(NSString*)aKeyEquivalent;
- (void)setTabTrigger:(NSString*)aTabTrigger;

- (void)setModifiedState:(BOOL)flag;
- (void)setDynamicTitle:(NSString*)title;
@end
