#import "FileItemSCMStatusSupport.h"
#import "SCMManagerCxx.h"
#import <io/path.h>
#import <ns/ns.h>

// The two methods below are moved verbatim from FileItemSCMStatus.mm's
// SCMStatusObserver (rule 6) — the scm-map walk that would be a hazard to retype
// in Swift. Only the enclosing class changed.
@implementation FileItemSCMStatusSupport
+ (NSArray<NSURL*>*)unstagedURLsInRepository:(SCMRepository*)repository
{
	std::map<std::string, scm::status::type> unstagedPaths;
	for(auto const& pair : repository.status)
	{
		if(pair.second & (scm::status::modified|scm::status::added|scm::status::deleted|scm::status::conflicted|scm::status::unversioned))
		{
			if(!(pair.second & scm::status::unversioned))
				unstagedPaths.insert(pair);
		}
	}

	if(!repository.tracksDirectories)
	{
		std::vector<std::string> parents;

		std::string child = NULL_STR;
		for(auto it = unstagedPaths.rbegin(); it != unstagedPaths.rend(); ++it)
		{
			if(path::is_child(child, it->first))
					parents.push_back(it->first);
			else	child = it->first;
		}

		for(auto const& path : parents)
			unstagedPaths.erase(path);
	}

	NSMutableArray<NSURL*>* res = [NSMutableArray array];
	for(auto const& pair : unstagedPaths)
		[res addObject:[NSURL fileURLWithPath:to_ns(pair.first)]];
	return res;
}

+ (NSArray<NSURL*>*)untrackedURLsInRepository:(SCMRepository*)repository
{
	std::map<std::string, scm::status::type> untrackedPaths;
	for(auto pair : repository.status)
	{
		if(pair.second & (scm::status::modified|scm::status::added|scm::status::deleted|scm::status::conflicted|scm::status::unversioned))
		{
			if(pair.second & scm::status::unversioned)
				untrackedPaths.insert(pair);
		}
	}

	if(!repository.tracksDirectories)
	{
		std::vector<std::string> children;

		std::string parent = NULL_STR;
		for(auto const& pair : untrackedPaths)
		{
			if(path::is_child(pair.first, parent))
				children.push_back(pair.first);
			else	parent = pair.first;
		}

		for(auto const& path : children)
			untrackedPaths.erase(path);
	}

	NSMutableArray<NSURL*>* res = [NSMutableArray array];
	for(auto const& pair : untrackedPaths)
	{
		NSURL* url = [NSURL fileURLWithPath:to_ns(pair.first)];
		[url setTemporaryResourceValue:@YES forKey:@"org.textmate.disable-scm-status"];
		[res addObject:url];
	}
	return res;
}
@end
