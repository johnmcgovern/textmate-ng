// The C++ side of the DWScopeContext boundary.
//
// Exported only for the ObjC++ shims that still have to speak both languages:
// DocumentWindowController's C++-typed selectors (-variables,
// -updateEnvironment:forCommand:, -titleForDocument:withSetting:) merge these
// variables into a settings_t lookup, and settings_for_path takes a
// std::map<std::string, std::string>.
//
// Converting to an NSDictionary and back at every one of those call sites would
// be churn in service of nothing — those files are already C++ and are staying
// that way. So the boundary is C++-free where Swift reads it (DWScopeContext.h)
// and C++ where ObjC++ reads it, which is the split TMBundleModelCxx.h makes for
// the same reason.
//
// This header contains C++ and therefore must NOT be reachable from any Swift
// bridging header.
#import "DWScopeContext.h"
#import <map>
#import <string>

NS_ASSUME_NONNULL_BEGIN

@interface DWScopeContext (Cxx)
// The same rule as -effectiveSCMVariables, without the round trip through
// Foundation: the document's variables if it has any, otherwise the project's.
@property (nonatomic, readonly) std::map<std::string, std::string> const& effectiveSCMVariablesMap;
@end

NS_ASSUME_NONNULL_END
