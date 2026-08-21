// The scope is a TMScopeContext, not a scope::context_t: Swift cannot express the C++ type
// (rule 17), and TMBundleModel already provides this box for exactly that reason. Callers
// wanting the wildcard fallback must ask for +wildcardScope explicitly — TMScopeContext's
// own +currentScope falls back to the *empty* scope, which matches only selectors that
// accept it and would leave this panel showing nothing.
#import "OakChooser.h"
#import <TMBundleModel/TMScopeContext.h>

@interface BundleItemChooser : OakChooser
@property (class, readonly) BundleItemChooser* sharedInstance;
@property (nonatomic) NSString* path;
@property (nonatomic) NSString* directory;
@property (nonatomic) TMScopeContext* scope;
@property (nonatomic) BOOL hasSelection;
@property (nonatomic) SEL editAction;
@end
