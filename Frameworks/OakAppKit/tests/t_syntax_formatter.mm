#import "../src/OakSyntaxFormatter.h"
#import <test/bundle_index.h>
#import <bundles/bundles.h>
#import <theme/theme.h> // kSystemUIThemeUUID
#import <Cocoa/Cocoa.h>

// Coverage for OakSyntaxFormatter, written against the ObjC++ *before* the port.
//
// The class is an NSFormatter wrapped around three things Swift cannot reach: a
// `parse::grammar_ptr` ivar, `parse::parse` over a std::string, and OakTheme's
// -stylesForScope: which takes a `scope::scope_t const&`. So the port needs a C++
// boundary, and the boundary needs to know exactly what the current code produces.
//
// The assertion that matters most is the UTF-16 one. The parser works in UTF-8
// bytes and the attributed string works in UTF-16 units; the ObjC++ bridges them
// with utf16::distance, and a port that carries the byte offsets straight through
// is correct for ASCII and silently wrong for every other input.

static char const* kPinGrammar =
	"{	name       = 'Pin';\n"
	"	scopeName  = 'source.pin';\n"
	"	uuid       = '11111111-2222-3333-4444-555555555555';\n"
	"	patterns   = ( { name = 'keyword.pin'; match = 'KEY'; } );\n"
	"}\n";

// The UUID is not arbitrary: +[OakTheme theme] looks up kSystemUIThemeUUID and
// falls back to an empty property list, so this is the only way a test gets a
// theme with distinguishable styles in it.
static char const* kPinTheme =
	"{	name     = 'Pin Theme';\n"
	"	uuid     = '64A455D4-9CF4-47C7-B484-3181471D1FD2';\n"
	"	settings = (\n"
	"		{ settings = { background = '#FFFFFF'; foreground = '#000000'; }; },\n"
	"		{ scope = 'keyword.pin'; settings = { foreground = '#FF0000'; fontStyle = 'bold underline'; }; },\n"
	"	);\n"
	"}\n";

void setup ()
{
	NSApplicationLoad();

	test::bundle_index_t bundleIndex;
	bundleIndex.add(bundles::kItemTypeGrammar, std::string(kPinGrammar));
	bundleIndex.add(bundles::kItemTypeTheme,   std::string(kPinTheme));
	bundleIndex.commit();
}

static NSMutableAttributedString* plain_string (NSString* str)
{
	return [[NSMutableAttributedString alloc] initWithString:str attributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:12] }];
}

static OakSyntaxFormatter* enabled_formatter ()
{
	OakSyntaxFormatter* formatter = [[OakSyntaxFormatter alloc] initWithGrammarName:@"source.pin"];
	formatter.enabled = YES;
	return formatter;
}

// The range over which the underline attribute is set. Underline is the cleanest
// marker the theme can hand back: the reset pass strips it from the whole string
// before the styled pass puts it back only where the theme asks for it.
static NSRange underlined_range (NSAttributedString* styled)
{
	__block NSRange found = NSMakeRange(NSNotFound, 0);
	[styled enumerateAttribute:NSUnderlineStyleAttributeName inRange:NSMakeRange(0, styled.length) options:0 usingBlock:^(id value, NSRange range, BOOL* stop){
		if(value)
		{
			found = range;
			*stop = YES;
		}
	}];
	return found;
}

static std::string to_string (NSRange range)
{
	return range.location == NSNotFound ? std::string("«none»") : oak_format("{%lu, %lu}", (unsigned long)range.location, (unsigned long)range.length);
}

// ==================================================================
// = The surface a Swift port has to keep reachable                 =
// ==================================================================

void test_syntax_formatter_selector_surface ()
{
	Class cls = OakSyntaxFormatter.class;

	OAK_ASSERT_EQ((bool)[cls isSubclassOfClass:NSFormatter.class], true);

	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(initWithGrammarName:)], true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(addStylesToString:)],   true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(enabled)],              true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(setEnabled:)],          true);

	// The three NSFormatter methods it overrides. A text field with this formatter
	// attached calls all three, so losing an override in a port is a live-editing
	// bug, not a styling one.
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(stringForObjectValue:)],                       true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(getObjectValue:forString:errorDescription:)],  true);
	OAK_ASSERT_EQ((bool)[cls instancesRespondToSelector:@selector(attributedStringForObjectValue:withDefaultAttributes:)], true);
}

void test_syntax_formatter_is_disabled_until_asked ()
{
	OakSyntaxFormatter* formatter = [[OakSyntaxFormatter alloc] initWithGrammarName:@"source.pin"];
	OAK_ASSERT_EQ((bool)formatter.enabled, false);
}

