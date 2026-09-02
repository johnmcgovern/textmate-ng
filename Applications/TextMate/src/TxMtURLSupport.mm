#import "TxMtURLSupport.h"
#import <io/path.h>
#import <ns/ns.h>
#import <oak/oak.h>
#import <text/decode.h>
#import <text/types.h>

@implementation TxMtURLSupport

+ (NSDictionary<NSString*, NSString*>*)parametersFromQuery:(NSString*)query
{
	NSMutableDictionary* parameters = [NSMutableDictionary dictionary];
	for(NSString* part in [query componentsSeparatedByString:@"&"])
	{
		NSArray* keyValue = [part componentsSeparatedByString:@"="];
		if([keyValue count] == 2)
		{
			std::string key = decode::url_part(to_s([keyValue firstObject]));
			std::string value = decode::url_part(to_s([keyValue lastObject]));
			if(NSString* k = to_ns(key))
			{
				if(NSString* v = to_ns(value))
					parameters[k] = v;
			}
		}
	}
	return parameters;
}

+ (NSString*)selectionStringForLine:(NSString*)line column:(NSString*)column
{
	if(!line)
		return nil;

	size_t col = column ? atoi(to_s(column).c_str()) : 1;
	return to_ns(text::range_t(text::pos_t(atoi(to_s(line).c_str())-1, col-1)));
}

+ (NSString*)pathForFileURLString:(NSString*)urlString
{
	static std::string const kTildeURLPrefixes[] = { "file://localhost/~/", "file:///~/", "file://~/" };
	static std::string const kRootURLPrefixes[]  = { "file://localhost/", "file:///" };

	std::string const urlStr = to_s(urlString);
	std::string path = NULL_STR;

	for(auto root : kRootURLPrefixes)
	{
		if(urlStr.find(root) == 0)
			path = path::join("/", urlStr.substr(root.size()));
	}

	for(auto tilde : kTildeURLPrefixes)
	{
		if(urlStr.find(tilde) == 0)
			path = path::join(path::home(), urlStr.substr(tilde.size()));
	}

	if(path == NULL_STR && urlStr.find("file://") == 0)
		path = path::join(path::home(), urlStr.substr(std::string("file://").size()));

	return path == NULL_STR ? nil : to_ns(path);
}

+ (BOOL)pathIsDirectory:(NSString*)path
{
	return path::is_directory(to_s(path));
}

+ (BOOL)pathExists:(NSString*)path
{
	return path::exists(to_s(path));
}

@end
