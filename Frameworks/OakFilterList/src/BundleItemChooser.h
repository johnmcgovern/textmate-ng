// Hand-written ObjC declaration of the Swift BundleItemChooser (BundleItemChooser.swift),
// for its one caller AppController.mm in the app — so it is a public header. The panel's
// C++ lives in BundleItemChooserSupport; the contract here is pinned by
// t_bundle_item_chooser.mm (rule 18).
//
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
