// Definitions for BundlesManagerConstants.h. Moved verbatim from
// BundlesManager.mm; see the header for why they live apart from it.
//
// This translation unit stays ObjC++ permanently. It exists precisely because
// Swift cannot export a global (rule 19) — porting it would delete the symbols
// that Preferences links against.
#import "BundlesManagerConstants.h"

NSString* const kUserDefaultsDisableBundleUpdatesKey       = @"disableBundleUpdates";
NSString* const kUserDefaultsLastBundleUpdateCheckKey      = @"lastBundleUpdateCheck";
NSString* const kUserDefaultsBundleUpdateFrequencyKey      = @"bundleUpdateFrequency";
