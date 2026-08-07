#import "FindSupport.h"
#import "Find.h"
#import <OakFoundation/OakFindProtocol.h>
#import <OakFoundation/NSString Additions.h>
#import <document/OakDocument.h>
#import <ns/ns.h>
#import <text/format.h>
#import <text/types.h>
#import <text/utf8.h>
#import <regexp/format_string.h>
#import <regexp/regexp.h>
#import <io/path.h>

// The C++ half of Find. See FindSupport.h for what is in here and why; this file
// is the implementation and the two pieces of glue that have no header:
// FindMatch, whose properties are text::range_t, and the ObjC++ category that
// carries Find's OakFindServerProtocol conformance.
//
// Everything below the "Exported" divider was moved from Find.mm rather than
// retyped — assembled from the file, per the rule this project earned on
// FFResultNodeSupport.mm. The format-string tables especially: they are the half
// of this file with no test coverage that a transcription slip would hide until
// someone read a status line.

// ============================================================
// = FFFindOperation ↔ find_operation_t                       =
// ============================================================
//
// The static half of the guard FindSupport.h describes. A divergence here is a
// compile error rather than a search that quietly performs the wrong operation;
// t_find_operation.mm checks the same pairs at runtime, because this file exists
// only as long as C++ does and the runtime table is what survives it. That is
// not hypothetical — TMSCMStatus.h still cites a static_assert in a file that was
// ported to Swift, taking the assertions with it.
static_assert((NSInteger)kFindOperationCount                  == FFFindOperationCount,                  "FFFindOperation diverged from find_operation_t: count");
static_assert((NSInteger)kFindOperationCountInSelection       == FFFindOperationCountInSelection,       "FFFindOperation diverged from find_operation_t: countInSelection");
static_assert((NSInteger)kFindOperationFind                   == FFFindOperationFind,                   "FFFindOperation diverged from find_operation_t: find");
static_assert((NSInteger)kFindOperationFindInSelection        == FFFindOperationFindInSelection,        "FFFindOperation diverged from find_operation_t: findInSelection");
static_assert((NSInteger)kFindOperationReplace                == FFFindOperationReplace,                "FFFindOperation diverged from find_operation_t: replace");
static_assert((NSInteger)kFindOperationReplaceAndFind         == FFFindOperationReplaceAndFind,         "FFFindOperation diverged from find_operation_t: replaceAndFind");
static_assert((NSInteger)kFindOperationReplaceAll             == FFFindOperationReplaceAll,             "FFFindOperation diverged from find_operation_t: replaceAll");
static_assert((NSInteger)kFindOperationReplaceAllInSelection  == FFFindOperationReplaceAllInSelection,  "FFFindOperation diverged from find_operation_t: replaceAllInSelection");

// And the same for the option bits, which cross this file as well as
// FFDocumentSearchSupport.mm's. Duplicated deliberately: each file that performs
// the conversion should fail to compile on its own if the two ever part.
static_assert((NSUInteger)find::regular_expression == FFFindOptionsRegularExpression, "FFFindOptions diverged from find::options_t: regular_expression");
static_assert((NSUInteger)find::backwards          == FFFindOptionsBackwards,         "FFFindOptions diverged from find::options_t: backwards");
static_assert((NSUInteger)find::all_matches        == FFFindOptionsAllMatches,        "FFFindOptions diverged from find::options_t: all_matches");

// ============================================================
// = FindMatch                                                =
// ============================================================
//
// Moved from Find.mm:50 unchanged. It stays ObjC++ because two of its three
// properties are text::range_t and its initialiser takes two more; it stays
// declared in Find.h because OakTextView.mm constructs one directly, with ranges
// it computes itself, and that call site is not part of this port.

@implementation FindMatch
- (instancetype)initWithUUID:(NSUUID*)uuid firstRange:(text::range_t const&)firstRange lastRange:(text::range_t const&)lastRange
{
	if(self = [super init])
	{
		_UUID       = uuid;
		_firstRange = firstRange;
		_lastRange  = lastRange;
	}
	return self;
}
@end

// ============================================================
// = FFReplacement                                            =
// ============================================================

