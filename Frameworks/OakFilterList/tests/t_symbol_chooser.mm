#import "../src/SymbolChooser.h"

// Written against the ObjC++ SymbolChooser, before the Swift port (rule 18). This is the
// ⇧⌘T "Jump to Symbol" panel: a shared OakChooser subclass driven entirely from
// OakDocumentView.mm, which sets .TMDocument and .selectionString and reads nothing back.
// So the contract is the property surface plus the two OakChooser hooks it overrides —
// and, since OakChooser is now Swift, that an ObjC++ subclass of it still works at all.
//
// The symbol list itself comes from -[OakDocument enumerateSymbolsUsingBlock:] over a real
// open document; there is none in a bare test process, so the ranking is left to the app
// (rule 8) and what is pinned here is everything reachable without one. The nil-document
// path is asserted because it is the state the panel is left in: -windowWillClose: sets
// .TMDocument = nil, and -updateItems:/-updateStatusText: must both survive that.

void setup ()
{
	NSApplicationLoad();
}

void test_symbol_chooser_shared_instance_is_a_chooser ()
{
	SymbolChooser* chooser = SymbolChooser.sharedInstance;
	OAK_ASSERT(chooser != nil);
	OAK_ASSERT(chooser == SymbolChooser.sharedInstance);
	OAK_ASSERT([chooser isKindOfClass:OakChooser.class]);
}

void test_symbol_chooser_builds_its_window_and_views ()
{
	SymbolChooser* chooser = [SymbolChooser new];
	OAK_ASSERT(chooser.window != nil);
	OAK_ASSERT([chooser.window.title hasPrefix:@"Jump to Symbol"]);
	// The base's lazily-built views the init wires into the titlebar and footer.
	OAK_ASSERT(chooser.searchField != nil);
	OAK_ASSERT(chooser.statusTextField != nil);
	OAK_ASSERT(chooser.itemCountTextField != nil);
	OAK_ASSERT(chooser.window.initialFirstResponder == chooser.searchField);
}

void test_symbol_chooser_keeps_its_selector_surface ()
{
	SEL const selectors[] = {
		@selector(TMDocument),      @selector(setTMDocument:),
		@selector(selectionString), @selector(setSelectionString:),
		@selector(updateItems:),
		@selector(updateStatusText:),
		@selector(windowWillClose:),
	};

	for(SEL selector : selectors)
		OAK_ASSERT([SymbolChooser instancesRespondToSelector:selector]);
	OAK_ASSERT([SymbolChooser respondsToSelector:@selector(sharedInstance)]);
}

void test_symbol_chooser_without_a_document_is_empty_and_titled ()
{
	SymbolChooser* chooser = [SymbolChooser new];
	chooser.TMDocument = nil;

	[chooser updateItems:nil];
	OAK_ASSERT(chooser.items.count == 0);

	[chooser updateStatusText:nil];
	OAK_ASSERT([chooser.statusTextField.stringValue isEqualToString:@""]);

	OAK_ASSERT([chooser.window.title isEqualToString:@"Jump to Symbol"]);
}

void test_symbol_chooser_filter_string_round_trips ()
{
	SymbolChooser* chooser = [SymbolChooser new];
	chooser.filterString = @"main"; // reaches -updateFilterString: -> -updateItems: with no document
	OAK_ASSERT([chooser.filterString isEqualToString:@"main"]);
	OAK_ASSERT(chooser.items.count == 0);
}

void test_symbol_chooser_selection_string_without_items_is_harmless ()
{
	SymbolChooser* chooser = [SymbolChooser new];
	chooser.selectionString = @"1:1"; // the empty-items path through the C++ position matching
	OAK_ASSERT([chooser.selectionString isEqualToString:@"1:1"]);
}
