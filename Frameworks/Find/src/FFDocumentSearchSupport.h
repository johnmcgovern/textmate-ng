#import "FFFindOptions.h"

@class OakDocument;

// The C++ half of FFDocumentSearch, split out so the class itself can be Swift
// (Phase 4): the settings lookup that builds the enumerator's glob dictionary,
// and the one call that still speaks find::options_t.
//
// It also owns the two exported notification names. A Swift
// `NSNotification.Name` extension does not emit a C symbol and consumers link
// against one, so the definitions stay in ObjC — the TMURLWillCloseNotification
// arrangement.

// The option dictionary OakDocumentController's enumerator expects, merging the
// .tm_properties exclusions that apply at `path`. `glob` nil yields an empty
// file-glob list, which matches nothing — see FFDocumentSearch.h.
NSDictionary* FFGlobOptionsForPath (NSString* path, NSString* glob, BOOL searchBinaryFiles, BOOL searchHiddenFolders);

// -matchesForString:options:bufferSize: takes find::options_t, which Swift
// cannot name. This is the explicit conversion the NS_OPTIONS split exists to
// localise; the two are pinned to each other by static_assert in the .mm.
NSArray* FFMatchesInDocument (OakDocument* document, NSString* searchString, FFFindOptions options, NSUInteger* bufferSize);
