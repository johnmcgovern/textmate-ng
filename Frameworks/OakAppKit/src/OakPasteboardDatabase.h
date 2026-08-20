// The SQLite store behind OakPasteboard, wrapped so the pasteboard can become Swift.
// All the C++ — the sqlite3 C API, the @encode→sqlite3_bind std::function dispatch
// table, ColumnsAsDictionary — lives in the .mm; the API here is C++-free: a query
// string plus an NSDictionary of `:name` → NSString / NSData / NSNumber / NSNull(=NULL).
//
// This is the DWScopeContext / SCMSupport pattern: an ObjC-shaped object owns the
// C++ lifetime (the process-wide sqlite3* handle) and OakPasteboard holds only the
// object. Deliberately free of C++ so a Swift bridging header can import it.
#import <Foundation/Foundation.h>

@interface OakPasteboardDatabase : NSObject
// Opens (and, first time, migrates + creates) the shared PasteboardHistory.db, or an
// in-memory database when disablePersistentClipboardHistory is set, exactly as
// +[OakPasteboard SQLDatabase] did.
+ (instancetype)sharedInstance;

// Runs one or more `;`-separated statements. Returns nil on error. The result shape
// is moved verbatim from RunSQLStatement (rule 6): for a single row-returning
// statement, its rows (NSArray<NSDictionary*>*); for several, an array of those
// per-statement row arrays — the shape `… .firstObject` / `for(row in …)` callers
// already expect.
- (NSArray*)executeQuery:(NSString*)query;
- (NSArray*)executeQuery:(NSString*)query variables:(NSDictionary<NSString*, id>*)variables;
@end
