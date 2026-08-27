#import "OakTextViewTesting.h"
#import <document/OakDocument.h>
#import <test/bundle_index.h>
#import <bundles/bundles.h>
#import <ns/ns.h>
#import <Cocoa/Cocoa.h>

// Coverage for OakDocumentView, written before the port. 781 lines, and the
// integration point of this framework: it owns the gutter, the status bar and the
// text view, and answers four protocols on their behalf.
//
// Its -initWithFrame: builds a real OakTextView — the 4633-line permanently-ObjC++
// class — which is why a probe came first. It constructs in ~20ms with no window,
// so everything here is a real view hierarchy rather than a mock.
//
// Two things are deliberately *not* pinned:
//
//   * -setTabSize: and the two -setIndentWith… actions, because each calls
//     settings_t::set, which opens with ASSERT_NE(default_settings_path(),
//     NULL_STR). In a test process that path is unset, so calling them aborts the
//     process rather than failing a test. Only -takeTabSizeFrom:'s reject branch,
//     which returns before the setter, is reachable.
//   * Anything needing a window: the two pasteboard-history actions, the symbol
//     chooser, and the bookmark popover all begin by converting a rect to screen
//     coordinates through self.window.

static char const* kGrammarPlain =
	"{	name       = 'Plain Text';\n"
	"	scopeName  = 'text.plain';\n"
	"	uuid       = '3130E4FA-B10E-11D9-9F75-000D93589AF6';\n"
	"	patterns   = ( );\n"
	"}\n";

void setup ()
{
	NSApplicationLoad();

	test::bundle_index_t bundleIndex;
	bundleIndex.add(bundles::kItemTypeGrammar, std::string(kGrammarPlain));
	bundleIndex.commit();
}

static std::string describe (NSString* str)
{
	return str ? to_s(str) : std::string("«nil»");
}

static OakDocumentView* make_view ()
{
	return [[OakDocumentView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
}

static NSMenuItem* make_item (SEL action)
{
	NSMenu* menu = [[NSMenu alloc] initWithTitle:@"test"];
	return [menu addItemWithTitle:@"item" action:action keyEquivalent:@""];
}

static std::string menu_titles (NSMenu* menu)
{
	NSMutableArray* titles = [NSMutableArray array];
	for(NSMenuItem* item in menu.itemArray)
		[titles addObject:item.isSeparatorItem ? @"«separator»" : item.title];
	return to_s([titles componentsJoinedByString:@" | "]);
}

// -toggleLineNumbers: writes NSUserDefaults, and -initWithFrame: *reads* the same
// key — so a test that leaves it set changes how the next view is built (rule 53).
struct line_numbers_default_t
{
	line_numbers_default_t () : _saved([NSUserDefaults.standardUserDefaults objectForKey:kKey]) { }
	~line_numbers_default_t ()
	{
		if(_saved)
				[NSUserDefaults.standardUserDefaults setObject:_saved forKey:kKey];
		else	[NSUserDefaults.standardUserDefaults removeObjectForKey:kKey];
	}
private:
	static NSString* const kKey;
	id _saved;
};
NSString* const line_numbers_default_t::kKey = @"DocumentView Disable Line Numbers";

// ==================================================================
// = The surface a Swift port has to keep reachable                 =
// ==================================================================

void test_document_view_selector_surface ()
{
	Class cls = OakDocumentView.class;

	OAK_ASSERT_EQ((bool)[cls isSubclassOfClass:NSView.class], true);

	for(NSString* name in @[ @"textView", @"document", @"hideStatusBar" ])
		OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:NSSelectorFromString(name)], true);

	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setDocument:)],      true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setHideStatusBar:)], true);

	// textView is readonly — the port must not quietly widen it.
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:NSSelectorFromString(@"setTextView:")], false);

	// The four protocols it answers. The first two return GVLineRecord, a C++ struct
	// *by value*, which this test was written expecting to block a Swift port.
	// **It does not** — the importer brings trivially-copyable C++ structs across,
	// so they were ported like everything else. Left asserting the surface, which is
	// what a pin is for, rather than rewritten to match the outcome.
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(lineRecordForPosition:)],          true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(lineFragmentForLine:column:)],     true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(imageForLine:inColumnWithIdentifier:state:)], true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(widthForColumnWithIdentifier:)],   true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(userDidClickColumnWithIdentifier:atLine:)], true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(showBundleItemSelector:)],         true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(showSymbolSelector:)],             true);
}

void test_document_view_builds_its_three_children ()
{
	OakDocumentView* view = make_view();

	OAK_ASSERT_EQ((bool)(view.textView != nil),  true);
	OAK_ASSERT_EQ((bool)(view.statusBar != nil), true);

	// A placeholder document is installed by the initialiser rather than left nil,
	// so every accessor below is safe before a real document arrives.
	OAK_ASSERT_EQ((bool)(view.document != nil), true);
	OAK_ASSERT_EQ(describe(view.document.fileType), std::string("text.plain"));

	OAK_ASSERT_EQ(describe(view.accessibilityLabel), std::string("Editor"));
}

