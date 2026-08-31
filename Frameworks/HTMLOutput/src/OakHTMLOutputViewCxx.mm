#import "OakHTMLOutputViewCxx.h"
#import "HOEnvironment.h"

@implementation OakHTMLOutputView (Cxx)
- (void)loadRequest:(NSURLRequest*)aRequest environment:(std::map<std::string, std::string> const&)anEnvironment autoScrolls:(BOOL)flag
{
	[self loadRequest:aRequest environmentBox:[HOEnvironment environmentWithCxxMap:anEnvironment] autoScrolls:flag];
}
@end