// ==================================================================
// = The two NSFormatter halves                                     =
// ==================================================================

void test_syntax_formatter_string_for_object_value_is_the_value ()
{
	OakSyntaxFormatter* formatter = enabled_formatter();
	NSString* value = @"aKEYb";
	// Returned as-is, not copied and not styled: -stringForObjectValue: is the
	// plain-text half of the formatter.
	OAK_ASSERT_EQ((bool)([formatter stringForObjectValue:value] == value), true);
}

void test_syntax_formatter_get_object_value_returns_a_new_instance ()
{
	OakSyntaxFormatter* formatter = enabled_formatter();
	NSString* input = [NSMutableString stringWithString:@"aKEYb"];

	id value = nil;
	NSString* error = nil;
	OAK_ASSERT_EQ((bool)[formatter getObjectValue:&value forString:input errorDescription:&error], true);

	OAK_ASSERT_EQ((bool)[value isEqualToString:@"aKEYb"], true);
	// A *different* object, deliberately: returning the same one breaks
	// NSContinuouslyUpdatesValueBindingOption, per the comment this pins.
	OAK_ASSERT_EQ((bool)(value == input), false);
}

void test_syntax_formatter_attributed_string_keeps_the_default_attributes ()
{
	OakSyntaxFormatter* formatter = enabled_formatter();

	NSFont* font = [NSFont systemFontOfSize:17];
	NSMutableParagraphStyle* paragraph = [NSMutableParagraphStyle new];
	paragraph.lineBreakMode = NSLineBreakByTruncatingMiddle;

	NSAttributedString* styled = [formatter attributedStringForObjectValue:@"aKEYb" withDefaultAttributes:@{ NSFontAttributeName: font, NSParagraphStyleAttributeName: paragraph }];

	OAK_ASSERT_EQ((bool)[styled.string isEqualToString:@"aKEYb"], true);
	// Attributes the formatter has no opinion about survive untouched.
	OAK_ASSERT_EQ((bool)([styled attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:nullptr] == paragraph), true);
	// And the ones it does have an opinion about were applied.
	OAK_ASSERT_EQ(to_string(underlined_range(styled)), std::string("{1, 3}"));
}

// ==================================================================
// = The reset pass, which runs whether or not styling is on        =
// ==================================================================

void test_syntax_formatter_resets_attributes_when_disabled ()
{
	OakSyntaxFormatter* formatter = [[OakSyntaxFormatter alloc] initWithGrammarName:@"source.pin"];
	// enabled stays NO

	NSMutableAttributedString* styled = plain_string(@"aKEYb");
	NSRange all = NSMakeRange(0, styled.length);
	[styled addAttributes:@{
		NSForegroundColorAttributeName:   NSColor.systemPinkColor,
		NSBackgroundColorAttributeName:   NSColor.systemYellowColor,
		NSUnderlineStyleAttributeName:    @(NSUnderlineStyleSingle),
		NSStrikethroughStyleAttributeName:@(NSUnderlineStyleSingle),
	} range:all];
	[styled applyFontTraits:NSBoldFontMask|NSItalicFontMask range:all];

	[formatter addStylesToString:styled];

	// Three attributes removed outright...
	OAK_ASSERT_EQ((bool)([styled attribute:NSBackgroundColorAttributeName    atIndex:0 effectiveRange:nullptr] == nil), true);
	OAK_ASSERT_EQ((bool)([styled attribute:NSUnderlineStyleAttributeName     atIndex:0 effectiveRange:nullptr] == nil), true);
	OAK_ASSERT_EQ((bool)([styled attribute:NSStrikethroughStyleAttributeName atIndex:0 effectiveRange:nullptr] == nil), true);

	// ...the foreground forced back to the control colour...
	OAK_ASSERT_EQ((bool)([styled attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:nullptr] == NSColor.controlTextColor), true);

	// ...and bold/italic stripped. This is the pass that lets one formatter be
	// reused on a field whose contents were styled by a previous pass.
	NSFont* font = [styled attribute:NSFontAttributeName atIndex:0 effectiveRange:nullptr];
	NSFontTraitMask traits = [NSFontManager.sharedFontManager traitsOfFont:font];
	OAK_ASSERT_EQ((bool)(traits & NSBoldFontMask),   false);
	OAK_ASSERT_EQ((bool)(traits & NSItalicFontMask), false);
}

void test_syntax_formatter_leaves_an_empty_string_alone ()
{
	OakSyntaxFormatter* formatter = enabled_formatter();

	NSMutableAttributedString* styled = plain_string(@"");
	[formatter addStylesToString:styled];
	OAK_ASSERT_EQ((size_t)styled.length, (size_t)0);
}

