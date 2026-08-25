#import "OTVStatusBarSupport.h"
#import <TMBundleModel/TMBundleItem.h>
#import <TMBundleModel/TMBundleModelCxx.h>
#import <bundles/bundles.h>
#import <text/ctype.h>
#import <ns/ns.h>
#import <OakFoundation/NSString Additions.h> // +stringWithCxxString:

// Moved out of OTVStatusBar.mm (rule 6): the queries and the ordering are
// unchanged, and the only edit is that the results leave as TMBundleItem rather
// than as bundles::item_ptr.

@implementation OTVStatusBarSupport
+ (NSArray<TMBundleItem*>*)grammarsForMenu
{
	// The multimap keyed on name with text::less_t is what ordered this before;
	// +[TMBundleItem itemsSortedByName:] is a stable_sort with the same
	// comparator, which is the same ordering including for equal names.
	std::vector<bundles::item_ptr> grammars;
	for(auto item : bundles::query(bundles::kFieldAny, NULL_STR, scope::wildcard, bundles::kItemTypeGrammar))
	{
		if(item->value_for_field(bundles::kFieldGrammarScope) != NULL_STR)
			grammars.push_back(item);
	}
	return [TMBundleItem itemsSortedByName:[TMBundleItem itemsWithCxxItems:grammars]];
}

+ (NSString*)grammarNameForFileType:(NSString*)fileType
{
	NSString* res = nil;
	for(auto const& item : bundles::query(bundles::kFieldGrammarScope, to_s(fileType)))
		res = [NSString stringWithCxxString:item->name()];
	return res;
}
@end
