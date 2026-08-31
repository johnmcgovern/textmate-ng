// The two fields the About window's Bundles page needs from BundlesManager.
//
// Not a C++ boundary in the usual sense — nothing in AboutWindowController.swift
// names a C++ type. The problem is one level down: <BundlesManager/BundlesManager.h>
// pulls in plist/, oak/algorithm.h and boost, and the app's bridging header is
// deliberately minimal (Foundation and <string>) precisely so the Swift importer
// does not re-parse that chain on every compile. Importing it there fails outright.
//
// So the summary crosses instead of the model. It is also all the page uses: the
// installed bundles' names and paths, from which it reads each Changes.json.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface AboutBundleSummary : NSObject
@property (nonatomic, readonly) NSString* name;
@property (nonatomic, readonly) NSString* path;
@end

@interface AboutBundlesSupport : NSObject
// Installed bundles that have a path, in BundlesManager's order. The two skips the
// ObjC++ did at the top of its loop happen here, so the caller has nothing to
// filter.
+ (NSArray<AboutBundleSummary*>*)installedBundles;
@end

NS_ASSUME_NONNULL_END
