#import "FileChooserSupport.h"
#import <OakFoundation/NSString Additions.h>
#import <document/OakDocumentController.h>
#import <ns/ns.h>
#import <scm/scm.h>
#import <settings/settings.h>
#import <text/ranker.h>

// FileChooser's remaining C++, moved from FileChooser.mm (2026-08-20); see
// FileChooserSupport.h for what each piece is. globs_for_path and the filter regular
// expression came out with `git show` rather than retyping (rule 6) and are asserted
// byte-identical by t_file_chooser_support.mm; only their signatures changed, from
// std::string and ivars to NSString parameters and properties.

static NSDictionary* globs_for_path (NSString* aPath)
{
	std::string const path = to_s(aPath);
	static std::map<std::string, NSString*> const map = {
		{ kSettingsExcludeDirectoriesInFileChooserKey, kSearchExcludeDirectoryGlobsKey },
		{ kSettingsExcludeDirectoriesKey,              kSearchExcludeDirectoryGlobsKey },
		{ kSettingsExcludeFilesInFileChooserKey,       kSearchExcludeFileGlobsKey      },
		{ kSettingsExcludeFilesKey,                    kSearchExcludeFileGlobsKey      },
		{ kSettingsExcludeInFileChooserKey,            kSearchExcludeGlobsKey          },
		{ kSettingsExcludeKey,                         kSearchExcludeGlobsKey          },
		{ kSettingsBinaryKey,                          kSearchExcludeGlobsKey          },
		{ kSettingsIncludeDirectoriesKey,              kSearchDirectoryGlobsKey        },
		{ kSettingsIncludeFilesInFileChooserKey,       kSearchFileGlobsKey             },
		{ kSettingsIncludeFilesKey,                    kSearchFileGlobsKey             },
		{ kSettingsIncludeInFileChooserKey,            kSearchGlobsKey                 },
		{ kSettingsIncludeKey,                         kSearchGlobsKey                 },
	};

	NSMutableDictionary* res = [NSMutableDictionary dictionary];

	settings_t const settings = settings_for_path(NULL_STR, "", path);
	for(auto const& pair : map)
	{
		if(NSString* glob = to_ns(settings.get(pair.first)))
		{
			if(!res[pair.second])
				res[pair.second] = [NSMutableArray array];
			[res[pair.second] addObject:glob];
		}
	}

	if(!res[kSearchDirectoryGlobsKey] && !res[kSearchGlobsKey])
		res[kSearchDirectoryGlobsKey] = @[ @"*" ];
	if(!res[kSearchFileGlobsKey] && !res[kSearchGlobsKey])
		res[kSearchFileGlobsKey] = @[ @"*" ];

	return res;
}

@implementation FileChooserFilter
{
	NSString* _globString;
	NSString* _filterString;
	NSString* _selectionString;
	NSString* _symbolString;
}

+ (instancetype)filterWithString:(NSString*)string
{
	return [[self alloc] initWithString:string];
}

- (instancetype)initWithString:(NSString*)aString
{
	if(self = [super init])
	{
		aString = [aString decomposedStringWithCanonicalMapping];

		NSRegularExpression* const ptrn = [NSRegularExpression regularExpressionWithPattern:@"\\A(?:(.*?\\*.*?)|(.*?))(?::([\\d+:-x\\+]*)|@(.*))?\\z" options:NSAnchoredSearch error:nil];
		NSTextCheckingResult* m = aString ? [ptrn firstMatchInString:aString options:NSMatchingAnchored range:NSMakeRange(0, [aString length])] : nil;
		self->_globString      = m && [m rangeAtIndex:1].location != NSNotFound ? [aString substringWithRange:[m rangeAtIndex:1]] : nil;
		self->_filterString    = m && [m rangeAtIndex:2].location != NSNotFound ? [NSString stringWithCxxString:oak::normalize_filter(to_s([aString substringWithRange:[m rangeAtIndex:2]]))] : nil;
		self->_selectionString = m && [m rangeAtIndex:3].location != NSNotFound ? [aString substringWithRange:[m rangeAtIndex:3]] : nil;
		self->_symbolString    = m && [m rangeAtIndex:4].location != NSNotFound ? [aString substringWithRange:[m rangeAtIndex:4]] : nil;

	}
	return self;
}

- (NSString*)globString      { return _globString; }
- (NSString*)filterString    { return _filterString; }
- (NSString*)selectionString { return _selectionString; }
- (NSString*)symbolString    { return _symbolString; }

- (NSString*)effectiveFilter { return _globString ?: _filterString ?: @""; }
@end

@implementation FileChooserSCMInfo
{
	scm::info_ptr _info;
}

- (instancetype)initWithInfo:(scm::info_ptr)info
{
	if(self = [super init])
		_info = info;
	return self;
}

+ (instancetype)infoForPath:(NSString*)path
{
	scm::info_ptr info = scm::info(to_s(path));
	return info ? [[self alloc] initWithInfo:info] : nil;
}

- (NSArray<NSString*>*)uncommittedPaths
{
	NSMutableArray<NSString*>* res = [NSMutableArray array];
	for(auto pair : _info->status())
	{
		if(pair.second & (scm::status::modified|scm::status::added|scm::status::deleted|scm::status::conflicted))
			[res addObject:to_ns(pair.first)];
	}
	return res;
}

- (void)addStatusCallback:(void(^)(void))block
{
	_info->push_callback(^(scm::info_t const& info){
		block();
	});
}
@end

@implementation FileChooserSupport
+ (NSDictionary*)searchOptionsForPath:(NSString*)path
{
	settings_t const settings = settings_for_path(NULL_STR, "", to_s(path));
	NSMutableDictionary* options = [globs_for_path(path) mutableCopy];
	options[kSearchFollowDirectoryLinksKey] = @(settings.get(kSettingsFollowSymbolicLinksKey, false));
	options[kSearchIgnoreOrderingKey] = @YES;
	return options;
}

+ (NSString*)path:(NSString*)path relativeTo:(NSString*)base
{
	return to_ns(path::relative_to(to_s(path), to_s(base)));
}

+ (BOOL)pathHasParent:(NSString*)path
{
	return to_s(path) != path::parent(to_s(path));
}
@end
