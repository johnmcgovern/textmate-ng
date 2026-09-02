// The C++ half of -[AppController handleTxMtURL:], extracted ahead of the port
// (rule 25).
//
// txmt://open?url=…&line=…&column=…&uuid=…&project=… is how `mate`, the
// HTML output view and every bundle command that links to a file reach the
// editor, so the parsing here is a real interface with real callers rather than
// an internal detail. 110 lines, of which about 60 were C++: a
// std::map<std::string, std::string> of query parameters, a text::range_t built
// from line/column, and a walk over file:// prefixes using path::.
//
// What is NOT here is the part a boundary looked necessary for. The original
// ends in -showDocument:andSelect:inProject:bringToFront:, whose selection
// argument is `text::range_t const&` — but that method's entire use of the range
// is `aDocument.selection = to_ns(range)`, and OakDocument.selection is an
// NSString property. So the caller sets .selection and uses the existing
// -showDocument:inProject:bringToFront:, which forwards an undefined range and
// therefore skips that assignment. Identical behaviour, no C++, and no new API
// in another framework (rule 36: the ObjC-shaped sibling already existed).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TxMtURLSupport : NSObject

// decode::url_part over the &-separated, =-split query. Pairs that are not
// exactly key=value are skipped, as before.
//
// ONE DELIBERATE DIFFERENCE from the std::map it replaces: a pair whose decoded
// bytes are not valid UTF-8 is dropped rather than stored. std::string held them
// happily; NSDictionary cannot, because to_ns() answers nil and inserting nil
// throws. The original would have carried such a value as far as its own to_ns()
// and produced a nil NSString there instead, so nothing that used to work stops
// working — a malformed %-escape now goes missing one step earlier.
+ (NSDictionary<NSString*, NSString*>*)parametersFromQuery:(nullable NSString*)query;

// to_ns(text::pos_t(line-1, column-1)), the string OakDocument.selection wants.
// nil when there is no line parameter, which is the `range == undefined` the
// original branched on. Column defaults to 1.
+ (nullable NSString*)selectionStringForLine:(nullable NSString*)line column:(nullable NSString*)column;

// The file:// prefix walk: file://localhost/~/, file:///~/ and file://~/ resolve
// against path::home(), file://localhost/ and file:///" against "/", and a bare
// file:// against home as well. nil for anything that matches none of them,
// which is the NULL_STR the original checked for.
+ (nullable NSString*)pathForFileURLString:(NSString*)urlString;

// path::is_directory and path::exists — kept as two calls rather than one
// combined answer, because that is what the original did and they are not the
// same question about a symlink.
+ (BOOL)pathIsDirectory:(NSString*)path;
+ (BOOL)pathExists:(NSString*)path;

@end

NS_ASSUME_NONNULL_END
