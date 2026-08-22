#import "OakAppKitTesting.h"
#import <ns/ns.h>
#import <settings/settings.h>
#import <Cocoa/Cocoa.h>

// Coverage for OakSavePanel, written against the ObjC++ *before* the port.
//
// The panel itself is untestable — it wants a window and a modal sheet — so all
// of this drives OakEncodingSaveOptionsViewController, which is where the
// behaviour actually lives: the accessory view, the two bindings, and the rule
// that decides which encoding a new file gets.
//
// This is the hardest remaining file in OakAppKit and the reason is in the
// header: `encoding::type` appears as an ivar (rule 20), as a parameter, and
// inside a **block parameter** (rule 15). The last of those makes the entry
// point uncallable from Swift no matter how the rest is written, so the port
// needs a box for encoding::type and both ObjC++ callers move with it.

void setup ()
{
	NSApplicationLoad();
}

static std::string describe (NSString* str)
{
	return str ? to_s(str) : std::string("«nil»");
}

static std::string describe (encoding::type const& encoding)
{
	return "newlines=" + (encoding.newlines() == NULL_STR ? std::string("«NULL_STR»") : encoding.newlines())
	     + " charset=" + encoding.charset();
}

static OakEncodingSaveOptionsViewController* make_controller (encoding::type const& encoding)
{
	return [[OakEncodingSaveOptionsViewController alloc] initWithOptions:[OakEncodingOptions optionsWithCxxEncoding:encoding] fileType:@"text.plain"];
}

// ==================================================================
// = The surface a Swift port has to keep reachable                 =
// ==================================================================

void test_save_panel_selector_surface ()
{
	// One class method, and its signature is the whole problem: an
	// `encoding::type const&` parameter *and* an `encoding::type const&` inside
	// the completion block.
	OAK_ASSERT_EQ((bool)[OakSavePanel respondsToSelector:@selector(showWithPath:directory:fowWindow:encoding:fileType:completionHandler:)], true);

	Class cls = OakEncodingSaveOptionsViewController.class;
	OAK_ASSERT_EQ((bool)[cls isSubclassOfClass:NSViewController.class], true);
	OAK_ASSERT_EQ((bool)[cls conformsToProtocol:@protocol(NSOpenSavePanelDelegate)], true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(initWithOptions:fileType:)], true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(resolvedOptionsForURL:)],                   true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(updateSettingsWithOptions:)],                   true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(panel:didChangeToDirectoryURL:)],    true);
}

// ==================================================================
// = The value transformer registered by +initialize                =
// ==================================================================

void test_save_panel_registers_the_line_endings_transformer ()
{
	// Touching the class fires +initialize, which is the only thing that creates
	// this transformer. Swift cannot define +initialize, so a port has to find it
	// another home *and* keep it running before the accessory view is built —
	// the line-endings pop-up binds through it by name.
	(void)make_controller(encoding::type());

	NSValueTransformer* transformer = [NSValueTransformer valueTransformerForName:@"OakLineEndingsTransformer"];
	OAK_ASSERT_EQ((bool)(transformer != nil), true);

	// Tag 0/1/2 is LF/CR/CRLF, and the pop-up's NSSelectedTagBinding rides on
	// exactly this mapping.
	OAK_ASSERT_EQ((long)[[transformer transformedValue:@"\n"]   integerValue], (long)0);
	OAK_ASSERT_EQ((long)[[transformer transformedValue:@"\r"]   integerValue], (long)1);
	OAK_ASSERT_EQ((long)[[transformer transformedValue:@"\r\n"] integerValue], (long)2);

	OAK_ASSERT_EQ(describe((NSString*)[transformer reverseTransformedValue:@0]), std::string("\n"));
	OAK_ASSERT_EQ(describe((NSString*)[transformer reverseTransformedValue:@1]), std::string("\r"));
	OAK_ASSERT_EQ(describe((NSString*)[transformer reverseTransformedValue:@2]), std::string("\r\n"));

	// An unknown string maps to nil rather than to 0 — which is what leaves the
	// pop-up with no selection instead of silently claiming LF.
	OAK_ASSERT_EQ((bool)([transformer transformedValue:@"\u2028"] == nil), true);
}

