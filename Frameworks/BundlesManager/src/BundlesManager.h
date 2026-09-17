// Hand-declared (rule 23): this class is defined in BundlesManager.swift.
//
// It must stay out of this framework's bridging header, where it would collide
// with the generated -Swift.h (rule 43). Its ObjC++ consumers import it
// unchanged, and so do the bridging headers of TextMate, BundleEditor,
// DocumentWindow and Preferences — consuming a Swift class of another module
// through its declaration is the established pattern (rule 56 forbids only
// subclassing). Nothing checks this file against the Swift at build time; the
// selectors are pinned by tests/t_bundles_manager.mm (rule 18).
#import "Bundle.h"
#import "BundlesManagerConstants.h"

// -findBundleForInstall:, which answers through a bundles::item_ptr, is declared
// in BundlesManagerCxx.h (rule 37) so that this header is C++-free and the
// bridging headers that import it stay so.
NS_ASSUME_NONNULL_BEGIN

@interface BundlesManager : NSObject
@property (class, readonly) BundlesManager* sharedInstance;

@property (nonatomic, readonly) NSArray<Bundle*>* bundles;

- (NSProgress*)installBundles:(NSArray<Bundle*>*)someBundles completionHandler:(void(^)(NSArray<Bundle*>*))callback;
- (void)uninstallBundle:(Bundle*)aBundle;
- (void)loadBundlesIndex;
- (void)installBundleItemsAtPaths:(NSArray*)somePaths;
- (void)reloadPath:(NSString*)aPath;
@end

NS_ASSUME_NONNULL_END
