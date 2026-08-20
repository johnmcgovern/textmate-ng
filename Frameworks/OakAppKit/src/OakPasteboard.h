// Hand-written ObjC declaration of the Swift OakPasteboard / OakPasteboardEntry
// (OakPasteboard.swift), for consumers that see the class through a header rather
// than the OakAppKit module: the ObjC++ callers in other frameworks (OakTextView,
// clipboard.mm, AppController, WKWebView Additions), the ObjC++ chooser in this one,
// and the Find / DocumentWindow bridging headers whose Swift reads it. Same
// arrangement as OakScopeBarView.h. Nothing checks this against the Swift at build
// time — t_pasteboard.mm's selector-surface tests (rule 18) are the guard against
// drift. Kept out of OakAppKit-Bridging-Header.h (Swift defines these classes; the
// boundary headers it needs go there instead).
#import <oak/oak.h>
#import "OakPasteboardConstants.h" // the extern constants (rule 19)

@interface OakPasteboardEntry : NSObject
@property (nonatomic, readonly) NSString* string;
@property (nonatomic, readonly) NSArray<NSString*>* strings;
@property (nonatomic, readonly) NSDictionary* options;
@property (nonatomic, getter = isFlagged) BOOL flagged;
@property (nonatomic, readonly) NSInteger historyId; // This is only to be used by OakPasteboardChooser

@property (nonatomic, readonly) BOOL fullWordMatch;
@property (nonatomic, readonly) BOOL ignoreWhitespace;
@property (nonatomic, readonly) BOOL regularExpression;
// -findOptions (find::options_t) is in the OakPasteboardEntryFindOptions category.
@end

@interface OakPasteboard : NSObject
@property (class, readonly) OakPasteboard* generalPasteboard;
@property (class, readonly) OakPasteboard* findPasteboard;
@property (class, readonly) OakPasteboard* replacePasteboard;

- (void)addEntryWithString:(NSString*)aString;
- (void)addEntryWithString:(NSString*)aString options:(NSDictionary*)someOptions;
- (OakPasteboardEntry*)addEntryWithStrings:(NSArray<NSString*>*)someStrings options:(NSDictionary*)someOptions;
- (void)removeEntries:(NSArray<OakPasteboardEntry*>*)pasteboardEntries;
- (void)removeAllEntries;
- (NSArray<OakPasteboardEntry*>*)entries;

- (void)updatePasteboardWithEntry:(OakPasteboardEntry*)pasteboardEntry;
- (void)updatePasteboardWithEntries:(NSArray<OakPasteboardEntry*>*)pasteboardEntries;

- (OakPasteboardEntry*)previous;
- (OakPasteboardEntry*)current;
- (OakPasteboardEntry*)next;

@property (nonatomic, readonly) NSString* name;
@property (nonatomic, readonly) OakPasteboardEntry* currentEntry;

- (void)selectItemForControl:(NSView*)controlView;
@end
