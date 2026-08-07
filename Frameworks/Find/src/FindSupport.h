// The C++ half of Find, split out so the window controller itself can be Swift
// (Phase 4). Same shape as FFResultNodeSupport.mm and FFDocumentSearchSupport.mm,
// and the same rule: the *decisions* stay in the Swift. Nothing here chooses
// what to search, what to replace or what to show — these functions convert,
// format and call through, and every one of them is a place where C++ appears in
// a signature Swift cannot name.
//
// There are three kinds of thing in here.
//
//  1. **OakDocumentMatch's C++ members.** `text::range_t range` and
//     `std::map<std::string, std::string> captures` are dropped by the Clang
//     importer, so a Swift caller holding an OakDocumentMatch can reach its
//     first/last/excerpt/lineNumber and nothing else. Anything downstream of
//     .range or .captures comes through here.
//
//  2. **C++-typed selectors on types this framework does not own.**
//     -performReplacements:checksum: takes a std::multimap and lives in
//     OakDocument.h; -selectRange:inDocument: takes a text::range_t and is
//     FindDelegate's, which DocumentWindowController implements in ObjC++.
//     Neither signature is moving, so the call sites move here instead.
//
//  3. **path:: / format_string:: / regexp:: string work**, the usual suspects.
//
// FindMatch's own implementation is in the .mm as well: two of its three
// properties are text::range_t, so it stays ObjC++ and stays declared in Find.h,
// where OakTextView.mm already constructs one.
#import <Cocoa/Cocoa.h>
#import "FFFindOptions.h"
#import "FindTypes.h"

@class OakDocument;
@class OakDocumentMatch;

// ============================================================
// = find_operation_t's ObjC spelling                         =
// ============================================================
//
// The same NS_ENUM split FFFindOptions is, for the same reason and with the same
// guard: OakFindServerProtocol's -findOperation returns a C++ unscoped enum whose
// width the compiler picks, and any ObjC or Swift declaration of that property
// would use NSInteger. The values are pinned to find_operation_t by static_assert
// in FindSupport.mm and checked again at runtime by t_find_operation.mm.
//
// Unlike FFFindOptions this is an NS_ENUM and not NS_OPTIONS: it is a choice of
// one, never a mask. Nothing ORs these together.
typedef NS_ENUM(NSInteger, FFFindOperation) {
	FFFindOperationCount = 0,
	FFFindOperationCountInSelection,
	FFFindOperationFind,
	FFFindOperationFindInSelection,
	FFFindOperationReplace,
	FFFindOperationReplaceAndFind,
	FFFindOperationReplaceAll,
	FFFindOperationReplaceAllInSelection,
};

// ============================================================
// = OakDocumentMatch, past the members the importer drops    =
// ============================================================

// One FindMatch spanning a file's first and last match — the pair OakTextView
// steps through with ⌘G once a folder search has finished. Both ranges are read
// off the matches' `range` members, which is the whole reason this is not a
// Swift initialiser call.
FindMatch* FFFindMatchForRange (NSUUID* uuid, OakDocumentMatch* firstMatch, OakDocumentMatch* lastMatch);

// -setMarkOfType:atPosition:content: takes a text::pos_t, and the position is
// `match.range.from`. Two dropped members in one call.
void FFSetMarkForMatch (OakDocumentMatch* match, NSString* markType);

// -selectRange:inDocument:, FindDelegate's one C++-typed requirement, applied to
// `match.range`. `delegate` nil is a no-op, matching a message to nil.
void FFSelectMatch (id <FindDelegate> delegate, OakDocumentMatch* match, OakDocument* document);

// The match's regexp captures as an ObjC dictionary — what -didSelectResult:
// hands to OakDocument.matchCaptures, and what the emptiness test in
// -copyReplacements: reads. Empty (never nil) when the match has none.
NSDictionary<NSString*, NSString*>* FFCapturesForMatch (OakDocumentMatch* match);