// ==================================================================
// = Geometry: everything the gutter lays out comes from these two  =
// ==================================================================

void test_document_view_column_width_is_always_odd ()
{
	OakDocumentView* view = make_view();

	// floor((lineHeight-1)/2)*2 + 1 — deliberately odd so a centred icon lands on
	// a whole pixel rather than straddling two.
	CGFloat width = [view widthForColumnWithIdentifier:nil];
	OAK_ASSERT_EQ((long)((long)width % 2), (long)1);

	// It is derived from the line height, not from the column identifier: every
	// column is the same width, which is why the argument is ignored.
	OAK_ASSERT_EQ((double)[view widthForColumnWithIdentifier:@"bookmarks"], (double)width);
	OAK_ASSERT_EQ((double)[view widthForColumnWithIdentifier:@"foldings"],  (double)width);

	CGFloat lineHeight = [view lineHeight];
	OAK_ASSERT_EQ((double)width, (double)(floor((lineHeight-1) / 2) * 2 + 1));
	OAK_ASSERT_EQ((bool)(lineHeight > 0), true);
}

// ==================================================================
// = The status bar can be taken away and put back                  =
// ==================================================================

void test_document_view_hide_status_bar_replaces_rather_than_hides ()
{
	OakDocumentView* view = make_view();

	OTVStatusBar* original = view.statusBar;
	OAK_ASSERT_EQ((bool)(original.superview == view), true);

	// Hiding *destroys* the bar rather than setting it hidden, and unhiding builds
	// a new one — so nothing may cache it across the toggle.
	view.hideStatusBar = YES;
	OAK_ASSERT_EQ((bool)(view.statusBar == nil), true);
	OAK_ASSERT_EQ((bool)(original.superview == nil), true);
	OAK_ASSERT_EQ((bool)(original.delegate == nil), true);
	OAK_ASSERT_EQ((bool)(original.target == nil), true);

	view.hideStatusBar = NO;
	OAK_ASSERT_EQ((bool)(view.statusBar != nil), true);
	OAK_ASSERT_EQ((bool)(view.statusBar == original), false);
	OAK_ASSERT_EQ((bool)(view.statusBar.superview == view), true);

	// The new bar is wired back to the view, which is what makes the tab-size menu
	// and the two pop-up selectors work again.
	OAK_ASSERT_EQ((bool)(view.statusBar.delegate == view), true);
	OAK_ASSERT_EQ((bool)(view.statusBar.target == view), true);
}

void test_document_view_hide_status_bar_ignores_an_equal_value ()
{
	OakDocumentView* view = make_view();

	// The guard is not decoration: without it, setting NO on a visible bar would
	// build a second one and add it to the view.
	OTVStatusBar* original = view.statusBar;
	view.hideStatusBar = NO;
	OAK_ASSERT_EQ((bool)(view.statusBar == original), true);
}

// ==================================================================
// = Auxiliary views                                                =
// ==================================================================

void test_document_view_auxiliary_views_are_kept_per_edge ()
{
	OakDocumentView* view = make_view();

	NSView* top    = [NSView new];
	NSView* bottom = [NSView new];

	[view addAuxiliaryView:top atEdge:NSMaxYEdge];
	[view addAuxiliaryView:bottom atEdge:NSMinYEdge];

	OAK_ASSERT_EQ((bool)(top.superview == view),    true);
	OAK_ASSERT_EQ((bool)(bottom.superview == view), true);

	[view removeAuxiliaryView:top];
	OAK_ASSERT_EQ((bool)(top.superview == nil),     true);
	OAK_ASSERT_EQ((bool)(bottom.superview == view), true);
}

void test_document_view_removing_an_unknown_auxiliary_view_is_a_no_op ()
{
	OakDocumentView* view = make_view();

	// The early return matters: without it a view belonging to somebody else would
	// be pulled out of its own superview.
	NSView* container = [NSView new];
	NSView* stranger  = [NSView new];
	[container addSubview:stranger];

	[view removeAuxiliaryView:stranger];
	OAK_ASSERT_EQ((bool)(stranger.superview == container), true);
}

// ==================================================================
// = -validateMenuItem:, which writes to the items it validates     =
// ==================================================================