@implementation FFReplacement
- (instancetype)initWithFirst:(NSUInteger)first last:(NSUInteger)last replacement:(NSString*)replacement
{
	if(self = [super init])
	{
		_first       = first;
		_last        = last;
		_replacement = replacement;
	}
	return self;
}
@end

// ============================================================
// = Exported                                                 =
// ============================================================

FindMatch* FFFindMatchForRange (NSUUID* uuid, OakDocumentMatch* firstMatch, OakDocumentMatch* lastMatch)
{
	return [[FindMatch alloc] initWithUUID:uuid firstRange:firstMatch.range lastRange:lastMatch.range];
}

void FFSetMarkForMatch (OakDocumentMatch* match, NSString* markType)
{
	[match.document setMarkOfType:markType atPosition:match.range.from content:nil];
}

void FFSelectMatch (id <FindDelegate> delegate, OakDocumentMatch* match, OakDocument* document)
{
	[delegate selectRange:match.range inDocument:document];
}

NSDictionary<NSString*, NSString*>* FFCapturesForMatch (OakDocumentMatch* match)
{
	NSMutableDictionary* captures = [NSMutableDictionary dictionary];
	for(auto pair : match.captures)
		captures[to_ns(pair.first)] = to_ns(pair.second);
	return [captures copy];
}

NSString* FFExpandFormatString (NSString* format, OakDocumentMatch* match)
{
	return to_ns(format_string::expand(to_s(format), match.captures));
}

BOOL FFPerformReplacements (OakDocument* document, NSArray<FFReplacement*>* replacements, uint32_t checksum)
{
	std::multimap<std::pair<size_t, size_t>, std::string> map;
	for(FFReplacement* replacement in replacements)
		map.emplace(std::make_pair(replacement.first, replacement.last), to_s(replacement.replacement));
	return [document performReplacements:map checksum:checksum];
}

void FFSaveDocumentModalForWindow (OakDocument* document, NSWindow* window)
{
	[document saveModalForWindow:window completionHandler:^(OakDocumentIOResult result, NSString* errorMessage, oak::uuid_t const& filterUUID){
		// TODO Indicate failure when result != OakDocumentIOResultSuccess
		if(!document.isLoaded) // Ensure document is still closed
			document.content = nil;
	}];
}

NSString* FFInvalidRegularExpressionMessage (NSString* pattern)
{
	std::string error = regexp::validate(to_s(pattern));
	if(error == NULL_STR)
		return nil;
	return to_ns(text::format("Invalid regular expression: %s.", error.c_str()));
}

NSString* FFDisplayNameForFolder (NSString* path, NSArray<NSString*>* candidates)
{
	std::vector<std::string> paths;
	for(NSString* candidate in candidates)
		paths.push_back(to_s(candidate));

	auto it = std::find(paths.begin(), paths.end(), to_s(path));
	if(it != paths.end())
		return [NSString stringWithCxxString:path::display_name(*it, path::disambiguate(paths)[it - paths.begin()])];
	return [NSFileManager.defaultManager displayNameAtPath:path];
}

NSString* FFRelativePath (NSString* path, NSString* base)
{
	return to_ns(path::relative_to(to_s(path), to_s(base)));
}

NSString* FFSearchProgressRelativePath (NSString* newPath, NSString* oldPath, NSString* searchFolder)
{
	// The ObjC++ read these off the KVO change dictionary and guarded with
	// -respondsToSelector:@selector(UTF8String), because the dictionary holds
	// NSNull rather than nil for a cleared value. Swift converts that to nil on
	// the way in, so the guard is a nil check here — same two cases.
	std::string searchPath     = newPath ? to_s(newPath) : "";
	std::string lastSearchPath = oldPath ? to_s(oldPath) : "";

	// Show only the directory part unless the file name hasn’t changed since last poll of the scanner
	if(searchPath != lastSearchPath && !path::is_directory(searchPath))
		searchPath = path::parent(searchPath);

	std::string relative = path::relative_to(searchPath, to_s(searchFolder));
	if(path::is_directory(searchPath))
		relative += "/";

	return to_ns(relative);
}