// `format` with its ${n} capture references expanded against the match's
// captures. Callers decide *whether* to expand — a literal search leaves the
// replacement alone even when captures exist — so this always expands.
NSString* FFExpandFormatString (NSString* format, OakDocumentMatch* match);

// ============================================================
// = The replace path                                         =
// ============================================================

// One edit, in the byte offsets OakDocument speaks. The ObjC++ built these
// straight into the std::multimap that -performReplacements:checksum: takes;
// Swift builds an array of these instead and FFPerformReplacements assembles the
// multimap on the other side of the boundary.
//
// A class rather than a struct because the array crosses as an NSArray, and
// because `first`/`last` want names — they are offsets into the document, not a
// range in the text::range_t sense.
@interface FFReplacement : NSObject
@property (nonatomic, readonly) NSUInteger first;
@property (nonatomic, readonly) NSUInteger last;
@property (nonatomic, readonly) NSString*  replacement;
- (instancetype)initWithFirst:(NSUInteger)first last:(NSUInteger)last replacement:(NSString*)replacement;
@end

// Applies every replacement to `document` in one pass, refusing if the document
// changed on disk since the search read it (that is what `checksum` is for).
// Returns NO when the checksum does not match, exactly as
// -performReplacements:checksum: does — the caller then has to put the
// replacement previews back.
//
// The multimap is ordered and admits duplicate keys; the array is turned into one
// verbatim, so two replacements at the same offsets both survive, as they did.
BOOL FFPerformReplacements (OakDocument* document, NSArray<FFReplacement*>* replacements, uint32_t checksum);

// -saveModalForWindow:completionHandler: hands its block an `oak::uuid_t const&`,
// which makes the block untypeable from Swift. The block body is carried over
// verbatim: a document that is still closed after the save gets its content
// dropped again, so a background replace does not leave the whole file resident.
void FFSaveDocumentModalForWindow (OakDocument* document, NSWindow* window);

// ============================================================
// = Strings                                                  =
// ============================================================

// nil when `pattern` is a valid regular expression, and the human-readable
// complaint — already wrapped in "Invalid regular expression: …." — when it is
// not. Returning the finished sentence rather than the raw error keeps
// text::format on this side of the line.
NSString* FFInvalidRegularExpressionMessage (NSString* pattern);

// The name shown for a folder in the “In:” pop-up. `candidates` is every other
// folder the menu is showing, because the name is disambiguated against them —
// two folders both called "src" become "one ▸ src" and "two ▸ src". Falls back to
// NSFileManager's display name when `path` is not among the candidates.
NSString* FFDisplayNameForFolder (NSString* path, NSArray<NSString*>* candidates);

// path::relative_to. `base` nil or empty yields `path` unchanged.
NSString* FFRelativePath (NSString* path, NSString* base);

// What the status line says while a folder search runs: the directory part of
// the path currently being scanned, relative to the search folder, with a
// trailing slash. Shows the file name only when the scanner has not moved on
// since the last poll — otherwise the line flickers through every file in a
// directory. `newPath`/`oldPath` are the KVO new and old values, either of which
// may be nil.
NSString* FFSearchProgressRelativePath (NSString* newPath, NSString* oldPath, NSString* searchFolder);

// One line of the Copy Results family: the matched text, or the whole line(s) it
// sits on, optionally prefixed "path:line\t". Byte arithmetic against the
// excerpt, which is why it is here and not in Swift.
NSString* FFCopyStringForMatch (OakDocumentMatch* match, NSString* path, BOOL entireLines, BOOL withFilename);

// ============================================================
// = Misc                                                     =
// ============================================================

// Whether the event being handled is Return being pressed — the test behind
// "close the Find window when ⏎ found something". Compares the event's
// characters against the carriage return, which the ObjC++ did through utf8::.
BOOL FFCurrentEventIsReturnKeyDown (void);
