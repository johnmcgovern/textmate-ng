#import "FFDocumentSearchSupport.h"
// Load-bearing, not tidiness: in C++ a `const` object at namespace scope has
// *internal* linkage unless a prior `extern` declaration is in scope, so
// defining the two NSNotificationName constants below without this header first
// makes them file-static and every consumer fails to link. FFDocumentSearch.mm
// got this for free by importing its own header; splitting the file lost it.
#import "FFDocumentSearch.h"
#import <OakFoundation/NSString Additions.h>
#import <document/OakDocumentController.h>
#import <document/OakDocument.h>
#import <settings/settings.h>
#import <regexp/find.h>
#import <ns/ns.h>
#import <oak/oak.h>

NSNotificationName const FFDocumentSearchDidReceiveResultsNotification = @"FFDocumentSearchDidReceiveResultsNotification";
NSNotificationName const FFDocumentSearchDidFinishNotification         = @"FFDocumentSearchDidFinishNotification";

// FFFindOptions is the ObjC spelling of find::options_t (see FFFindOptions.h for
// why it exists). Pinned value-for-value here, so reordering or renumbering
// either one is a compile error rather than a search that quietly stops
// honouring "ignore case".
static_assert(FFFindOptionsFullWords         == find::full_words,         "FFFindOptions diverged from find::options_t");
static_assert(FFFindOptionsIgnoreCase        == find::ignore_case,        "FFFindOptions diverged from find::options_t");
static_assert(FFFindOptionsIgnoreWhitespace  == find::ignore_whitespace,  "FFFindOptions diverged from find::options_t");
static_assert(FFFindOptionsRegularExpression == find::regular_expression, "FFFindOptions diverged from find::options_t");
static_assert(FFFindOptionsBackwards         == find::backwards,          "FFFindOptions diverged from find::options_t");
static_assert(FFFindOptionsNotBOL            == find::not_bol,            "FFFindOptions diverged from find::options_t");
static_assert(FFFindOptionsNotEOL            == find::not_eol,            "FFFindOptions diverged from find::options_t");
static_assert(FFFindOptionsWrapAround        == find::wrap_around,        "FFFindOptions diverged from find::options_t");
static_assert(FFFindOptionsAllMatches        == find::all_matches,        "FFFindOptions diverged from find::options_t");
static_assert(FFFindOptionsExtendSelection   == find::extend_selection,   "FFFindOptions diverged from find::options_t");
static_assert(FFFindOptionsFileSizeLimit     == find::filesize_limit,     "FFFindOptions diverged from find::options_t");

// Moved verbatim from FFDocumentSearch.mm, less the std::string parameter — the
// caller is Swift now, so the path arrives as an NSString and is converted here.
NSDictionary* FFGlobOptionsForPath (NSString* aPath, NSString* glob, BOOL searchBinaryFiles, BOOL searchHiddenFolders)
{
	static std::map<std::string, NSString*> const map = {
		{ kSettingsExcludeDirectoriesInFolderSearchKey, kSearchExcludeDirectoryGlobsKey },
		{ kSettingsExcludeDirectoriesKey,               kSearchExcludeDirectoryGlobsKey },
		{ kSettingsExcludeFilesInFolderSearchKey,       kSearchExcludeFileGlobsKey      },
		{ kSettingsExcludeFilesKey,                     kSearchExcludeFileGlobsKey      },
		{ kSettingsExcludeInFolderSearchKey,            kSearchExcludeGlobsKey          },
		{ kSettingsExcludeKey,                          kSearchExcludeGlobsKey          },
	};

	NSDictionary* res = @{
		kSearchExcludeDirectoryGlobsKey: [NSMutableArray array],
		kSearchExcludeFileGlobsKey:      [NSMutableArray array],
		kSearchExcludeGlobsKey:          [NSMutableArray array],
		kSearchDirectoryGlobsKey:        [NSMutableArray arrayWithObject:searchHiddenFolders ? @"{,.}*" : @"*"],
		kSearchFileGlobsKey:             [NSMutableArray arrayWithArray:glob ? @[ glob ] : @[ ]],
		kSearchGlobsKey:                 [NSMutableArray array],
	};

	settings_t const settings = settings_for_path(NULL_STR, "", to_s(aPath));
	for(auto const& pair : map)
	{
		if(NSString* glob = to_ns(settings.get(pair.first)))
			[res[pair.second] addObject:glob];
	}

	if(!searchBinaryFiles)
	{
		if(NSString* glob = to_ns(settings.get(kSettingsBinaryKey)))
			[res[kSearchExcludeFileGlobsKey] addObject:glob];
	}

	return res;
}

NSArray* FFMatchesInDocument (OakDocument* document, NSString* searchString, FFFindOptions options, NSUInteger* bufferSize)
{
	return [document matchesForString:searchString options:(find::options_t)options bufferSize:bufferSize];
}
