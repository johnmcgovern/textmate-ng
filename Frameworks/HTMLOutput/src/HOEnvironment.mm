#import "HOEnvironment.h"
#import <OakFoundation/NSString Additions.h>
#import <ns/ns.h>

@implementation HOEnvironment
{
	std::map<std::string, std::string> _map;
}

+ (instancetype)environmentWithCxxMap:(std::map<std::string, std::string> const&)map
{
	HOEnvironment* res = [HOEnvironment new];
	res->_map = map;
	return res;
}

- (std::map<std::string, std::string> const&)cxxMap
{
	return _map;
}

- (NSString*)valueForVariable:(NSString*)name
{
	auto it = _map.find(to_s(name));
	return it != _map.end() ? [NSString stringWithCxxString:it->second] : nil;
}
@end
