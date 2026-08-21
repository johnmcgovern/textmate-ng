@class OakDocument;

// Extracted from FileChooser.mm ahead of porting that class to Swift. FileChooserItem
// cannot become Swift at all: it stores std::string paths and std::vector cover ranges as
// *ivars* (rule 20), which is the DWScopeContext shape of blocker, and it is also what the
// table binds to — the row's icon, name, folder and closeDisabled are read by key, and the
// close button binds to objectValue.closeDisabled. So it stays ObjC++ behind this header,
// which has no C++ in it.
//
// The ranking is deliberately a *batch* class method rather than per-item calls. The
// original built one path::glob_t (or one filter plus its bindings) outside the loop and
// then ranked every record concurrently with NSEnumerationConcurrent; exposing per-item
// ranking with NSString parameters would rebuild the glob per item, on every keystroke,
// over every file in the project. Keeping the loop here preserves both the concurrency and
// the one-time setup.
@interface FileChooserItem : NSObject
- (instancetype)initWithDocument:(OakDocument*)document base:(NSString*)base isCurrent:(BOOL)isCurrent;

@property (nonatomic) OakDocument* document;
@property (nonatomic, readonly) NSImage* icon;
@property (nonatomic, readonly) NSAttributedString* name;
@property (nonatomic, readonly) NSAttributedString* folder;
@property (nonatomic, getter = isCloseDisabled, readonly) BOOL closeDisabled;
@property (nonatomic, getter = isMatched) BOOL matched;
@property (nonatomic, getter = isDirectoryMatched, readonly) BOOL directoryMatched;

// Ranks records[first...] against either a glob (when globString is non-empty) or a filter
// plus the user's learned abbreviations, then returns the matched records sorted — by name
// for a glob, by rank for a filter, exactly as the original chose its compare selector.
+ (NSArray<FileChooserItem*>*)rankedItemsFromRecords:(NSArray<FileChooserItem*>*)records
                                           fromIndex:(NSUInteger)first
                                          globString:(NSString*)globString
                                        filterString:(NSString*)filterString
                                            bindings:(NSArray<NSString*>*)bindings;
@end
