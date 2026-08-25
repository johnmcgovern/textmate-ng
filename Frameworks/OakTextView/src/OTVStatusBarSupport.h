// The two bundles::query calls behind OTVStatusBar's grammar pop-up.
//
// `bundles` is C++ free functions over std::shared_ptr<bundles::item_t>, which
// Swift can neither call nor implement; TMBundleItem is this tree's ObjC-shaped
// model over exactly that, so the boundary is thin — it runs the queries and
// hands back model objects.
//
// It exists rather than reusing +[TMBundleItem itemsInBundle:ofKinds:] because
// that method deliberately passes `filter:false, includeDisabledItems:true` for
// the Bundle Editor, which lists what is *there*. The status bar lists what you
// can switch to, and takes bundles::query's defaults — `filter:true,
// includeDisabledItems:false`. Reusing the Bundle Editor's call would quietly put
// disabled grammars in the menu.
#import <Cocoa/Cocoa.h>

@class TMBundleItem;

@interface OTVStatusBarSupport : NSObject
// Every grammar that declares a scope, sorted by name with the same comparator
// and the same stability the ObjC++ multimap had. Hidden items are **not**
// filtered here: the menu builder skips them when adding rows, but the emptiness
// check that produces "No Grammars Loaded" runs against this unfiltered list.
+ (NSArray<TMBundleItem*>*)grammarsForMenu;

// The name of the grammar claiming `fileType`, or nil when none does. When more
// than one claims it the *last* wins, which is what the ObjC++ loop did by
// assigning on every iteration.
+ (NSString*)grammarNameForFileType:(NSString*)fileType;
@end
