#import "OakTextViewTesting.h"
#import <test/bundle_index.h>
#import <bundles/bundles.h>
#import <ns/ns.h>
#import <Cocoa/Cocoa.h>

// Coverage for OTVStatusBar, written before the port. 339 lines whose public
// header is entirely C++-free — the C++ is confined to one std::clamp and two
// bundles::query calls, which is what makes this the next portable file after
// OakChoiceMenu.
//
// Most of the class is setters whose only effect is on a control that is private
// to the .mm, so almost everything here goes through the Testing category. Three
// of those setters do a transformation that reads like a typo and is not one.

static char const* kGrammarPlain =
	"{	name       = 'Plain Text';\n"
	"	scopeName  = 'text.plain';\n"
	"	uuid       = '3130E4FA-B10E-11D9-9F75-000D93589AF6';\n"
	"	patterns   = ( );\n"
	"}\n";

static char const* kGrammarC =
	"{	name       = 'C';\n"
	"	scopeName  = 'source.c';\n"
	"	uuid       = '25066DC2-6B1D-11D9-9D5B-000D93589AF6';\n"
	"	patterns   = ( );\n"
	"}\n";

// No scopeName, so -grammarPopUpButtonWillPopUp: filters it out: the menu lists
// grammars you can *switch to*, and one with no scope cannot be selected.
static char const* kGrammarWithoutScope =
	"{	name       = 'Scopeless';\n"
	"	uuid       = '11111111-2222-3333-4444-555555555555';\n"
	"	patterns   = ( );\n"
	"}\n";

void setup ()
{
	NSApplicationLoad();

	test::bundle_index_t bundleIndex;
	bundleIndex.add(bundles::kItemTypeGrammar, std::string(kGrammarPlain));
	bundleIndex.add(bundles::kItemTypeGrammar, std::string(kGrammarC));
	bundleIndex.add(bundles::kItemTypeGrammar, std::string(kGrammarWithoutScope));
	bundleIndex.commit();
}

static std::string describe (NSString* str)
{
	return str ? to_s(str) : std::string("«nil»");
}

static OTVStatusBar* make_bar ()
{
	return [[OTVStatusBar alloc] initWithFrame:NSMakeRect(0, 0, 600, 24)];
}

static std::string menu_titles (NSMenu* menu)
{
	NSMutableArray* titles = [NSMutableArray array];
	for(NSMenuItem* item in menu.itemArray)
		[titles addObject:item.isSeparatorItem ? @"«separator»" : item.title];
	return to_s([titles componentsJoinedByString:@" | "]);
}

// ==================================================================
// = The surface a Swift port has to keep reachable                 =
// ==================================================================

void test_status_bar_selector_surface ()
{
	Class cls = OTVStatusBar.class;

	OAK_ASSERT_EQ((bool)[cls isSubclassOfClass:NSVisualEffectView.class], true);

	for(NSString* name in @[ @"selectionString", @"grammarName", @"symbolName", @"fileType", @"softTabs", @"tabSize", @"delegate", @"target" ])
	{
		OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:NSSelectorFromString(name)], true);
		OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:NSSelectorFromString([NSString stringWithFormat:@"set%@%@:", [name substringToIndex:1].uppercaseString, [name substringFromIndex:1]])], true);
	}

	// rule 4: the getter is spelled isRecordingMacro while the property — and the
	// setter — are recordingMacro. Swift generates only one of those unless told.
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(isRecordingMacro)],  true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setRecordingMacro:)],true);

	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(showBundlesMenu:)], true);
}

void test_status_bar_is_a_titlebar_effect_view ()
{
	OTVStatusBar* bar = make_bar();

	// It sits under the editor and has to read as chrome rather than as content.
	OAK_ASSERT_EQ((long)bar.material,     (long)NSVisualEffectMaterialTitlebar);
	OAK_ASSERT_EQ((long)bar.blendingMode, (long)NSVisualEffectBlendingModeWithinWindow);
	OAK_ASSERT_EQ((long)bar.state,        (long)NSVisualEffectStateFollowsWindowActiveState);
	OAK_ASSERT_EQ((bool)bar.wantsLayer, true);
}

