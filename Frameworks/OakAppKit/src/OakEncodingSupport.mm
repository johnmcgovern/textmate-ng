#import "OakEncodingSupport.h"
#import <io/path.h>
#import <ns/ns.h>
#import <text/parse.h>
#import <plist/plist.h>

// Moved out of OakEncodingPopUpButton.mm (rule 6). encoding_list()'s body and
// the +initialize body are unchanged apart from where their results land —
// OakCharset objects instead of a std::vector<charset_t>, and a callable class
// method instead of a hook the runtime fires.

static NSString* const kUserDefaultsAvailableEncodingsKey = @"availableEncodings";

@implementation OakCharset
- (instancetype)initWithName:(NSString*)name code:(NSString*)code
{
	if(self = [super init])
	{
		_name = name;
		_code = code;

		// text::split(name, " – ") in the ObjC++, with the same "exactly two
		// parts or nothing" rule the menu builder applied to its result.
		NSArray<NSString*>* parts = [name componentsSeparatedByString:@" – "];
		if(parts.count == 2)
		{
			_group = parts.firstObject;
			_title = parts.lastObject;
		}
	}
	return self;
}
@end

@implementation OakEncodingSupport
+ (NSString*)availableEncodingsKey
{
	return kUserDefaultsAvailableEncodingsKey;
}

+ (NSArray<OakCharset*>*)charsets
{
	NSMutableArray<OakCharset*>* res = [NSMutableArray array];

	std::string path = path::join(path::home(), "Library/Application Support/TextMate/Charsets.plist");
	if(!path::exists(path))
		path = to_s([[NSBundle bundleForClass:[OakEncodingSupport class]] pathForResource:@"Charsets" ofType:@"plist"]);

	plist::array_t encodings;
	if(plist::get_key_path(plist::load(path), "encodings", encodings))
	{
		for(auto const& item : encodings)
		{
			std::string name, code;
			if(plist::get_key_path(item, "name", name) && plist::get_key_path(item, "code", code))
				[res addObject:[[OakCharset alloc] initWithName:to_ns(name) code:to_ns(code)]];
		}
	}

	return res;
}

+ (void)registerDefaultEncodings
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSArray* encodings = @[ @"WINDOWS-1252", @"MACROMAN", @"ISO-8859-1", @"UTF-8", @"UTF-16LE//BOM", @"UTF-16BE//BOM", @"SHIFT_JIS", @"GB18030" ];
		[NSUserDefaults.standardUserDefaults registerDefaults:@{ kUserDefaultsAvailableEncodingsKey: encodings }];

		// LEGACY format used prior to 2.0-beta.10
		NSArray* legacy = [NSUserDefaults.standardUserDefaults stringArrayForKey:kUserDefaultsAvailableEncodingsKey];
		if([legacy containsObject:@"UTF-16BE"] && ![legacy containsObject:@"UTF-16BE//BOM"])
		{
			NSMutableArray* updatedList = [NSMutableArray array];
			for(NSString* charset in legacy)
			{
				BOOL legacyName = ([charset hasPrefix:@"UTF-16"] || [charset hasPrefix:@"UTF-32"]) && ![charset hasSuffix:@"//BOM"];
				[updatedList addObject:legacyName ? [charset stringByAppendingString:@"//BOM"] : charset];
			}
			[NSUserDefaults.standardUserDefaults setObject:updatedList forKey:kUserDefaultsAvailableEncodingsKey];
		}
	});
}
@end
