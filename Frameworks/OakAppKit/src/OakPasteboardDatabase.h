// Hand-written declaration of the Swift OakPasteboardDatabase
// (OakPasteboardDatabase.swift), the SQLite store behind OakPasteboard, for
// t_pasteboard.mm, which pins it (rule 18). It began as a C++ boundary so the
// pasteboard could become Swift; its only C++ turned out to be a dispatch table,
// and the sqlite3 C API is Swift's to call, so the boundary is Swift as well.
// Kept out of the bridging header: Swift defines the class (rule 43). The API:
// a query string plus a dictionary of `:name` → NSString / NSData / NSNumber /
// NSNull(=NULL).
#import <Foundation/Foundation.h>

@interface OakPasteboardDatabase : NSObject
// Opens (and, first time, migrates + creates) the shared PasteboardHistory.db, or an
// in-memory database when disablePersistentClipboardHistory is set, exactly as
// +[OakPasteboard SQLDatabase] did.
+ (nonnull instancetype)sharedInstance;

// Runs one or more `;`-separated statements. Returns nil on error. The result shape
// is moved verbatim from RunSQLStatement (rule 6): for a single row-returning
// statement, its rows (NSArray<NSDictionary*>*); for several, an array of those
// per-statement row arrays — the shape `… .firstObject` / `for(row in …)` callers
// already expect.
- (NSArray*)executeQuery:(NSString*)query;
- (NSArray*)executeQuery:(NSString*)query variables:(NSDictionary<NSString*, id>*)variables;
@end