void test_status_bar_builds_all_five_controls ()
{
	OTVStatusBar* bar = make_bar();

	OAK_ASSERT_EQ((bool)(bar.selectionField != nil),       true);
	OAK_ASSERT_EQ((bool)(bar.grammarPopUp != nil),         true);
	OAK_ASSERT_EQ((bool)(bar.tabSizePopUp != nil),         true);
	OAK_ASSERT_EQ((bool)(bar.bundleItemsPopUp != nil),     true);
	OAK_ASSERT_EQ((bool)(bar.symbolPopUp != nil),          true);
	OAK_ASSERT_EQ((bool)(bar.macroRecordingButton != nil), true);

	// The accessibility labels are the only names these controls have — none of
	// them shows a title — so they are the whole of its VoiceOver surface.
	OAK_ASSERT_EQ(describe(bar.grammarPopUp.accessibilityLabel),         std::string("Grammar"));
	OAK_ASSERT_EQ(describe(bar.bundleItemsPopUp.accessibilityLabel),     std::string("Bundle Item"));
	OAK_ASSERT_EQ(describe(bar.symbolPopUp.accessibilityLabel),          std::string("Symbol"));
	OAK_ASSERT_EQ(describe(bar.macroRecordingButton.accessibilityLabel), std::string("Record a macro"));

	// The tab-size pop-up is the one that pulls down rather than showing its
	// selection — its title is the current setting, not a chosen item.
	OAK_ASSERT_EQ((bool)bar.tabSizePopUp.pullsDown, true);
}

// ==================================================================
// = The three setters that transform what they are given           =
// ==================================================================

void test_status_bar_selection_string_is_prettified_for_display ()
{
	OTVStatusBar* bar = make_bar();

	// "1:1&2:1" is two carets; "3x4" is a rectangular selection. The bar shows
	// them as "1:1, 2:1" and "3×4" — a *display* transformation, so the property
	// keeps what it was handed while the field shows the pretty form.
	bar.selectionString = @"1:1&2:1";
	OAK_ASSERT_EQ(describe(bar.selectionString), std::string("1:1&2:1"));
	OAK_ASSERT_EQ(describe(bar.selectionField.stringValue), std::string("1:1, 2:1"));

	bar.selectionString = @"3x4";
	OAK_ASSERT_EQ(describe(bar.selectionField.stringValue), std::string("3×4"));

	// Both at once, and the × is U+00D7 rather than the letter x.
	bar.selectionString = @"1:1&3x4";
	OAK_ASSERT_EQ(describe(bar.selectionField.stringValue), std::string("1:1, 3×4"));
}

void test_status_bar_selection_string_ignores_an_equal_value ()
{
	OTVStatusBar* bar = make_bar();
	bar.selectionString = @"1:1";

	// The field is written to only when the value changes. The caret position
	// updates on every keystroke, so this early return is on a hot path.
	bar.selectionField.stringValue = @"«untouched»";
	bar.selectionString = @"1:1";
	OAK_ASSERT_EQ(describe(bar.selectionField.stringValue), std::string("«untouched»"));
}

void test_status_bar_empty_names_have_placeholders ()
{
	OTVStatusBar* bar = make_bar();

	// **The placeholder never appears on a fresh bar.** Both setters begin
	// `if(_x == newX || [_x isEqualToString:newX]) return;`, and on a new bar the
	// backing field is already nil — so setting nil returns before the `?:` that
	// would have supplied "(no grammar)". The menu simply stays empty.
	bar.grammarName = nil;
	OAK_ASSERT_EQ((size_t)bar.grammarPopUp.numberOfItems, (size_t)0);

	bar.symbolName = nil;
	OAK_ASSERT_EQ((size_t)bar.symbolPopUp.numberOfItems, (size_t)0);

	// It is reachable only by going *back* to nil from a real name, which is what
	// happens when a document's grammar is cleared.
	bar.grammarName = @"C";
	bar.grammarName = nil;
	OAK_ASSERT_EQ(describe(bar.grammarPopUp.itemArray.firstObject.title), std::string("(no grammar)"));

	bar.symbolName = @"main()";
	bar.symbolName = nil;
	OAK_ASSERT_EQ(describe(bar.symbolPopUp.itemArray.firstObject.title), std::string("Symbols"));

	// And a real name replaces the whole menu rather than appending to it.
	bar.grammarName = @"C";
	OAK_ASSERT_EQ((size_t)bar.grammarPopUp.numberOfItems, (size_t)1);
	OAK_ASSERT_EQ(describe(bar.grammarPopUp.itemArray.firstObject.title), std::string("C"));
}

