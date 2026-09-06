// The keys and channel names live in their own header now (rule 11) and are
// imported here, so every existing `#import <SoftwareUpdate/SoftwareUpdate.h>`
// is unchanged.
#import "SoftwareUpdateConstants.h"

@interface SoftwareUpdate : NSObject
@property (class, readonly) SoftwareUpdate* sharedInstance;

@property (nonatomic) NSDictionary<NSString*, NSURL*>* channels;
@property (nonatomic, readonly, getter = isChecking) BOOL checking;
@property (nonatomic, readonly) NSString* errorString;

- (void)checkForUpdate:(id)sender;
@end

NSComparisonResult OakCompareVersionStrings (NSString* lhsString, NSString* rhsString);
