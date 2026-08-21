// Hand-written ObjC declaration of the Swift OakAbbreviations (OakAbbreviations.swift),
// for its callers FileChooser.mm and BundleItemChooser.mm, still ObjC++. Kept out of the
// bridging header (Swift defines the class); behaviour is pinned by t_abbreviations.mm
// (rule 18). Disappears once both choosers are Swift too.
@interface OakAbbreviations : NSObject
+ (OakAbbreviations*)abbreviationsForName:(NSString*)aName;

- (NSArray<NSString*>*)stringsForAbbreviation:(NSString*)anAbbreviation;
- (void)learnAbbreviation:(NSString*)anAbbreviation forString:(NSString*)aString;
@end