NSString* FFCopyStringForMatch (OakDocumentMatch* m, NSString* path, BOOL entireLines, BOOL withFilename)
{
	std::string str = to_s(m.excerpt);

	if(!entireLines)
		str = str.substr(m.first - m.excerptOffset, m.last - m.first);
	else if(str.size() && str.back() == '\n')
		str.erase(str.size()-1);

	if(withFilename)
		str = text::format("%s:%lu\t", [path UTF8String], m.lineNumber + 1) + str;

	return to_ns(str);
}

BOOL FFCurrentEventIsReturnKeyDown (void)
{
	NSEvent* event = NSApp.currentEvent;
	return event.type == NSEventTypeKeyDown && to_s(event) == utf8::to_s(NSCarriageReturnCharacter);
}

// ============================================================
// = Find's OakFindServerProtocol conformance                 =
// ============================================================
//
// An ObjC++ category on the Swift class — the recipe BEInterop.mm and
// CRSupport.mm established, and the reason Find.swift contains no C++ at all.
//
// The protocol has five requirements and two of them are C++: -findOptions
// returns find::options_t, and -didFind:…atPosition: takes text::pos_t const&.
// Probes in f9bb0414 showed Swift *can* name both under this project's interop
// mode, so this is a choice rather than a wall — the choice being that one
// declared C++ boundary per framework is easier to reason about than C++ types
// leaking into a 900-line window controller, and that the conversions then have
// exactly one home, next to the static_asserts that pin them.
//
// The other three requirements — findString, replaceString, didReplace:… — are
// pure ObjC and are implemented in Swift. They are declared below so this
// category's conformance is satisfied at compile time.

@interface Find (FindSwiftHalf)
// Implemented in Find.swift. Declared here, not through the generated
// Find-Swift.h: under SWIFT_OBJC_INTEROP_MODE=objcxx that header emits
// `namespace Find`, and this framework has an ObjC class named Find, which clang
// rejects as a redefinition — the BESwiftClasses.h situation exactly. Keep these
// in step with the Swift by hand; nothing checks them at build time, and a
// mismatch is an unrecognized selector at runtime.
@property (nonatomic, readonly) NSString* findString;
@property (nonatomic, readonly) NSString* replaceString;
@property (nonatomic) FFFindOperation findOperationTag;
@property (nonatomic) FFFindOptions    findOptionsMask;
- (void)didFindNumber:(NSUInteger)aNumber statusString:(NSString*)statusString;
- (void)didReplace:(NSUInteger)aNumber occurrencesOf:(NSString*)aFindString with:(NSString*)aReplacementString;
@end

@implementation Find (OakFindServer)

- (find_operation_t)findOperation
{
	return (find_operation_t)self.findOperationTag;
}

- (find::options_t)findOptions
{
	return (find::options_t)self.findOptionsMask;
}

- (void)didFind:(NSUInteger)aNumber occurrencesOf:(NSString*)aFindString atPosition:(text::pos_t const&)aPosition wrapped:(BOOL)didWrap
{
	static std::string const formatStrings[4][3] = {
		{ "No more occurrences of “${found}”.", "Found “${found}”${line:+ at line ${line}, column ${column}}.",               "${count} occurrences of “${found}”." },
		{ "No more matches for “${found}”.",    "Found one match for “${found}”${line:+ at line ${line}, column ${column}}.", "${count} matches for “${found}”."    },
	};

	std::map<std::string, std::string> variables;
	variables["count"]  = to_s([NSNumberFormatter localizedStringFromNumber:@(aNumber) numberStyle:NSNumberFormatterDecimalStyle]);
	variables["found"]  = to_s(aFindString);
	variables["line"]   = aPosition ? std::to_string(aPosition.line + 1)   : NULL_STR;
	variables["column"] = aPosition ? std::to_string(aPosition.column + 1) : NULL_STR;
	NSString* statusString = [NSString stringWithCxxString:format_string::expand(formatStrings[(self.findOptionsMask & FFFindOptionsRegularExpression) ? 1 : 0][std::min<size_t>(aNumber, 2)], variables)];

	// Everything the ObjC++ did after building the string — set it, announce it,
	// and close the window if ⏎ found something — is ordinary AppKit and stays in
	// Swift. Only the sentence itself needed C++.
	[self didFindNumber:aNumber statusString:statusString];
}

@end
