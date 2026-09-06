// Split out of SoftwareUpdate.h (rule 11), for the same reason the constants
// were: SoftwareUpdate.h declares a class that is now Swift, so it cannot enter
// this framework's bridging header (rule 43) — and the ported Swift still needs
// to call this. A free function is fine to *call* from Swift (rule 61); what
// Swift cannot do is export one (rule 19), which is why OakCompareVersionStrings.mm
// stays ObjC++.
//
// SoftwareUpdate.h imports this, so BundlesManager's Bundle.mm is unchanged.
#import <Foundation/Foundation.h>

NSComparisonResult OakCompareVersionStrings (NSString* lhsString, NSString* rhsString);
