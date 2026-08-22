#import "OakAppKitTesting.h"
#import <ns/ns.h> // to_s(NSString*)
#import <Cocoa/Cocoa.h>

// Coverage for OakEncodingPopUpButton, written against the ObjC++ *before* the
// port. 345 lines, two classes and a nib, and the parts that will be hard to
// port are not the parts that look hard:
//
//   * +initialize both registers the defaults *and* migrates a pre-2.0-beta.10
//     format, and Swift cannot define +initialize at all;
//   * the menu is built two completely different ways depending on how many
//     encodings are enabled, with the threshold buried mid-method;
//   * -setEncoding: hand-rolls the push half of an NSBinding.
//
// The user-defaults key is spelled out here rather than imported because it is
// private to the implementation, and pinning it is the point: it is what the
// preference survives under.
static NSString* const kAvailableEncodingsKey = @"availableEncodings";

// +initialize runs once per process and only on the first message to the class,
// so the legacy migration cannot be re-run from a test. It is driven here, once,
// and its result is stashed for the test that asserts it.
static NSArray* g_migratedFromLegacy;
static NSArray* g_registeredDefaults;

static OakEncodingPopUpButton* make_button ()
{
	return [[OakEncodingPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
}

void setup ()
{
	NSApplicationLoad();

	NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
	NSArray* original = [defaults stringArrayForKey:kAvailableEncodingsKey];

	// A list in the pre-2.0-beta.10 spelling: UTF-16BE present, UTF-16BE//BOM
	// absent, which is exactly the condition +initialize tests for.
	[defaults setObject:@[ @"UTF-8", @"UTF-16BE", @"UTF-32LE", @"MACROMAN", @"UTF-16LE//BOM" ] forKey:kAvailableEncodingsKey];

	// Creating a button is the trigger, not messaging the class. +initialize
	// fired on the first message and Swift cannot define it, so the registration
	// moved into the initialisers — and this line has to work against both the
	// ObjC++ and the port, or the pin stops meaning anything across the change.
	(void)make_button();

	g_migratedFromLegacy = [defaults stringArrayForKey:kAvailableEncodingsKey];
	g_registeredDefaults = [[defaults volatileDomainForName:NSRegistrationDomain] objectForKey:kAvailableEncodingsKey];

	// Clear the key outright rather than putting `original` back. An earlier
	// version of this file restored it, and an assertion that threw before its
	// restore line left a ten-encoding list persisted in the test host's domain —
	// which then made the *next* run build a hierarchical menu where a flat one
	// was expected, in a test that had nothing to do with it. Removing the key
	// leaves the registration domain showing through, which is what a machine
	// that has never opened the pop-up looks like.
	(void)original;
	[defaults removeObjectForKey:kAvailableEncodingsKey];
}

// Sets the enabled-encodings default for as long as it is in scope, and puts the
// previous value back on the way out — including when an assertion throws past
// the end of the test, which is how this file poisoned its own next run once.
struct available_encodings_t
{
	available_encodings_t (NSArray* encodings) : _original([NSUserDefaults.standardUserDefaults arrayForKey:kAvailableEncodingsKey])
	{
		set(encodings);
	}

	~available_encodings_t ()
	{
		set(_original);
	}

private:
	static void set (NSArray* encodings)
	{
		if(encodings)
			[NSUserDefaults.standardUserDefaults setObject:encodings forKey:kAvailableEncodingsKey];
		else
			[NSUserDefaults.standardUserDefaults removeObjectForKey:kAvailableEncodingsKey];
	}

	NSArray* _original;
};

// The eight codes +initialize registers. Spelled out at each use rather than
// leaned on ambiently, so a test's menu shape does not depend on what ran before
// it.
#define OAK_DEFAULT_ENCODINGS @[ @"WINDOWS-1252", @"MACROMAN", @"ISO-8859-1", @"UTF-8", @"UTF-16LE//BOM", @"UTF-16BE//BOM", @"SHIFT_JIS", @"GB18030" ]

static std::string describe (NSArray* array)
{
	return array ? to_s([array componentsJoinedByString:@", "]) : std::string("«nil»");
}

static std::string describe (NSString* str)
{
	return str ? to_s(str) : std::string("«nil»");
}

// Every top-level title in the button's menu, in order, so a failure names what
// the menu actually looked like.
static std::string menu_titles (NSMenu* menu)
{
	NSMutableArray* titles = [NSMutableArray array];
	for(NSMenuItem* item in menu.itemArray)
		[titles addObject:item.isSeparatorItem ? @"«separator»" : item.title];
	return describe(titles);
}

static NSUInteger count_of_items_with_submenus (NSMenu* menu)
{
	NSUInteger res = 0;
	for(NSMenuItem* item in menu.itemArray)
		res += item.hasSubmenu ? 1 : 0;
	return res;
}

// ==================================================================
// = The surface a Swift port has to keep reachable                 =
// ==================================================================

void test_encoding_pop_up_selector_surface ()
{
	Class cls = OakEncodingPopUpButton.class;

	OAK_ASSERT_EQ((bool)[cls isSubclassOfClass:NSPopUpButton.class], true);
	OAK_ASSERT_EQ((bool)[cls conformsToProtocol:@protocol(OakUserDefaultsObserver)], true);

	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(encoding)],    true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setEncoding:)],true);

	// All three initialisers are live: -init from FilesPreferences.swift,
	// -initWithFrame:pullsDown: from OakDocument/EncodingView/OakSavePanel, and
	// -initWithCoder: from the nibs.
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(init)],                  true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(initWithFrame:pullsDown:)], true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(initWithCoder:)],        true);

	// The two menu actions and the defaults callback. These are wired by
	// -setTarget:/@selector() rather than in a header, so nothing but a test
	// notices when one is renamed.
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(selectEncoding:)],             true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(customizeAvailableEncodings:)],true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(userDefaultsDidChange:)],      true);
}

