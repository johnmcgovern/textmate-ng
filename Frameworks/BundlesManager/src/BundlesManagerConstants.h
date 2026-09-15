// The user-defaults keys, split out of BundlesManager.h and BundlesManager.mm
// (rule 11), for the reason SoftwareUpdateConstants.h gives: BundlesManager.h
// declares a class that is Swift now, so it cannot enter this framework's
// bridging header (rule 43), and Swift can call a global but never export one
// (rule 19), so the keys have to stay defined by an ObjC++ translation unit and
// declared somewhere the Swift can see. BundlesManager.h imports this, so no
// consumer changed.
//
// All three are here, including the poll frequency only this framework reads.
#import <Foundation/Foundation.h>

extern NSString* const kUserDefaultsDisableBundleUpdatesKey;
extern NSString* const kUserDefaultsLastBundleUpdateCheckKey;
extern NSString* const kUserDefaultsBundleUpdateFrequencyKey;
