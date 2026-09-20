#import "BundlesManagerSupport.h"
#import "InstallBundleItems.h"
#import <regexp/format_string.h>
#import <text/decode.h>
#import <ns/ns.h>
#import <io/path.h>
#import <io/entries.h>
#import <os/activity.h>

static char const* kBundleAttributeUpdated = "org.textmate.bundle.updated";

@implementation BundlesManagerSupport
+ (NSURL*)remoteIndexURL
{
	// This fork's own signed mirror. TM_BUNDLE_INDEX_URL is a -D flag so the
	// value is fixed at build time and covered by the code signature: where
	// bundles come from is not something a preference should be able to move,
	// because a bundle command is arbitrary code.
	return [NSURL URLWithString:@TM_BUNDLE_INDEX_URL];
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

+ (void)runInUpdateBundleIndexActivity:(void(^)(void))block
{
	os_activity_initiate("Update bundle index", OS_ACTIVITY_FLAG_DEFAULT, block);
}
@end