// ==================================================================
// = +initialize: the defaults, and the migration                   =
// ==================================================================

void test_encoding_pop_up_registers_its_default_list ()
{
	// Read from the registration domain, which is what +registerDefaults: writes
	// and what the application domain falls through to.
	OAK_ASSERT_EQ(describe(g_registeredDefaults), std::string("WINDOWS-1252, MACROMAN, ISO-8859-1, UTF-8, UTF-16LE//BOM, UTF-16BE//BOM, SHIFT_JIS, GB18030"));
}

void test_encoding_pop_up_migrates_the_legacy_bom_suffix ()
{
	// UTF-16BE and UTF-32LE gain //BOM; a code that already has it, and a code
	// that is neither UTF-16 nor UTF-32, are left alone. Order is preserved.
	OAK_ASSERT_EQ(describe(g_migratedFromLegacy), std::string("UTF-8, UTF-16BE//BOM, UTF-32LE//BOM, MACROMAN, UTF-16LE//BOM"));
}

// ==================================================================
// = What a fresh button looks like                                 =
// ==================================================================

void test_encoding_pop_up_defaults_to_utf8 ()
{
	available_encodings_t enabled(OAK_DEFAULT_ENCODINGS);
	OakEncodingPopUpButton* button = make_button();

	OAK_ASSERT_EQ(describe(button.encoding), std::string("UTF-8"));

	// In the flat shape the selection follows the value: the menu is built with
	// the current encoding's own item selected, not left on item 0.
	OAK_ASSERT_EQ(describe((NSString*)button.selectedItem.representedObject), std::string("UTF-8"));
}