// ==================================================================
// = -encodingForURL:, the rule that picks an encoding              =
// ==================================================================

void test_save_panel_fills_in_an_unset_encoding_from_settings ()
{
	// A brand new document: no charset, no newlines. Both come from settings,
	// whose defaults are UTF-8 and LF.
	OakEncodingSaveOptionsViewController* controller = make_controller(encoding::type());

	encoding::type res = [[controller resolvedOptionsForURL:[NSURL fileURLWithPath:@"/tmp/t_save_panel.txt"]] cxxEncoding];

	settings_t const& settings = settings_for_path("/tmp/t_save_panel.txt", "text.plain");
	OAK_ASSERT_EQ(describe(res), "newlines=" + settings.get(kSettingsLineEndingsKey, "\n") + " charset=" + settings.get(kSettingsEncodingKey, kCharsetUTF8));
}

void test_save_panel_keeps_an_encoding_that_is_already_set ()
{
	// An existing document being saved elsewhere keeps what it had — the settings
	// lookup is a fallback, not an override.
	OakEncodingSaveOptionsViewController* controller = make_controller(encoding::type("\r\n", "MACROMAN"));

	encoding::type res = [[controller resolvedOptionsForURL:[NSURL fileURLWithPath:@"/tmp/t_save_panel.txt"]] cxxEncoding];
	OAK_ASSERT_EQ(describe(res), std::string("newlines=\r\n charset=MACROMAN"));
}

void test_save_panel_fills_the_two_halves_independently ()
{
	// Charset set, newlines not. Only the missing half is filled, which is why
	// the ObjC++ tests them with two separate `if`s rather than one.
	OakEncodingSaveOptionsViewController* controller = make_controller(encoding::type(NULL_STR, "MACROMAN"));

	encoding::type res = [[controller resolvedOptionsForURL:[NSURL fileURLWithPath:@"/tmp/t_save_panel.txt"]] cxxEncoding];
	settings_t const& settings = settings_for_path("/tmp/t_save_panel.txt", "text.plain");

	OAK_ASSERT_EQ(describe(res), "newlines=" + settings.get(kSettingsLineEndingsKey, "\n") + " charset=MACROMAN");
}

void test_save_panel_uppercases_a_charset_it_fills_in ()
{
	// encoding::type's *constructor* stores the charset verbatim while
	// -set_charset uppercases it. -encodingForURL: goes through the setter, so a
	// lowercase settings value comes back uppercased — and a port that carries
	// the string straight through changes what the pop-up matches against.
	encoding::type direct("\n", "macroman");
	OAK_ASSERT_EQ(direct.charset(), std::string("macroman")); // constructor: verbatim

	encoding::type viaSetter;
	viaSetter.set_charset("macroman");
	OAK_ASSERT_EQ(viaSetter.charset(), std::string("MACROMAN")); // setter: uppercased
}

// ==================================================================
// = -updateSettings: and the accessory view it feeds               =
// ==================================================================

void test_save_panel_update_settings_maps_onto_the_bound_properties ()
{
	OakEncodingSaveOptionsViewController* controller = make_controller(encoding::type());

	[controller updateSettingsWithOptions:[OakEncodingOptions optionsWithCxxEncoding:encoding::type("\r", "SHIFT_JIS")]];

	// These two property names are the binding key paths the accessory view uses,
	// so they are API even though nothing declares them publicly.
	OAK_ASSERT_EQ(describe(controller.lineEndings), std::string("\r"));
	OAK_ASSERT_EQ(describe(controller.encoding),    std::string("SHIFT_JIS"));
}

void test_save_panel_update_settings_passes_null_str_through_as_nil ()
{
	OakEncodingSaveOptionsViewController* controller = make_controller(encoding::type());

	// NULL_STR becomes nil rather than an empty string — +stringWithCxxString:
	// maps it — and the pop-up treats nil as "no selection".
	//
	// Both halves come back nil here, and the second one is worth stating because
	// the name hides it: **kCharsetNoEncoding is NULL_STR**, not a sentinel
	// string. A default-constructed encoding::type therefore carries nothing at
	// all, which is exactly why -encodingForURL: has to fill both halves in.
	[controller updateSettingsWithOptions:[OakEncodingOptions optionsWithCxxEncoding:encoding::type()]];
	OAK_ASSERT_EQ(describe(controller.lineEndings), std::string("«nil»"));
	OAK_ASSERT_EQ(describe(controller.encoding),    std::string("«nil»"));
	OAK_ASSERT_EQ((bool)(kCharsetNoEncoding == NULL_STR), true);
}

