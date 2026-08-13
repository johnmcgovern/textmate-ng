#import "OakAppKitTesting.h"

// Coverage for OakAppKit's small leaves, written against the ObjC++ *before*
// they were ported to Swift — the order every port in this project since Find
// has used, and the only thing that makes a green suite after the port mean
// anything.
//
// These classes are mostly configuration: a window that forces a style mask, a
// table mapping Finder labels to colours, a cache keyed by bundle identifier.
// None of it is algorithmic, which is exactly why it is worth pinning: a port
// that drops a flag or renumbers a table compiles, runs, and looks fine.

void setup ()
{
	// OakZoomingIcon orders a window front and drives Core Animation, both of
	// which need the main run loop to exist.
	NSApplicationLoad();
}

// ==================================================================
// = OakBorderlessPanel: the style mask it forces                   =
// ==================================================================
//
// The whole class is two overrides. It exists so a caller can ask for a titled
// panel and reliably get a borderless one, and so the panel draws as key even
// when it is not — used by the tooltip and pop-up chrome.

// The implementation reads as two operations:
//
//     styleMask |= NSWindowStyleMaskBorderless;
//     styleMask &= ~NSWindowStyleMaskTitled;
//
// but **NSWindowStyleMaskBorderless is 0**, so the first line does nothing at
// all and cannot be observed. "Borderless" is the *absence* of Titled, not a bit
// alongside it. The class's entire effect is the second line.
//
// This test asserted the intent when it was first written and failed against the
// unported ObjC++, which is the reason for writing it before porting: a Swift
// version that "helpfully" made the first line meaningful would be a change in
// behaviour dressed as a cleanup.
void test_borderless_panel_forces_style_mask ()
{
	OakBorderlessPanel* panel = [[OakBorderlessPanel alloc] initWithContentRect:NSMakeRect(0, 0, 100, 50) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];

	OAK_ASSERT_EQ((bool)(panel.styleMask & NSWindowStyleMaskTitled), false);

	// Resizable is *not* stripped — Titled is the only bit touched.
	OAK_ASSERT_EQ((bool)(panel.styleMask & NSWindowStyleMaskResizable), true);

	// And the no-op, stated so it stays stated: masking against Borderless is
	// masking against zero.
	OAK_ASSERT_EQ((NSUInteger)NSWindowStyleMaskBorderless, 0);
}

