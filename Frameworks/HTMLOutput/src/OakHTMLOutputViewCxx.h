// The one selector that cannot follow OakHTMLOutputView into Swift.
//
// Rule 17: `std::map<std::string, std::string> const&` is not a parameter type
// Swift can declare. OakCommand.mm is this method's only caller and is not
// moving, so the selector keeps an ObjC++ home — a category on the Swift class,
// the NSMenuItemCxx shape. It holds no state, so a category is enough.
#import "OakHTMLOutputView.h"

@interface OakHTMLOutputView (Cxx)
- (void)loadRequest:(NSURLRequest*)aRequest environment:(std::map<std::string, std::string> const&)anEnvironment autoScrolls:(BOOL)flag;
@end