void test_document_view_validate_renames_the_line_numbers_item ()
{
	line_numbers_default_t guard;
	OakDocumentView* view = make_view();

	// The validator is also the *only* thing that titles this item — the menu ships
	// with a placeholder — so a port that drops the rename leaves a nonsense menu.
	NSMenuItem* item = make_item(@selector(toggleLineNumbers:));
	OAK_ASSERT_EQ((bool)[view validateMenuItem:item], true);
	OAK_ASSERT_EQ(describe(item.title), std::string("Hide Line Numbers"));

	[view toggleLineNumbers:nil];
	OAK_ASSERT_EQ((bool)[view validateMenuItem:item], true);
	OAK_ASSERT_EQ(describe(item.title), std::string("Show Line Numbers"));
}

void test_document_view_toggle_line_numbers_persists_the_choice ()
{
	line_numbers_default_t guard;
	OakDocumentView* view = make_view();

	// Hiding writes the key; showing *removes* it rather than writing NO, so the
	// default stays the absence of a value.
	[view toggleLineNumbers:nil];
	OAK_ASSERT_EQ((bool)([NSUserDefaults.standardUserDefaults objectForKey:@"DocumentView Disable Line Numbers"] != nil), true);

	[view toggleLineNumbers:nil];
	OAK_ASSERT_EQ((bool)([NSUserDefaults.standardUserDefaults objectForKey:@"DocumentView Disable Line Numbers"] != nil), false);
}

void test_document_view_validate_reflects_indent_style ()
{
	OakDocumentView* view = make_view();

	NSMenuItem* tabs   = make_item(NSSelectorFromString(@"setIndentWithTabs:"));
	NSMenuItem* spaces = make_item(NSSelectorFromString(@"setIndentWithSpaces:"));

	// The two are exact opposites, driven by the text view rather than the document.
	view.textView.softTabs = NO;
	[view validateMenuItem:tabs];
	[view validateMenuItem:spaces];
	OAK_ASSERT_EQ((long)tabs.state,   (long)NSControlStateValueOn);
	OAK_ASSERT_EQ((long)spaces.state, (long)NSControlStateValueOff);

	view.textView.softTabs = YES;
	[view validateMenuItem:tabs];
	[view validateMenuItem:spaces];
	OAK_ASSERT_EQ((long)tabs.state,   (long)NSControlStateValueOff);
	OAK_ASSERT_EQ((long)spaces.state, (long)NSControlStateValueOn);
}

void test_document_view_validate_checks_the_matching_tab_size ()
{
	OakDocumentView* view = make_view();
	view.textView.tabSize = 4;

	NSMenuItem* four = make_item(NSSelectorFromString(@"takeTabSizeFrom:"));
	four.tag = 4;
	NSMenuItem* eight = make_item(NSSelectorFromString(@"takeTabSizeFrom:"));
	eight.tag = 8;

	[view validateMenuItem:four];
	[view validateMenuItem:eight];
	OAK_ASSERT_EQ((long)four.state,  (long)NSControlStateValueOn);
	OAK_ASSERT_EQ((long)eight.state, (long)NSControlStateValueOff);
}

void test_document_view_validate_names_a_non_predefined_tab_size ()
{
	OakDocumentView* view = make_view();
	NSMenuItem* item = make_item(NSSelectorFromString(@"showTabSizeSelectorPanel:"));

	// One of 2/3/4/8 leaves the item as a plain "Other…", unchecked.
	view.textView.tabSize = 4;
	[view validateMenuItem:item];
	OAK_ASSERT_EQ(describe(item.title), std::string("Other…"));
	OAK_ASSERT_EQ((long)item.state, (long)NSControlStateValueOff);

	// Anything else names itself in the title and checks the row — this is the only
	// place a tab size of 5 is visible in the interface at all.
	view.textView.tabSize = 5;
	[view validateMenuItem:item];
	OAK_ASSERT_EQ(describe(item.title), std::string("Other (5)…"));
	OAK_ASSERT_EQ((long)item.state, (long)NSControlStateValueOn);
}

void test_document_view_take_tab_size_rejects_a_non_positive_tag ()
{
	OakDocumentView* view = make_view();
	view.textView.tabSize = 4;

	// The guard is `[sender tag] > 0`. Its other branch reaches settings_t::set and
	// so cannot be exercised here — see the header comment.
	NSMenuItem* item = make_item(NSSelectorFromString(@"takeTabSizeFrom:"));
	item.tag = 0;
	[view takeTabSizeFrom:item];
	OAK_ASSERT_EQ((size_t)view.textView.tabSize, (size_t)4);
}

// ==================================================================
// = The three menus it builds                                      =
// ==================================================================

void test_document_view_symbol_menu_falls_back_when_empty ()
{
	OakDocumentView* view = make_view();

	NSPopUpButton* popUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect];
	[view showSymbolSelector:popUp];

	// A plain-text placeholder has no symbols, and the fallback row is inert.
	OAK_ASSERT_EQ(menu_titles(popUp.menu), std::string("No symbols to show for current document."));
	OAK_ASSERT_EQ((bool)(popUp.menu.itemArray.firstObject.action == @selector(nop:)), true);
}

