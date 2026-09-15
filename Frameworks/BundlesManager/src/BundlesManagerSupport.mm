#import "BundlesManagerSupport.h"
#import "InstallBundleItems.h"
#import <regexp/format_string.h>
#import <text/decode.h>
#import <ns/ns.h>
#import <io/path.h>
#import <io/entries.h>

static char const* kBundleAttributeUpdated = "org.textmate.bundle.updated";

@implementation BundlesManagerSupport
+ (NSURL*)remoteIndexURL
{
	return [NSURL URLWithString:@REST_API "/bundles"];
}

+ (void)recordIndexCheckAtPath:(NSString*)remoteIndexPath
{
	path::set_attr(remoteIndexPath.fileSystemRepresentation, "last-check", to_s(oak::date_t::now()));
}

+ (void)setUpdatedDate:(NSDate*)date forBundleAtPath:(NSString*)bundlePath
{
	path::set_attr(to_s(bundlePath), kBundleAttributeUpdated, to_s(date));
}

+ (NSDate*)updatedDateForBundleAtPath:(NSString*)bundlePath
{
	NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
	dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss ZZZZZ";
	if(NSString* str = to_ns(path::get_attr(to_s(bundlePath), kBundleAttributeUpdated)))
		return [dateFormatter dateFromString:str];
	return nil;
}

+ (NSArray<NSString*>*)bundleDirectoryNamesInDirectory:(NSString*)bundlesDir
{
	NSMutableArray<NSString*>* res = [NSMutableArray array];
	for(auto const& entry : path::entries(to_s(bundlesDir), "*.tm[Bb]undle"))
		[res addObject:to_ns(entry->d_name)];
	return res;
}

+ (NSString*)rot13:(NSString*)string
{
	return to_ns(decode::rot13(to_s(string)));
}

+ (NSString*)textSummaryForString:(NSString*)summary
{
	std::string str = to_s(summary);
	str = format_string::replace(str, "\\A\\s+|<[^>]*>|\\s+\\z", "");
	str = format_string::replace(str, "\\s+", " ");
	str = decode::entities(str);
	return to_ns(str);
}

+ (void)installBundleItemsAtPaths:(NSArray*)somePaths
{
	InstallBundleItems(somePaths);
}
@end
