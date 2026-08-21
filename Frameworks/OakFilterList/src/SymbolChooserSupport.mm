#import "SymbolChooserSupport.h"
#import "OakChooserMarkup.h"
#import <document/OakDocument.h>
#import <OakFoundation/NSString Additions.h>
#import <OakFoundation/OakFoundation.h>
#import <text/ranker.h>
#import <ns/ns.h>

// The C++ half of SymbolChooser, moved from SymbolChooser.mm (2026-08-20) so the panel
// itself could become Swift; see SymbolChooserSupport.h for what is here and why.
//
// The three bodies below came out of the original with `git show`, not retyping (rule 6),
// and the extraction asserts that at build time — see t_symbol_chooser_support.mm. The
// only edits are mechanical: the property and ivar reads the methods used
// (self.items, _selectionString, _TMDocument, self.filterString) became parameters, and
// each body gained the return its caller now needs. -setSelectionString:'s trailing
// table-view selection stayed behind in the controller, which is where it belongs.

@implementation SymbolChooserItem
- (id)objectForKey:(id)key { return [self valueForKey:key]; }
@end

static SymbolChooserItem* CreateItem (OakDocument* document, text::pos_t const& pos, NSString* symbol, std::vector< std::pair<size_t, size_t> > const& ranges)
{
	SymbolChooserItem* res = [SymbolChooserItem new];
	res.path            = document.path;
	res.identifier      = document.identifier.UUIDString;
	res.selectionString = [NSString stringWithCxxString:pos];
	res.name            = CreateAttributedStringWithMarkedUpRanges(to_s(symbol), ranges, NSLineBreakByTruncatingTail);
	res.infoString      = [document.displayName stringByAppendingFormat:@":%@", res.selectionString];
	return res;
}

@implementation SymbolChooserSupport
+ (NSArray<SymbolChooserItem*>*)itemsForDocument:(OakDocument*)document filterString:(NSString*)filterString
{
	NSMutableArray* res = [NSMutableArray array];
	if(document)
	{
		if(OakIsEmptyString(filterString))
		{
			[document enumerateSymbolsUsingBlock:^(text::pos_t const& pos, NSString* symbol){
				if(![symbol isEqualToString:@"-"])
					[res addObject:CreateItem(document, pos, symbol, std::vector< std::pair<size_t, size_t> >())];
			}];
		}
		else
		{
			std::string const filter = oak::normalize_filter(to_s(filterString));

			__block NSString* sectionName = nil;
			__block std::multimap<double, SymbolChooserItem*> rankedItems;

			[document enumerateSymbolsUsingBlock:^(text::pos_t const& pos, NSString* symbol){
				if([symbol isEqualToString:@"-"])
					return;

				BOOL indented = [symbol hasPrefix:@"\u2003"];
				if(!indented)
					sectionName = symbol;

				std::vector< std::pair<size_t, size_t> > ranges;
				if(double rank = oak::rank(filter, to_s(symbol), &ranges))
					rankedItems.emplace(1 - rank, CreateItem(document, pos, indented && sectionName ? [NSString stringWithFormat:@"%@ — %@", symbol, sectionName] : symbol, ranges));
			}];

			for(auto const& pair : rankedItems)
				[res addObject:pair.second];
		}
	}
	return res;
}

+ (NSUInteger)indexOfItemForSelectionString:(NSString*)selectionString inItems:(NSArray<SymbolChooserItem*>*)items
{
	std::map<text::pos_t, SymbolChooserItem*> symbolItems;
	for(SymbolChooserItem* item in items)
	{
		text::selection_t sel(to_s(item.selectionString));
		text::pos_t pos = sel.last().min();
		symbolItems.emplace(pos, item);
	}

	SymbolChooserItem* item = nil;
	for(text::range_t const& range : text::selection_t(to_s(selectionString)))
	{
		auto it = symbolItems.upper_bound(range.min());
		if(it != symbolItems.begin())
			item = (--it)->second;
	}

	return item ? [items indexOfObject:item] : NSNotFound;
}
@end
