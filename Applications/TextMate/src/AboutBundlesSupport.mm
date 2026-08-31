#import "AboutBundlesSupport.h"
#import <BundlesManager/BundlesManager.h>

@implementation AboutBundleSummary
- (instancetype)initWithName:(NSString*)name path:(NSString*)path
{
	if(self = [super init])
	{
		_name = name;
		_path = path;
	}
	return self;
}
@end

@implementation AboutBundlesSupport
+ (NSArray<AboutBundleSummary*>*)installedBundles
{
	NSMutableArray<AboutBundleSummary*>* res = [NSMutableArray array];
	for(Bundle* bundle in BundlesManager.sharedInstance.bundles)
	{
		if(!bundle.installed || !bundle.path)
			continue;
		[res addObject:[[AboutBundleSummary alloc] initWithName:bundle.name ?: @"" path:bundle.path]];
	}
	return res;
}
@end
