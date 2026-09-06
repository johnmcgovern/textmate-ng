// Hand-declared (rule 23): this class is defined in SoftwareUpdate.swift, with
// its panel in SUDownloadViewController.swift.
//
// It must stay out of the framework's bridging header, where it would collide
// with the generated -Swift.h (rule 43). Its ObjC++ consumers import it
// unchanged: the application (AppController calls -checkForUpdate:) and
// BundlesManager's Bundle.mm, which wants only OakCompareVersionStrings.
//
// The keys, channel names and the version comparator live in their own headers
// (rule 11) and are imported here, so nothing a consumer writes had to change.
// They are ObjC++ because Swift can call a global but never export one (rule 19).
#import "SoftwareUpdateConstants.h"
#import "OakCompareVersionStrings.h"

@interface SoftwareUpdate : NSObject
@property (class, readonly) SoftwareUpdate* sharedInstance;

@property (nonatomic) NSDictionary<NSString*, NSURL*>* channels;
@property (nonatomic, readonly, getter = isChecking) BOOL checking;
@property (nonatomic, readonly) NSString* errorString;

- (void)checkForUpdate:(id)sender;
@end