void test_encoding_pop_up_menu_is_flat_below_ten_items ()
{
	// Eight encodings, which is the shipped default: no submenus, and each title
	// carries its group inline. Note the order — it is Charsets.plist's, not the
	// preference array's, because -updateMenu walks the charset list and filters.
	available_encodings_t enabled(OAK_DEFAULT_ENCODINGS);
	OakEncodingPopUpButton* button = make_button();

	OAK_ASSERT_EQ((size_t)count_of_items_with_submenus(button.menu), (size_t)0);
	OAK_ASSERT_EQ(menu_titles(button.menu), std::string("Chinese – GB18030, Japanese – Shift JIS, Unicode – UTF-8, Unicode – UTF-16BE, Unicode – UTF-16LE, Western – ISO Latin 1, Western – Mac OS Roman, Western – Windows, «separator», Customize List…"));
}

void test_encoding_pop_up_menu_is_hierarchical_at_ten_or_more ()
{
	// Ten is the threshold itself, not one past it — the branch is
	// `items.size() < 10`, so ten items already take the hierarchical path.
	available_encodings_t enabled(@[ @"WINDOWS-1252", @"MACROMAN", @"ISO-8859-1", @"UTF-8", @"UTF-16LE//BOM", @"UTF-16BE//BOM", @"SHIFT_JIS", @"GB18030", @"GBK", @"CP1256" ]);
	OakEncodingPopUpButton* button = make_button();

	// A header item carrying the current encoding's full name, a separator, then
	// one submenu per *contiguous run* of a group. Arabic, Chinese, Japanese,
	// Unicode and Western — five, because the charset list is already grouped.
	OAK_ASSERT_EQ((size_t)count_of_items_with_submenus(button.menu), (size_t)5);
	OAK_ASSERT_EQ(menu_titles(button.menu), std::string("Unicode – UTF-8, «separator», Arabic, Chinese, Japanese, Unicode, Western, «separator», Customize List…"));
}

void test_encoding_pop_up_hierarchical_selection_has_no_represented_object ()
{
	// The asymmetry between the two menu shapes, and the reason -selectedItem is
	// not a reliable way to read the encoding back. In the flat shape the
	// selected item is a real encoding item; in the hierarchical shape it is the
	// header, which is built with a NULL action and no represented object — the
	// actual selection is marked with a check inside a submenu instead.
	available_encodings_t enabled(@[ @"WINDOWS-1252", @"MACROMAN", @"ISO-8859-1", @"UTF-8", @"UTF-16LE//BOM", @"UTF-16BE//BOM", @"SHIFT_JIS", @"GB18030", @"GBK", @"CP1256" ]);
	OakEncodingPopUpButton* button = make_button();

	OAK_ASSERT_EQ(describe(button.selectedItem.title), std::string("Unicode – UTF-8"));
	OAK_ASSERT_EQ(describe((NSString*)button.selectedItem.representedObject), std::string("«nil»"));

	// And the encoding itself is unaffected — it is the property, not the menu,
	// that holds the value.
	OAK_ASSERT_EQ(describe(button.encoding), std::string("UTF-8"));
}

void test_encoding_pop_up_always_ends_with_customize ()
{
	available_encodings_t enabled(OAK_DEFAULT_ENCODINGS);
	OakEncodingPopUpButton* button = make_button();

	NSArray<NSMenuItem*>* items = button.menu.itemArray;
	OAK_ASSERT_EQ(describe(items.lastObject.title), std::string("Customize List…"));
	OAK_ASSERT_EQ((bool)items[items.count - 2].isSeparatorItem, true);
	// Targeted at the button, not at first responder — the menu is built with an
	// explicit target throughout.
	OAK_ASSERT_EQ((bool)(items.lastObject.target == button), true);
}

void test_encoding_pop_up_caps_its_width_at_200 ()
{
	// -init is the one FilesPreferences.swift calls, and it is the only
	// initialiser that sizes itself.
	OakEncodingPopUpButton* button = [[OakEncodingPopUpButton alloc] init];
	OAK_ASSERT_LE((double)NSWidth(button.frame), (double)200);
	OAK_ASSERT_GT((double)NSWidth(button.frame), (double)0);
}

