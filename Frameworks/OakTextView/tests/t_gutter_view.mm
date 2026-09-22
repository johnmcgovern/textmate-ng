#import "OakTextViewTesting.h"
#import <Cocoa/Cocoa.h>

// Coverage for GutterView, written **before** the port and against the
// Objective-C++ (the two-commit method). A pin written after the flip tests the
// port against itself and proves nothing.
//
// The gutter is worth pinning more than its 562 lines suggest. Two of the worst
// bugs this project has shipped were here — a gutter that drew no line numbers,
// which survived to alpha.10, and it was invisible to the suite both times
// because nothing had ever constructed the view. These tests construct it.
//
// What they deliberately do **not** pin: drawing. `-drawRect:` is checked by
// looking at a screenshot, which is what the smoke pass is for. Pinning pixels
// here would be a test of AppKit's text metrics on one machine.

static GutterView* TestGutter (GutterTestDelegate** outDelegate = nullptr)
{
	GutterView* gutter = [[GutterView alloc] initWithFrame:NSMakeRect(0, 0, 60, 300)];
	GutterTestDelegate* delegate = [GutterTestDelegate new];
	delegate.lastLineNumber = 41;               // a 42-line document
	gutter.delegate = delegate;
	if(outDelegate)
		*outDelegate = delegate;
	return gutter;
}

// The two answers every other thing here depends on. `isFlipped` is why line 0
// is at the top; getting it wrong draws the gutter upside down relative to the
// text, which is the shape of the bug that shipped.
void test_gutter_is_flipped_and_opaque ()
{
	GutterView* gutter = TestGutter();
	OAK_ASSERT_EQ((bool)gutter.isFlipped, true);
	OAK_ASSERT_EQ((bool)gutter.isOpaque, true);
}

// A fresh gutter already has the line-number column, inserted by -initWithFrame:.
// This is the one that would have caught "the gutter has no line numbers".
//
// **Asserted through width, not visibility.** The first version of this asked
// `visibilityForColumnWithIdentifier:`, and a mutation removing the column from
// -initWithFrame: survived it: visibility is stored as a set of *hidden*
// identifiers, so a column that was never inserted also reads as visible — which
// the test two functions below pins deliberately. The assertion was true whether
// or not the column existed, which is no assertion at all.
//
// Width does depend on it. With no columns there is nothing to be wide for.
void test_a_fresh_gutter_has_the_line_numbers_column ()
{
	GutterView* gutter = TestGutter();
	[gutter reloadData:nil];
	OAK_ASSERT_LT(0.0, (double)gutter.intrinsicContentSize.width);
}

// Visibility is stored as a set of *hidden* identifiers, so an identifier nobody
// has ever mentioned reads as visible. That is deliberate and worth pinning: it
// means inserting a column does not also have to register its visibility.
void test_an_unknown_column_reads_as_visible ()
{
	GutterView* gutter = TestGutter();
	OAK_ASSERT_EQ((bool)[gutter visibilityForColumnWithIdentifier:@"nobody-inserted-this"], true);
}

void test_column_visibility_round_trips ()
{
	GutterView* gutter = TestGutter();
	GutterTestColumn* column = [GutterTestColumn new];
	column.reportedWidth = 11;
	[gutter insertColumnWithIdentifier:@"bookmarks" atPosition:1 dataSource:column delegate:nil];

	OAK_ASSERT_EQ((bool)[gutter visibilityForColumnWithIdentifier:@"bookmarks"], true);
	[gutter setVisibility:NO forColumnWithIdentifier:@"bookmarks"];
	OAK_ASSERT_EQ((bool)[gutter visibilityForColumnWithIdentifier:@"bookmarks"], false);
	[gutter setVisibility:YES forColumnWithIdentifier:@"bookmarks"];
	OAK_ASSERT_EQ((bool)[gutter visibilityForColumnWithIdentifier:@"bookmarks"], true);

	// The line-number column is untouched by any of that.
	OAK_ASSERT_EQ((bool)[gutter visibilityForColumnWithIdentifier:GVLineNumbersColumnIdentifier], true);
}