void test_syntax_formatter_without_a_grammar_name_does_nothing ()
{
	// -init, not -initWithGrammarName:, so _grammarName is nil and the whole
	// method returns before the reset pass. The reset is *not* unconditional.
	OakSyntaxFormatter* formatter = [[OakSyntaxFormatter alloc] init];
	formatter.enabled = YES;

	NSMutableAttributedString* styled = plain_string(@"aKEYb");
	[styled addAttributes:@{ NSBackgroundColorAttributeName: NSColor.systemYellowColor } range:NSMakeRange(0, styled.length)];

	[formatter addStylesToString:styled];

	OAK_ASSERT_EQ((bool)([styled attribute:NSBackgroundColorAttributeName atIndex:0 effectiveRange:nullptr] != nil), true);
}

// ==================================================================
// = The styled pass                                                =
// ==================================================================

void test_syntax_formatter_styles_the_matched_scope ()
{
	OakSyntaxFormatter* formatter = enabled_formatter();

	NSMutableAttributedString* styled = plain_string(@"aKEYb");
	[formatter addStylesToString:styled];

	OAK_ASSERT_EQ(to_string(underlined_range(styled)), std::string("{1, 3}"));

	// The theme also asks for bold over that scope, and for a foreground that is
	// not the one the reset pass put down.
	NSFont* keywordFont = [styled attribute:NSFontAttributeName atIndex:1 effectiveRange:nullptr];
	OAK_ASSERT_EQ((bool)([NSFontManager.sharedFontManager traitsOfFont:keywordFont] & NSBoldFontMask), true);

	NSColor* inside  = [styled attribute:NSForegroundColorAttributeName atIndex:1 effectiveRange:nullptr];
	NSColor* outside = [styled attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:nullptr];
	OAK_ASSERT_EQ((bool)[inside isEqual:outside], false);
}

void test_syntax_formatter_ranges_are_utf16_not_bytes ()
{
	OakSyntaxFormatter* formatter = enabled_formatter();

	// "æ" is one UTF-16 unit and two UTF-8 bytes; the emoji is two UTF-16 units
	// and four UTF-8 bytes. So KEY begins at UTF-8 byte 6 and UTF-16 index 3, and
	// a port that hands the parser's byte offsets to NSMutableAttributedString
	// underlines the wrong three characters — or throws out of range.
	NSMutableAttributedString* styled = plain_string(@"æ😀KEYb");
	OAK_ASSERT_EQ((size_t)styled.length, (size_t)7); // 1 + 2 + 3 + 1 UTF-16 units

	[formatter addStylesToString:styled];

	OAK_ASSERT_EQ(to_string(underlined_range(styled)), std::string("{3, 3}"));
}

void test_syntax_formatter_stops_parsing_at_the_size_limit ()
{
	OakSyntaxFormatter* formatter = enabled_formatter();

	// kParseSizeLimit is 1024 bytes. The keyword sits past it, so no scope is
	// produced for it...
	NSString* padded = [[@"" stringByPaddingToLength:1100 withString:@"a" startingAtIndex:0] stringByAppendingString:@"KEY"];
	NSMutableAttributedString* styled = plain_string(padded);
	[formatter addStylesToString:styled];

	OAK_ASSERT_EQ(to_string(underlined_range(styled)), std::string("«none»"));

	// ...but the text past the limit is not left unstyled either: the loop gives
	// the final scope a range that runs to str.size(), so the base scope's
	// foreground covers the whole string.
	NSRange effective = NSMakeRange(0, 0);
	[styled attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:&effective];
	OAK_ASSERT_EQ(to_string(effective), to_string(NSMakeRange(0, styled.length)));
}

void test_syntax_formatter_unknown_grammar_falls_back_to_the_reset_pass ()
{
	OakSyntaxFormatter* formatter = [[OakSyntaxFormatter alloc] initWithGrammarName:@"source.nothing-claims-this"];
	formatter.enabled = YES;

	NSMutableAttributedString* styled = plain_string(@"aKEYb");
	[styled addAttributes:@{ NSBackgroundColorAttributeName: NSColor.systemYellowColor } range:NSMakeRange(0, styled.length)];

	[formatter addStylesToString:styled];

	// The reset still ran — a missing grammar degrades to plain text rather than
	// leaving whatever the field happened to be carrying.
	OAK_ASSERT_EQ((bool)([styled attribute:NSBackgroundColorAttributeName atIndex:0 effectiveRange:nullptr] == nil), true);
	OAK_ASSERT_EQ(to_string(underlined_range(styled)), std::string("«none»"));
}
