// The small C++ fragments of BundlesManager and Bundle, each moved here verbatim
// (rule 6) behind a C++-free signature (rule 25), so the rest of both files can
// be Swift. Every method is one of the original's expressions with its
// arguments and result converted at the edge, and nothing else.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Swift names are stated rather than left to the importer (rule 28).
@interface BundlesManagerSupport : NSObject
// [NSURL URLWithString:@REST_API "/bundles"] — REST_API is a -D flag the Swift
// compiler does not see.
+ (NSURL*)remoteIndexURL;

// path::set_attr(remoteIndexPath, "last-check", to_s(oak::date_t::now())),
// which -tryUpdateBundleIndexAndCallback: writes after every check.
+ (void)recordIndexCheckAtPath:(NSString*)remoteIndexPath NS_SWIFT_NAME(recordIndexCheck(atPath:));

// The org.textmate.bundle.updated xattr on an installed bundle: written by
// -installBundles: as to_s(NSDate*), read back by the index parser through the
// "yyyy-MM-dd HH:mm:ss ZZZZZ" formatter. Both halves are here so the format
// stays one fact. nil when the attribute is absent.
+ (void)setUpdatedDate:(nullable NSDate*)date forBundleAtPath:(NSString*)bundlePath NS_SWIFT_NAME(setUpdatedDate(_:forBundleAtPath:));
+ (nullable NSDate*)updatedDateForBundleAtPath:(NSString*)bundlePath NS_SWIFT_NAME(updatedDate(forBundleAtPath:));

// path::entries(bundlesDir, "*.tm[Bb]undle"): the entry names, in scandir order.
+ (NSArray<NSString*>*)bundleDirectoryNamesInDirectory:(NSString*)bundlesDir NS_SWIFT_NAME(bundleDirectoryNames(inDirectory:));

// decode::rot13, for the contactEmailRot13 field of both indexes.
+ (nullable NSString*)rot13:(nullable NSString*)string NS_SWIFT_NAME(rot13(_:));

// Bundle.textSummary: tags stripped, whitespace collapsed, entities decoded.
+ (nullable NSString*)textSummaryForString:(nullable NSString*)summary NS_SWIFT_NAME(textSummary(for:));

// InstallBundleItems(), whose header carries C++ the bridging header need not.
+ (void)installBundleItemsAtPaths:(NSArray*)somePaths NS_SWIFT_NAME(installBundleItems(atPaths:));

// os_activity_initiate("Update bundle index", …) — a C macro Swift cannot call.
// Dropping it would quietly ungroup the index check's log messages in Console;
// SoftwareUpdateSupport.h made the same call for the same reason.
+ (void)runInUpdateBundleIndexActivity:(void(^)(void))block NS_SWIFT_NAME(runInUpdateBundleIndexActivity(_:));
@end

NS_ASSUME_NONNULL_END