// Width is the gutter's whole job besides drawing: it has to be wide enough for
// the widest line number plus every visible column. Pinned as a relation rather
// than a number, because the number is a font metric and would differ per
// machine — but hiding a column must narrow it, and showing it must widen it
// back, on any machine.
void test_hiding_a_column_narrows_the_gutter ()
{
	GutterView* gutter = TestGutter();
	GutterTestColumn* column = [GutterTestColumn new];
	column.reportedWidth = 20;
	[gutter insertColumnWithIdentifier:@"bookmarks" atPosition:1 dataSource:column delegate:nil];
	[gutter reloadData:nil];

	CGFloat const withColumn = gutter.intrinsicContentSize.width;

	[gutter setVisibility:NO forColumnWithIdentifier:@"bookmarks"];
	CGFloat const withoutColumn = gutter.intrinsicContentSize.width;
	OAK_ASSERT_LT(withoutColumn, withColumn);

	[gutter setVisibility:YES forColumnWithIdentifier:@"bookmarks"];
	OAK_ASSERT_EQ((double)gutter.intrinsicContentSize.width, (double)withColumn);
}

// The highlighted range is the current selection, drawn as a band beside the
// text. Set through the NSString entry point, which is the only one anything
// outside this class uses — the `std::string const&` overload beside it has no
// callers at all, measured, which is what makes this file portable to Swift.
//
// The pin is that a range is accepted and changes what needs redrawing. The
// rects themselves are private; `-needsDisplay` is the observable consequence.
void test_setting_a_highlighted_range_marks_the_gutter_dirty ()
{
	GutterView* gutter = TestGutter();
	[gutter insertColumnWithIdentifier:@"bookmarks" atPosition:1 dataSource:[GutterTestColumn new] delegate:nil];

	// In a window, because `-setNeedsDisplayInRect:` on a view with no window is
	// not required to record anything — which is what the first version of this
	// test got wrong, and the failure said so.
	NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 300) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
	[window.contentView addSubview:gutter];

	gutter.needsDisplay = NO;
	[gutter setHighlightedRangeString:@"3:1-5:1"];
	OAK_ASSERT_EQ((bool)gutter.needsDisplay, true);
}

// An empty range is how the gutter is told "nothing is selected". It must be
// accepted rather than treated as malformed, or the band never clears.
void test_an_empty_highlighted_range_is_accepted ()
{
	GutterView* gutter = TestGutter();
	[gutter setHighlightedRangeString:@"3:1-5:1"];
	[gutter setHighlightedRangeString:@""];
	OAK_ASSERT_EQ((bool)[gutter isKindOfClass:[GutterView class]], true);   // did not throw
}

// The public surface, pinned by name. This is what a Swift GutterView has to
// keep answering, and the selectors are `@objc` names rather than Swift ones —
// rule 18, and the reason a rename is caught here rather than at runtime.
void test_gutter_answers_its_public_selectors ()
{
	NSArray<NSString*>* const required = @[
		@"setHighlightedRangeString:",
		@"reloadData:",
		@"insertColumnWithIdentifier:atPosition:dataSource:delegate:",
		@"setVisibility:forColumnWithIdentifier:",
		@"visibilityForColumnWithIdentifier:",
		@"setPartnerView:",
		@"setLineNumberFont:",
		@"setDelegate:",
	];

	NSMutableArray* missing = [NSMutableArray array];
	for(NSString* name in required)
	{
		if(![GutterView instancesRespondToSelector:NSSelectorFromString(name)])
			[missing addObject:name];
	}
	OAK_ASSERT_EQ(std::string([missing componentsJoinedByString:@", "].UTF8String), std::string(""));
}