void test_borderless_panel_is_always_key ()
{
	OakBorderlessPanel* panel = [[OakBorderlessPanel alloc] initWithContentRect:NSMakeRect(0, 0, 100, 50) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
	OAK_ASSERT_EQ((bool)panel.isKeyWindow, true); // even though it was never ordered front
}

// ==================================================================
// = OakFinderTag: the label→colour table                           =
// ==================================================================

void test_finder_tag_label_zero_has_no_colour ()
{
	OakFinderTag* tag = [OakFinderTag tagWithDisplayName:@"Personal" label:0];
	OAK_ASSERT_EQ((bool)[tag hasLabelColor], false);
	OAK_ASSERT(tag.labelColor == nil);
}

void test_finder_tag_labels_one_through_seven_have_colours ()
{
	// Finder's seven, in Finder's order. Pinned by value because the switch is a
	// table and a port that renumbers it silently recolours every tagged file.
	NSArray<NSColor*>* expected = @[
		NSColor.systemGrayColor, NSColor.systemGreenColor, NSColor.systemPurpleColor,
		NSColor.systemBlueColor, NSColor.systemYellowColor, NSColor.systemRedColor,
		NSColor.systemOrangeColor,
	];

	for(NSUInteger label = 1; label <= 7; ++label)
	{
		OakFinderTag* tag = [OakFinderTag tagWithDisplayName:@"x" label:label];
		OAK_ASSERT_EQ((bool)[tag hasLabelColor], true);
		OAK_ASSERT([tag.labelColor isEqual:expected[label-1]]);
	}
}

void test_finder_tag_label_out_of_range_has_no_colour ()
{
	OakFinderTag* tag = [OakFinderTag tagWithDisplayName:@"x" label:8];
	OAK_ASSERT(tag.labelColor == nil);

	// …but -hasLabelColor is `label != 0`, so it disagrees with -labelColor here.
	// Carried over as-is: it is what the ObjC++ does, and nothing depends on the
	// out-of-range case.
	OAK_ASSERT_EQ((bool)[tag hasLabelColor], true);
}

// Equality is by display name alone — the label is deliberately not part of it,
// so a tag renamed in Finder still matches one read from an older xattr.
void test_finder_tag_equality_ignores_label ()
{
	OakFinderTag* a = [OakFinderTag tagWithDisplayName:@"Work" label:4];
	OakFinderTag* b = [OakFinderTag tagWithDisplayName:@"Work" label:6];
	OakFinderTag* c = [OakFinderTag tagWithDisplayName:@"Home" label:4];

	OAK_ASSERT_EQ((bool)[a isEqual:b], true);
	OAK_ASSERT_EQ((bool)[a isEqual:c], false);
	OAK_ASSERT_EQ(a.hash, b.hash);

	OAK_ASSERT_EQ((bool)[a isEqual:@"Work"], false); // not just any object with that name
}

void test_finder_tag_copy_preserves_both_fields ()
{
	OakFinderTag* tag  = [OakFinderTag tagWithDisplayName:@"Work" label:4];
	OakFinderTag* copy = [tag copy];
	OAK_ASSERT_EQ((bool)[tag isEqual:copy], true);
	OAK_ASSERT_EQ(copy.label, 4);
}

// ==================================================================
// = OakFinderTag: parsing the xattr                                =
// ==================================================================
//
// Finder stores tags as a bplist array of strings, each either "Name" or
// "Name\n<label>". Both shapes appear in real files.

static NSData* tag_plist (NSArray<NSString*>* entries)
{
	return [NSPropertyListSerialization dataWithPropertyList:entries format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
}

void test_finder_tags_from_data_parses_both_shapes ()
{
	NSArray<OakFinderTag*>* tags = [OakFinderTagManager finderTagsFromData:tag_plist(@[ @"Red\n6", @"Personal" ])];
	OAK_ASSERT_EQ(tags.count, 2);

	OAK_ASSERT([tags[0].displayName isEqualToString:@"Red"]);
	OAK_ASSERT_EQ(tags[0].label, 6);

	OAK_ASSERT([tags[1].displayName isEqualToString:@"Personal"]);
	OAK_ASSERT_EQ(tags[1].label, 0); // no newline means no colour
}

void test_finder_tags_from_empty_data_is_empty ()
{
	OAK_ASSERT_EQ([OakFinderTagManager finderTagsFromData:tag_plist(@[ ])].count, 0);
}

void test_finder_tags_for_url_without_tags_is_empty ()
{
	NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_appkit_leaves_untagged.txt"];
	[@"x" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];

	OAK_ASSERT_EQ([OakFinderTagManager finderTagsForURL:[NSURL fileURLWithPath:path]].count, 0);

	[NSFileManager.defaultManager removeItemAtPath:path error:nil];
}

// A non-file URL has no filePathURL, which is the guard the method opens with.
void test_finder_tags_for_non_file_url_is_empty ()
{
	OAK_ASSERT_EQ([OakFinderTagManager finderTagsForURL:[NSURL URLWithString:@"https://example.com/"]].count, 0);
}

// The fallback list matters: with no Finder preference, TextMate still offers
// the seven standard tags rather than none.
void test_favorite_finder_tags_are_named_and_nonempty ()
{
	NSArray<OakFinderTag*>* tags = [OakFinderTagManager favoriteFinderTags];
	OAK_ASSERT_GT(tags.count, 0);
	for(OakFinderTag* tag in tags)
		OAK_ASSERT_GT(tag.displayName.length, 0); // empty names are filtered out
}

// ==================================================================
// = OakZoomingIcon: the window it puts on screen                   =
// ==================================================================
//
// The animation closes the window ~0.25s later, so the assertions are about the
// window as constructed, not about what it looks like mid-flight.

void test_zooming_icon_window_configuration ()
{
	NSImage* icon = [[NSImage alloc] initWithSize:NSMakeSize(32, 32)];
	NSRect const iconRect = NSMakeRect(-10000, -10000, 32, 32); // off-screen

	OakZoomingIcon* window = [OakZoomingIcon zoomIcon:icon fromRect:iconRect];
	OAK_ASSERT(window != nil);

	OAK_ASSERT_EQ((bool)window.ignoresMouseEvents, true);
	OAK_ASSERT_EQ((bool)window.isOpaque, false);
	OAK_ASSERT_EQ((bool)window.releasedWhenClosed, false);
	OAK_ASSERT_EQ(window.level, NSPopUpMenuWindowLevel);

	// The frame is the icon's rect grown by 56 points on every side, which is the
	// room the zoom needs.
	OAK_ASSERT_EQ(NSWidth(window.frame),  NSWidth(iconRect)  + 112);
	OAK_ASSERT_EQ(NSHeight(window.frame), NSHeight(iconRect) + 112);

	[window close];
}

// ==================================================================
// = NSImage (ImageFromBundle)                                      =
// ==================================================================

void test_image_named_nil_is_nil ()
{
	OAK_ASSERT([NSImage imageNamed:nil inSameBundleAsClass:[OakFinderTag class]] == nil);
}

void test_image_named_missing_is_nil ()
{
	OAK_ASSERT([NSImage imageNamed:@"NoSuchImageInThisBundle" inSameBundleAsClass:[OakFinderTag class]] == nil);
}
