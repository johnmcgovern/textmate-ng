#import "../src/SymbolChooserSupport.h"

// SymbolChooserSupport is the C++ SymbolChooser left behind when the panel became Swift.
// Its ranking half needs a real open document (rule 8, and the reason t_symbol_chooser.mm
// stops where it does), but the position matching does not: it takes the item list as a
// parameter, so it can be driven with hand-built items and is pinned properly here.
//
// -indexOfItemForSelectionString: answers "which symbol is the caret inside?" — the last
// item at or before the selection. Getting the boundary case wrong (at the position, one
// before, one past the end) puts the wrong row under the cursor when Jump to Symbol opens,
// which no build error and no other test would show.

static SymbolChooserItem* Item (NSString* selectionString, NSString* name)
{
	SymbolChooserItem* res = [SymbolChooserItem new];
	res.selectionString = selectionString;
	res.name            = [[NSAttributedString alloc] initWithString:name];
	res.infoString      = name;
	return res;
}

static NSArray<SymbolChooserItem*>* Items ()
{
	return @[ Item(@"1:1", @"first"), Item(@"10:1", @"second"), Item(@"20:1", @"third") ];
}

void setup ()
{
	NSApplicationLoad();
}

void test_symbol_support_matches_exact_position ()
{
	OAK_ASSERT([SymbolChooserSupport indexOfItemForSelectionString:@"10:1" inItems:Items()] == 1);
}

void test_symbol_support_matches_the_symbol_the_caret_is_inside ()
{
	// Between the second and third symbols: the second one owns the caret.
	OAK_ASSERT([SymbolChooserSupport indexOfItemForSelectionString:@"15:1" inItems:Items()] == 1);
	// Past the last symbol: still the last one.
	OAK_ASSERT([SymbolChooserSupport indexOfItemForSelectionString:@"99:1" inItems:Items()] == 2);
}

void test_symbol_support_before_the_first_symbol_matches_nothing ()
{
	// upper_bound lands on begin(), so there is no preceding item to select.
	NSArray* items = @[ Item(@"10:1", @"second"), Item(@"20:1", @"third") ];
	OAK_ASSERT([SymbolChooserSupport indexOfItemForSelectionString:@"1:1" inItems:items] == NSNotFound);
}

void test_symbol_support_empty_items_is_not_found ()
{
	OAK_ASSERT([SymbolChooserSupport indexOfItemForSelectionString:@"1:1" inItems:@[]] == NSNotFound);
}

void test_symbol_support_nil_document_has_no_items ()
{
	OAK_ASSERT([SymbolChooserSupport itemsForDocument:nil filterString:nil].count == 0);
	OAK_ASSERT([SymbolChooserSupport itemsForDocument:nil filterString:@"main"].count == 0);
}

void test_symbol_chooser_item_answers_objectForKey ()
{
	// OakChooser's row builder asks the item for its column by key; that path is what makes
	// the symbol name reach the table at all.
	SymbolChooserItem* item = Item(@"1:1", @"symbolName");
	OAK_ASSERT([[item objectForKey:@"name"] isKindOfClass:NSAttributedString.class]);
	OAK_ASSERT([[[item objectForKey:@"name"] string] isEqualToString:@"symbolName"]);
}
