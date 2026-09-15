// The small C++ fragments of BundlesManager and Bundle, each moved here verbatim
// (rule 6) behind a C++-free signature (rule 25), so the rest of both files can
// be Swift. Every method is one of the original's expressions with its
// arguments and result converted at the edge, and nothing else.
#import <Foundation/Foundation.h>

@interface BundlesManagerSupport : NSObject
// [NSURL URLWithString:@REST_API "/bundles"] — REST_API is a -D flag the Swift
// compiler does not see.
+ (NSURL*)remoteIndexURL;

// path::set_attr(remoteIndexPath, "last-check", to_s(oak::date_t::now())),
// which -tryUpdateBundleIndexAndCallback: writes after every check.
+ (void)recordIndexCheckAtPath:(NSString*)remoteIndexPath;

// The org.textmate.bundle.updated xattr on an installed bundle: written by
// -installBundles: as to_s(NSDate*), read back by the index parser through the
// "yyyy-MM-dd HH:mm:ss ZZZZZ" formatter. Both halves are here so the format
// stays one fact. nil when the attribute is absent.
+ (void)setUpdatedDate:(NSDate*)date forBundleAtPath:(NSString*)bundlePath;
+ (NSDate*)updatedDateForBundleAtPath:(NSString*)bundlePath;

// path::entries(bundlesDir, "*.tm[Bb]undle"): the entry names, in scandir order.
+ (NSArray<NSString*>*)bundleDirectoryNamesInDirectory:(NSString*)bundlesDir;

// decode::rot13, for the contactEmailRot13 field of both indexes.
+ (NSString*)rot13:(NSString*)string;

// Bundle.textSummary: tags stripped, whitespace collapsed, entities decoded.
+ (NSString*)textSummaryForString:(NSString*)summary;

// InstallBundleItems(), whose header carries C++ the bridging header need not.
+ (void)installBundleItemsAtPaths:(NSArray*)somePaths;
@end
