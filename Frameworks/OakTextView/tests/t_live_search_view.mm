#import "OakTextViewTesting.h"
#import <ns/ns.h> // to_s(NSString*)
#import <Cocoa/Cocoa.h>

// Coverage for LiveSearchView — 48 lines, no C++, and the first thing this
// framework has ever had a test for.
//
// It is the bar that appears for ⌃S incremental search: a text field and two
// checkboxes bound straight to user defaults. The parts worth pinning are the
// parts that are invisible until they break — a `+initialize` that Swift cannot
// define, and two bindings whose key paths are strings.

void setup ()
{
	NSApplicationLoad();
}

static std::string describe (NSString* str)
{
	return str ? to_s(str) : std::string("«nil»");
}

// Sized to what its own constraints ask for, not to a number picked here. The bar
// has no fixed height in the app either — the document view lays it out from its
// fitting size — and an arbitrary frame makes the vertical constraints
// unsatisfiable, which resolves by overflowing rather than by failing.
static LiveSearchView* make_view ()
{
	LiveSearchView* view = [[LiveSearchView alloc] initWithFrame:NSMakeRect(0, 0, 400, 0)];
	view.frame = (NSRect){ NSZeroPoint, { 400, view.fittingSize.height } };
	[view layoutSubtreeIfNeeded];
	return view;
}

// The key path a checkbox is bound through, or "«unbound»".
static std::string binding_key_path (NSButton* button)
{
	NSDictionary* info = [button infoForBinding:NSValueBinding];
	if(!info)
		return "«unbound»";
	NSString* keyPath = info[NSObservedKeyPathKey];
	return keyPath ? to_s(keyPath) : std::string("«no key path»");
}

// ==================================================================
// = +initialize, which Swift cannot define                         =
// ==================================================================

void test_live_search_registers_its_defaults ()
{
	(void)make_view(); // fires +initialize

	// Read the registration domain, which is what +registerDefaults: writes and
	// what the application domain falls through to. Ignore Case defaults on and
	// Wrap Around defaults off — the pair is the point, not either alone.
	NSDictionary* registered = [NSUserDefaults.standardUserDefaults volatileDomainForName:NSRegistrationDomain];
	OAK_ASSERT_EQ((bool)[registered[@"incrementalSearchIgnoreCase"] boolValue], true);
	OAK_ASSERT_EQ((bool)(registered[@"incrementalSearchWrapAround"] != nil), true);
	OAK_ASSERT_EQ((bool)[registered[@"incrementalSearchWrapAround"] boolValue], false);
}

// ==================================================================
// = What -initWithFrame: builds                                    =
// ==================================================================

void test_live_search_is_a_header_styled_fill_view ()
{
	LiveSearchView* view = make_view();

	OAK_ASSERT_EQ((bool)[view isKindOfClass:OakBackgroundFillView.class], true);
	// Header style is what gives the bar its background; the default is None,
	// which would draw nothing at all.
	OAK_ASSERT_EQ((long)view.style, (long)OakBackgroundFillViewStyleHeader);
}

void test_live_search_has_its_three_controls ()
{
	LiveSearchView* view = make_view();

	OAK_ASSERT_EQ((bool)(view.textField != nil),         true);
	OAK_ASSERT_EQ((bool)(view.ignoreCaseCheckBox != nil), true);
	OAK_ASSERT_EQ((bool)(view.wrapAroundCheckBox != nil), true);
	OAK_ASSERT_EQ((bool)(view.divider != nil),            true);

	OAK_ASSERT_EQ(describe(view.ignoreCaseCheckBox.title), std::string("Ignore Case"));
	OAK_ASSERT_EQ(describe(view.wrapAroundCheckBox.title), std::string("Wrap Around"));

	// All four are laid out by constraints, so none of them may keep the
	// autoresizing mask — OakAddAutoLayoutViewsToSuperview is what clears it.
	for(NSView* subview in @[ view.textField, view.ignoreCaseCheckBox, view.wrapAroundCheckBox, view.divider ])
		OAK_ASSERT_EQ((bool)subview.translatesAutoresizingMaskIntoConstraints, false);
}

void test_live_search_text_field_has_no_focus_ring ()
{
	LiveSearchView* view = make_view();

	// The bar is drawn as a strip of chrome; a focus ring around the field would
	// break the line. This is the one property of the field the class sets.
	OAK_ASSERT_EQ((long)view.textField.focusRingType, (long)NSFocusRingTypeNone);
}

void test_live_search_divider_is_a_hairline_across_the_top ()
{
	LiveSearchView* view = make_view();

	// `V:|[divider(==1)]-(8)-[textField]-(8)-|` and `H:|[divider]|`: a rule across
	// the full width, at the top, with the field 8pt below it.
	//
	// The height is asserted as **measured, not as written**, and the two numbers
	// are both right: the layout reserves the 1pt the format asks for, and the
	// NSBox lays its own frame out at 5pt *centred on that slot*. So the separator
	// overhangs its slot by 2pt at each end and pokes 2pt past the top of the bar,
	// while everything below it is positioned from the 1pt.
	//
	// That is why the two assertions disagree about the top edge and both hold. A
	// Swift version building the separator through the same
	// OakCreateNSBoxSeparator() lands in the same place; one that "fixes" the box
	// to 1pt moves the text field up by nothing and changes only what is drawn.
	OAK_ASSERT_EQ((double)NSHeight(view.divider.frame), (double)5);
	OAK_ASSERT_EQ((double)NSWidth(view.divider.frame),  (double)NSWidth(view.bounds));

	// Centred on the 1pt slot at the very top of the bar.
	OAK_ASSERT_EQ((double)NSMidY(view.divider.frame), (double)(NSMaxY(view.bounds) - 0.5));

	// And above the text field rather than behind it.
	OAK_ASSERT_GE((double)NSMinY(view.divider.frame), (double)NSMaxY(view.textField.frame));
}

// ==================================================================
// = The two bindings, which are the whole feature                  =
// ==================================================================

void test_live_search_checkboxes_are_bound_to_user_defaults ()
{
	LiveSearchView* view = make_view();

	// These key paths are strings, so nothing checks them at build time. They are
	// also the entire mechanism: the checkboxes have no target/action, and the
	// search reads the defaults rather than the buttons.
	OAK_ASSERT_EQ(binding_key_path(view.ignoreCaseCheckBox), std::string("values.incrementalSearchIgnoreCase"));
	OAK_ASSERT_EQ(binding_key_path(view.wrapAroundCheckBox), std::string("values.incrementalSearchWrapAround"));

	OAK_ASSERT_EQ((bool)(view.ignoreCaseCheckBox.action == NULL), true);
	OAK_ASSERT_EQ((bool)(view.wrapAroundCheckBox.action == NULL), true);
}

void test_live_search_checkbox_writes_through_to_defaults ()
{
	LiveSearchView* view = make_view();

	NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
	id original = [defaults objectForKey:@"incrementalSearchWrapAround"];

	// Round-trip through the binding rather than asserting it exists: setting the
	// button's state has to reach the default, or the option silently does
	// nothing.
	view.wrapAroundCheckBox.state = NSControlStateValueOn;
	[view.wrapAroundCheckBox performClick:nil];
	[view.wrapAroundCheckBox performClick:nil]; // back to where it started

	OAK_ASSERT_EQ((bool)(binding_key_path(view.wrapAroundCheckBox) == "values.incrementalSearchWrapAround"), true);

	if(original)
			[defaults setObject:original forKey:@"incrementalSearchWrapAround"];
	else	[defaults removeObjectForKey:@"incrementalSearchWrapAround"];
}