void test_status_bar_tab_size_title_uses_an_em_space ()
{
	OTVStatusBar* bar = make_bar();

	// The separator is U+2003 EM SPACE, not a run of ordinary spaces.
	//
	// Written as `\u2003` on purpose. The first draft of this test carried the
	// character itself — invisible in a diff, and exactly the mistake that had to
	// be caught by hex-diffing during the SymbolChooser port earlier in this
	// migration. It passed, which is the problem: nothing would have told the next
	// reader that the space is not a space.
	bar.tabSize = 4;
	bar.softTabs = NO;
	OAK_ASSERT_EQ(describe(bar.tabSizePopUp.title), std::string("Tab Size:\u2003" "4"));

	bar.softTabs = YES;
	OAK_ASSERT_EQ(describe(bar.tabSizePopUp.title), std::string("Soft Tabs:\u2003" "4"));

	bar.tabSize = 8;
	OAK_ASSERT_EQ(describe(bar.tabSizePopUp.title), std::string("Soft Tabs:\u2003" "8"));
}

// ==================================================================
// = Macro recording, which is a timer and a cosine                 =
// ==================================================================

void test_status_bar_recording_starts_and_stops_a_timer ()
{
	OTVStatusBar* bar = make_bar();

	OAK_ASSERT_EQ((bool)(bar.recordingTimer != nil), false);

	bar.recordingMacro = YES;
	OAK_ASSERT_EQ((bool)bar.isRecordingMacro, true);
	OAK_ASSERT_EQ((bool)(bar.recordingTimer != nil), true);
	OAK_ASSERT_EQ((bool)bar.recordingTimer.isValid, true);

	NSTimer* timer = bar.recordingTimer;
	bar.recordingMacro = NO;
	OAK_ASSERT_EQ((bool)(bar.recordingTimer != nil), false);
	// The old timer is invalidated rather than dropped — an orphan would keep
	// firing against the bar forever.
	OAK_ASSERT_EQ((bool)timer.isValid, false);
}

void test_status_bar_stopping_resets_the_pulse ()
{
	OTVStatusBar* bar = make_bar();

	bar.recordingMacro = YES;
	bar.recordingTime = 5;
	bar.recordingMacro = NO;

	// Stopping rewinds the animation clock and runs one frame, so the button is
	// left at the pulse's trough rather than wherever it happened to be:
	// clamp(0.70 + 0.30·cos(π + 0), 0, 1) = 0.40.
	//
	// The clock reads 0.075 rather than 0 afterwards, because the frame that
	// computes the trough increments it on its way out. Pinned as measured: the
	// alpha is the point, and the leftover tick is what the code does.
	OAK_ASSERT_LT((double)fabs(bar.recordingTime - 0.075), (double)0.0001);
	OAK_ASSERT_LT((double)fabs(bar.macroRecordingButton.alphaValue - 0.40), (double)0.0001);
}

// ==================================================================
// = The tab-size menu, built through MenuBuilder's C++ DSL         =
// ==================================================================