// ==================================================================
// = -setEncoding:                                                  =
// ==================================================================

void test_encoding_pop_up_setting_the_same_encoding_does_not_rebuild ()
{
	available_encodings_t enabled(OAK_DEFAULT_ENCODINGS);
	OakEncodingPopUpButton* button = make_button();

	// The menu is thrown away and rebuilt on every set, so item identity is the
	// cheapest way to see whether the early return fired.
	NSMenuItem* before = button.menu.itemArray.firstObject;

	button.encoding = @"UTF-8"; // the value it already has
	OAK_ASSERT_EQ((bool)(button.menu.itemArray.firstObject == before), true);

	button.encoding = @"MACROMAN";
	OAK_ASSERT_EQ((bool)(button.menu.itemArray.firstObject == before), false);
}

void test_encoding_pop_up_adopts_an_encoding_outside_the_available_list ()
{
	available_encodings_t enabled(@[ @"UTF-8", @"MACROMAN" ]);
	OakEncodingPopUpButton* button = make_button();
	OAK_ASSERT_EQ(menu_titles(button.menu), std::string("Unicode – UTF-8, Western – Mac OS Roman, «separator», Customize List…"));

	// KOI8-R is in Charsets.plist but not in the enabled list. Setting it has to
	// widen the menu, or the button would carry a value it cannot display.
	button.encoding = @"KOI8-R";

	OAK_ASSERT_EQ(describe(button.encoding), std::string("KOI8-R"));
	OAK_ASSERT_EQ(menu_titles(button.menu), std::string("Cyrillic – KOI8-R, Unicode – UTF-8, Western – Mac OS Roman, «separator», Customize List…"));
	OAK_ASSERT_EQ(describe((NSString*)button.selectedItem.representedObject), std::string("KOI8-R"));
}

void test_encoding_pop_up_select_encoding_takes_the_represented_object ()
{
	available_encodings_t enabled(OAK_DEFAULT_ENCODINGS);
	OakEncodingPopUpButton* button = make_button();

	NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"whatever" action:NULL keyEquivalent:@""];
	item.representedObject = @"SHIFT_JIS";
	[button selectEncoding:item];

	OAK_ASSERT_EQ(describe(button.encoding), std::string("SHIFT_JIS"));
}

void test_encoding_pop_up_pushes_through_its_binding ()
{
	// -setEncoding: hand-rolls the push half of an NSBinding: it looks the
	// binding up with -infoForBinding: and writes through the key path itself.
	// Another button is the most convenient KVO-compliant target, and it is the
	// class under test, so nothing else has to be declared to run this.
	available_encodings_t enabled(OAK_DEFAULT_ENCODINGS);
	OakEncodingPopUpButton* button = make_button();
	OakEncodingPopUpButton* model  = make_button();

	model.encoding = @"MACROMAN";
	[button bind:@"encoding" toObject:model withKeyPath:@"encoding" options:nil];

	button.encoding = @"SHIFT_JIS";
	OAK_ASSERT_EQ(describe(model.encoding), std::string("SHIFT_JIS"));

	[button unbind:@"encoding"];
}

// ==================================================================
// = Reacting to the defaults changing under it                     =
// ==================================================================

void test_encoding_pop_up_follows_the_defaults ()
{
	available_encodings_t enabled(OAK_DEFAULT_ENCODINGS);
	OakEncodingPopUpButton* button = make_button();
	OAK_ASSERT_EQ((size_t)count_of_items_with_submenus(button.menu), (size_t)0);

	// The button is an OakUserDefaultsObserver, so a change to the enabled list
	// rebuilds its menu in place rather than needing a new button.
	available_encodings_t narrowed(@[ @"UTF-8", @"MACROMAN" ]);
	[button userDefaultsDidChange:nil];

	OAK_ASSERT_EQ(menu_titles(button.menu), std::string("Unicode – UTF-8, Western – Mac OS Roman, «separator», Customize List…"));
}
