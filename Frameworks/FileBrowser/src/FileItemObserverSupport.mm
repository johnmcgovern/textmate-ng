#import "FileItemObserverSupport.h"
#import "SCMManager.h"
#import "SCMSupportCxx.h"
#import <io/path.h>
#import <ns/ns.h>

@implementation FileItemObserverSupport
// The loop is moved verbatim (rule 6) from FileItemObserver.mm's SCM observer
// block; only the surrounding method shape changed.
+ (NSArray<NSURL*>*)deletedURLsInRepository:(SCMRepository*)repository forDirectoryURL:(NSURL*)url
{
	NSMutableArray<NSURL*>* urls = [NSMutableArray array];

	std::string const dir = url.fileSystemRepresentation;
	for(auto pair : repository.status.rawStatus)
	{
		if(!(pair.second & scm::status::deleted) || dir != path::parent(pair.first))
			continue;

		[urls addObject:[NSURL fileURLWithPath:to_ns(pair.first) isDirectory:NO]];
	}

	return urls;
}
@end