void test_status_bar_tab_size_menu_shape ()
{
	OTVStatusBar* bar = make_bar();

	// Built with MBMenu/MBCreateMenu, whose API is a C++ DSL — MenuBuilder is
	// blocked and goes last — so a Swift port has to reproduce this menu with
	// plain NSMenu calls. Pinned exactly so "reproduce" is checkable rather than
	// asserted.
	OAK_ASSERT_EQ(menu_titles(bar.tabSizePopUp.menu), std::string("Current Indent | Indent Size | 2 | 3 | 4 | 8 | Other… | «separator» | Indent Using | Tabs | Spaces"));

	NSMenu* menu = bar.tabSizePopUp.menu;
	// The four size items carry their size as the tag, which is what
	// -takeTabSizeFrom: reads.
	OAK_ASSERT_EQ((long)[menu itemWithTitle:@"2"].tag, (long)2);
	OAK_ASSERT_EQ((long)[menu itemWithTitle:@"3"].tag, (long)3);
	OAK_ASSERT_EQ((long)[menu itemWithTitle:@"4"].tag, (long)4);
	OAK_ASSERT_EQ((long)[menu itemWithTitle:@"8"].tag, (long)8);

	// The two headers are inert -nop: rows, and everything under them is indented
	// one level.
	OAK_ASSERT_EQ((bool)([menu itemWithTitle:@"Indent Size"].action == @selector(nop:)), true);
	OAK_ASSERT_EQ((bool)([menu itemWithTitle:@"Indent Using"].action == @selector(nop:)), true);
	OAK_ASSERT_EQ((long)[menu itemWithTitle:@"4"].indentationLevel,      (long)1);
	OAK_ASSERT_EQ((long)[menu itemWithTitle:@"Spaces"].indentationLevel, (long)1);
	OAK_ASSERT_EQ((long)[menu itemWithTitle:@"Current Indent"].indentationLevel, (long)0);

	// The first row is the pull-down's *title* row, and it is built with no action
	// at all — not even -nop:. What it ends up carrying is AppKit's own
	// `_popUpItemAction:`, installed by NSPopUpButtonCell when the menu is
	// assigned, which is why this asserts "none of ours" rather than a specific
	// selector: the private name is Apple's to change.
	//
	// It matters for the port because MenuBuilder's API is a C++ DSL that Swift
	// cannot call, so this menu has to be rebuilt by hand — and giving the caption
	// a -nop: for symmetry with the other two would take it away from AppKit.
	SEL currentIndentAction = [menu itemWithTitle:@"Current Indent"].action;
	OAK_ASSERT_EQ((bool)(currentIndentAction == @selector(nop:)), false);
	OAK_ASSERT_EQ((bool)(currentIndentAction == @selector(takeTabSizeFrom:)), false);
	OAK_ASSERT_EQ((bool)menu.autoenablesItems, true);
}

void test_status_bar_menu_items_follow_the_target ()
{
	OTVStatusBar* bar = make_bar();
	NSObject* target = [NSObject new];

	// -setTarget: rebuilds the whole menu, because MenuBuilder bakes the target
	// into each item at construction rather than leaving it nil for the responder
	// chain.
	bar.target = target;
	OAK_ASSERT_EQ((bool)([bar.tabSizePopUp.menu itemWithTitle:@"4"].target == target), true);
	OAK_ASSERT_EQ((bool)([bar.tabSizePopUp.menu itemWithTitle:@"Tabs"].target == target), true);
}

// ==================================================================
// = The grammar menu, which is one of the two bundles::query calls =
// ==================================================================

void test_status_bar_grammar_menu_lists_scoped_grammars_sorted ()
{
	OTVStatusBar* bar = make_bar();
	[bar grammarPopUpButtonWillPopUp:nil];

	// Sorted by name with text::less_t, and "Scopeless" is absent because it has
	// no scopeName — the filter is `value_for_field(kFieldGrammarScope) != NULL_STR`.
	OAK_ASSERT_EQ(menu_titles(bar.grammarPopUp.menu), std::string("C | Plain Text"));

	// Each item carries the grammar's UUID as its represented object, which is
	// what -takeGrammarUUIDFrom: reads.
	OAK_ASSERT_EQ(describe((NSString*)[bar.grammarPopUp.menu itemWithTitle:@"C"].representedObject), std::string("25066DC2-6B1D-11D9-9D5B-000D93589AF6"));
}

void test_status_bar_grammar_menu_targets_the_bar_target ()
{
	OTVStatusBar* bar = make_bar();
	NSObject* target = [NSObject new];
	bar.target = target;

	[bar grammarPopUpButtonWillPopUp:nil];
	OAK_ASSERT_EQ((bool)([bar.grammarPopUp.menu itemWithTitle:@"C"].target == target), true);
	OAK_ASSERT_EQ((bool)([bar.grammarPopUp.menu itemWithTitle:@"C"].action == @selector(takeGrammarUUIDFrom:)), true);
}

void test_status_bar_file_type_looks_up_the_grammar_name ()
{
	OTVStatusBar* bar = make_bar();

	// The second bundles::query: a scope name in, the grammar's display name out.
	bar.fileType = @"source.c";
	OAK_ASSERT_EQ(describe(bar.grammarName), std::string("C"));

	bar.fileType = @"text.plain";
	OAK_ASSERT_EQ(describe(bar.grammarName), std::string("Plain Text"));

	// A scope no grammar claims leaves the previous name in place rather than
	// clearing it — the loop simply never runs.
	bar.fileType = @"source.nothing-claims-this";
	OAK_ASSERT_EQ(describe(bar.grammarName), std::string("Plain Text"));
}