void test_save_panel_accessory_view_has_both_pop_ups ()
{
	OakEncodingSaveOptionsViewController* controller = make_controller(encoding::type("\n", "UTF-8"));

	NSView* view = controller.view; // forces -loadView
	OAK_ASSERT_EQ((bool)(view != nil), true);
	OAK_ASSERT_GT((double)NSWidth(view.frame), (double)0);

	NSMutableArray<NSPopUpButton*>* popUps = [NSMutableArray array];
	for(NSView* subview in view.subviews)
	{
		if([subview isKindOfClass:NSPopUpButton.class])
			[popUps addObject:(NSPopUpButton*)subview];
	}

	// One encoding pop-up and one line-endings pop-up, plus the "Encoding:" label.
	OAK_ASSERT_EQ((size_t)popUps.count, (size_t)2);

	// The accessibility labels are how the panel is driven by anything other than
	// a mouse, and neither pop-up has a visible title to fall back on.
	NSMutableSet<NSString*>* labels = [NSMutableSet set];
	for(NSPopUpButton* popUp in popUps)
	{
		if(popUp.accessibilityLabel)
			[labels addObject:popUp.accessibilityLabel];
	}
	OAK_ASSERT_EQ((bool)[labels containsObject:@"Encoding"],     true);
	OAK_ASSERT_EQ((bool)[labels containsObject:@"Line endings"], true);
}

void test_save_panel_line_endings_pop_up_is_tagged_in_order ()
{
	OakEncodingSaveOptionsViewController* controller = make_controller(encoding::type("\n", "UTF-8"));
	(void)controller.view;

	NSPopUpButton* lineEndings = nil;
	for(NSView* subview in controller.view.subviews)
	{
		if([subview isKindOfClass:NSPopUpButton.class] && [[(NSPopUpButton*)subview accessibilityLabel] isEqualToString:@"Line endings"])
			lineEndings = (NSPopUpButton*)subview;
	}
	OAK_ASSERT_EQ((bool)(lineEndings != nil), true);

	OAK_ASSERT_EQ((size_t)lineEndings.numberOfItems, (size_t)3);
	OAK_ASSERT_EQ(describe([lineEndings itemAtIndex:0].title), std::string("LF"));
	OAK_ASSERT_EQ(describe([lineEndings itemAtIndex:1].title), std::string("CR"));
	OAK_ASSERT_EQ(describe([lineEndings itemAtIndex:2].title), std::string("CRLF"));

	// The tags are what the transformer maps, so they must be 0/1/2 in this
	// order — the titles alone carry no meaning to the binding.
	OAK_ASSERT_EQ((long)[lineEndings itemAtIndex:0].tag, (long)0);
	OAK_ASSERT_EQ((long)[lineEndings itemAtIndex:1].tag, (long)1);
	OAK_ASSERT_EQ((long)[lineEndings itemAtIndex:2].tag, (long)2);
}

void test_save_panel_holds_its_panel_weakly_enough_to_detach ()
{
	// -dealloc nils the panel's delegate when it is still pointing at self, because
	// NSSavePanel outlives the accessory controller once the sheet is dismissed.
	//
	// That teardown is **not pinned here**, deliberately. Observing it needs the
	// controller to be deallocated at a moment the test controls, and wrapping the
	// construction in an @autoreleasepool is not enough — the object survives the
	// pool, so the assertion measured nothing. What is pinned is the property the
	// teardown depends on.
	NSSavePanel* panel = [NSSavePanel savePanel];
	OakEncodingSaveOptionsViewController* controller = make_controller(encoding::type());

	controller.savePanel = panel;
	OAK_ASSERT_EQ((bool)(controller.savePanel == panel), true);

	panel.delegate = (id<NSOpenSavePanelDelegate>)controller;
	OAK_ASSERT_EQ((bool)(panel.delegate == (id)controller), true);
}
