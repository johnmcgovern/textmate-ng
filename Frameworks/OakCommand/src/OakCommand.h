#include <command/parser.h>

extern NSNotificationName const OakCommandDidTerminateNotification;
// Posted instead of calling [BundleEditor.sharedInstance revealBundleItem:]
// directly — that call was OakCommand's only tie to BundleEditor, closing a
// cycle in the framework graph. userInfo carries the bundle item's UUID as an
// NSString (OakCommandUUIDKey) rather than the C++ item_ptr itself, since a
// std::shared_ptr can't go in an NSDictionary and the poster only has the UUID
// at hand anyway; the observer looks the item up itself.
extern NSNotificationName const OakRevealBundleItemNotification;
extern NSString* const OakCommandUUIDKey;
extern NSString* const OakCommandErrorDomain;

NS_ENUM(NSInteger) {
	OakCommandRequirementsMissingError,
	OakCommandAbnormalTerminationError
};

@class OakHTMLOutputView;

@interface OakCommand : NSObject
@property (nonatomic, weak) NSResponder* firstResponder;
@property (nonatomic, readonly) NSUUID* identifier;
@property (nonatomic, strong) void(^modalEventLoopRunner)(OakCommand*, BOOL* didTerminate);
@property (nonatomic, strong) void(^terminationHandler)(OakCommand*, BOOL normalExit);
@property (nonatomic) BOOL updateHTMLViewAtomically;
@property (nonatomic, readonly) OakHTMLOutputView* htmlOutputView;
- (instancetype)initWithBundleCommand:(bundle_command_t const&)aCommand;
- (void)executeWithInput:(NSFileHandle*)fileHandleForReading variables:(std::map<std::string, std::string> const&)someVariables outputHandler:(void(^)(std::string const& out, output::type placement, output_format::type format, output_caret::type outputCaret, std::map<std::string, std::string> const& environment))handler;
- (void)terminate;
- (void)closeHTMLOutputView;
@end