void test_document_view_bundle_item_menu_lists_bundles ()
{
	OakDocumentView* view = make_view();

	NSPopUpButton* popUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect];
	[view showBundleItemSelector:popUp];

	// The fixture index holds a bundle with no menu, so every row is filtered out.
	//
	// This assertion was inverted deliberately. It first pinned the ObjC++ as
	// measured — a silently **blank** menu, because the fallback was guarded on the
	// unfiltered bundle list while the rows came from the filtered one. The port
	// preserved that; the following commit fixed it by testing the built menu
	// instead. So the empty case now explains itself, which is what the row is for.
	OAK_ASSERT_EQ(menu_titles(popUp.menu), std::string("No Bundles Loaded"));
	OAK_ASSERT_EQ((bool)(popUp.menu.itemArray.firstObject.action == @selector(nop:)), true);
}

void test_document_view_bookmarks_menu_is_inert_when_empty ()
{
	OakDocumentView* view = make_view();

	NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Bookmarks"];
	[view updateBookmarksMenu:menu];

	// No bookmarks means no separator, and "Clear Bookmarks" gets -nop: so it draws
	// disabled rather than offering to clear nothing.
	OAK_ASSERT_EQ(menu_titles(menu), std::string("Clear Bookmarks"));
	OAK_ASSERT_EQ((bool)([menu itemWithTitle:@"Clear Bookmarks"].action == @selector(nop:)), true);
}

void test_document_view_bookmarks_menu_lists_marks_with_padded_lines ()
{
	OakDocumentView* view = make_view();
	view.document = [OakDocument documentWithString:@"one\ntwo\nthree\n" fileType:@"text.plain" customName:@"bookmarks"];
	[view.document setMarkOfType:OakDocumentBookmarkIdentifier atPosition:text::pos_t(1, 0) content:nil];

	NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Bookmarks"];
	[view updateBookmarksMenu:menu];

	// The line number is padded to four columns so the excerpts line up, and it is
	// 1-based in the title while the mark is 0-based.
	//
	// The padding is U+2007 FIGURE SPACE, not a space — text::pad uses it so the
	// gap is exactly one digit wide in a proportional menu font. Written as escapes
	// for the same reason the em space in t_status_bar.mm is: as literals these are
	// three invisible characters that a reader would take for spaces.
	OAK_ASSERT_EQ(menu_titles(menu), std::string("\u2007\u2007\u2007" "2: two | «separator» | Clear Bookmarks"));
	OAK_ASSERT_EQ((bool)([menu itemWithTitle:@"Clear Bookmarks"].action == @selector(clearAllBookmarks:)), true);
}

// ==================================================================
// = The gutter's bookmark column, whose priority is map ordering   =
// ==================================================================

void test_document_view_gutter_image_priority ()
{
	OakDocumentView* view = make_view();
	view.document = [OakDocument documentWithString:@"one\ntwo\nthree\n" fileType:@"text.plain" customName:@"gutter"];

	// A line with nothing on it draws nothing in the regular state...
	OAK_ASSERT_EQ((bool)([view imageForLine:0 inColumnWithIdentifier:@"bookmarks" state:GutterViewRowStateRegular] != nil), false);

	// ...but hovering offers to add one. That is the std::map's key 3, reached only
	// because the map is empty — a port that returns early on "no marks" loses the
	// add affordance entirely.
	OAK_ASSERT_EQ((bool)([view imageForLine:0 inColumnWithIdentifier:@"bookmarks" state:GutterViewRowStateRollover] != nil), true);

	[view.document setMarkOfType:OakDocumentBookmarkIdentifier atPosition:text::pos_t(0, 0) content:nil];
	OAK_ASSERT_EQ((bool)([view imageForLine:0 inColumnWithIdentifier:@"bookmarks" state:GutterViewRowStateRegular] != nil), true);

	// An unknown column draws nothing rather than falling through to bookmarks.
	OAK_ASSERT_EQ((bool)([view imageForLine:0 inColumnWithIdentifier:@"nonesuch" state:GutterViewRowStateRegular] != nil), false);
}

void test_document_view_marks_changing_notifies_the_gutter ()
{
	OakDocumentView* view = make_view();

	__block NSInteger count = 0;
	id observer = [NSNotificationCenter.defaultCenter addObserverForName:GVColumnDataSourceDidChange object:view queue:nil usingBlock:^(NSNotification*){ ++count; }];

	// The gutter has no way to know a mark moved; this repost is the whole of the
	// wiring between the document's marks and the column redrawing.
	[view documentMarksDidChange:nil];
	OAK_ASSERT_EQ((long)count, (long)1);

	[NSNotificationCenter.defaultCenter removeObserver:observer];
}
