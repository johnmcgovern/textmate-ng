#import <layout/layout.h>
#import <buffer/buffer.h>
#import <selection/selection.h>
#import <text/utf8.h>

// ng::layout_t maps a buffer onto screen geometry: it decides where every
// character is drawn, answers hit-testing and caret-movement questions in that
// geometry, and folds. None of that needs a window — a layout owns its own metrics
// and only wants a CGContext when actually asked to draw — so all of it is tested
// here headlessly.
//
// The predecessor of this file was an interactive harness: it opened a scrollable
// view, inserted this very source file at randomized offsets, and left a human to
// drive it. Its single real check was structural_integrity() inside a refresh
// cycle's destructor. That check is kept below (test_randomized_inserts) with a
// fixed seed so a failure is reproducible; everything else here is new.

typedef std::shared_ptr<ng::layout_t> layout_ptr;

static std::string const kSampleText =
	"#include <stdio.h>\n"
	"\n"
	"int main (int argc, char* argv[])\n"
	"{\n"
	"\tprintf(\"Hello, World!\\n\");\n"
	"\treturn 0;\n"
	"}\n";

// A layout needs a theme for its font metrics; parse_theme(nullptr) yields the
// built-in default, which keeps these tests independent of installed bundles.
//
// The viewport is deliberately shorter than any content used here: width()/height()
// return max(content, viewport), so a viewport taller than the text would pin the
// reported height to the viewport and hide every change to the content.
static CGSize const kViewportSize = { 600, 10 };

static layout_ptr make_layout (ng::buffer_t& buffer, std::string const& text = kSampleText, bool softWrap = false, size_t wrapColumn = 0)
{
	buffer.insert(0, text);
	layout_ptr res = std::make_shared<ng::layout_t>(buffer, parse_theme(bundles::item_ptr()), "Menlo", 12, softWrap, false, wrapColumn);
	res->set_viewport_size(kViewportSize);
	res->update_metrics(CGRectMake(0, 0, 600, 400));
	return res;
}

// Callers wrap every mutation in begin/end_refresh_cycle; the layout is only
// required to be self-consistent outside one, so integrity is checked there.
static void refresh (ng::layout_t& layout, ng::ranges_t const& selection, std::function<void()> body)
{
	layout.begin_refresh_cycle(selection);
	body();
	layout.end_refresh_cycle(selection, CGRectMake(0, 0, 600, 400));
	OAK_ASSERT(layout.structural_integrity());
}

void test_metrics_follow_content ()
{
	ng::buffer_t buffer;
	layout_ptr layout = make_layout(buffer);

	OAK_ASSERT(layout->structural_integrity());
	OAK_ASSERT_GT(layout->width(), 0);
	OAK_ASSERT_GT(layout->height(), 0);

	CGFloat const height = layout->height();
	CGFloat const width  = layout->width();

	// Adding lines makes it taller; a long line makes it wider.
	refresh(*layout, ng::ranges_t(0), [&]{ buffer.insert(buffer.size(), "\n\n\n"); });
	OAK_ASSERT_GT(layout->height(), height);

	refresh(*layout, ng::ranges_t(0), [&]{ buffer.insert(buffer.size(), std::string(400, 'x')); });
	OAK_ASSERT_GT(layout->width(), width);
}

// Every character index must map to a rect, and that rect's own origin must map
// back to the same index — the invariant every click and every caret move relies
// on. Off-by-one here is what puts the caret one character from the pointer.
void test_index_and_rect_round_trip ()
{
	ng::buffer_t buffer;
	layout_ptr layout = make_layout(buffer);

	size_t checked = 0;
	for(size_t i = 0; i < buffer.size(); i = buffer.begin(buffer.convert(i).line + 1) + 1)
	{
		CGRect rect = layout->rect_at_index(ng::index_t(i));
		OAK_MASSERT_GT("empty rect at " + std::to_string(i), CGRectGetHeight(rect), 0);

		// Aim just inside the glyph rather than exactly on its edge, where the
		// answer is legitimately either of two neighbours.
		CGPoint inside = CGPointMake(CGRectGetMinX(rect) + 1, CGRectGetMidY(rect));
		OAK_MASSERT_EQ("hit test at " + std::to_string(i), layout->index_at_point(inside).index, i);
		++checked;
	}
	OAK_ASSERT_GT(checked, 5);
}

// Clicking past the last line lands at the end of the document rather than
// nowhere, and clicking above the first lands at 0.
void test_hit_testing_outside_content ()
{
	ng::buffer_t buffer;
	layout_ptr layout = make_layout(buffer);

	OAK_ASSERT_EQ(layout->index_at_point(CGPointMake(0, -1000)).index, 0);
	OAK_ASSERT_EQ(layout->index_at_point(CGPointMake(0, layout->height() + 1000)).index, buffer.size());
	// Far to the right of a line is that line's end, not the next line's start.
	CGRect firstLine = layout->rect_at_index(ng::index_t(0));
	OAK_ASSERT_EQ(layout->index_at_point(CGPointMake(10000, CGRectGetMidY(firstLine))).index, buffer.begin(1) - 1);
}

// Soft wrap is layout-only: it must change the geometry without touching a byte
// of the buffer, and it must make the content narrower and taller.
void test_soft_wrap ()
{
	ng::buffer_t buffer;
	std::string const text = std::string(500, 'x') + "\n";
	layout_ptr layout = make_layout(buffer, text);

	size_t const size = buffer.size();
	CGFloat const unwrappedWidth  = layout->width();
	CGFloat const unwrappedHeight = layout->height();
	OAK_ASSERT_EQ((bool)layout->soft_wrap(), false);
	OAK_ASSERT_EQ(layout->softline_for_index(ng::index_t(size - 1)), 0);

	refresh(*layout, ng::ranges_t(0), [&]{ layout->set_wrapping(true, 0); });
	OAK_ASSERT_EQ((bool)layout->soft_wrap(), true);
	OAK_ASSERT_EQ(buffer.size(), size);                    // no text was changed
	OAK_ASSERT_LT(layout->width(), unwrappedWidth);
	OAK_ASSERT_GT(layout->height(), unwrappedHeight);
	// The one long line now occupies several soft lines.
	OAK_ASSERT_GT(layout->softline_for_index(ng::index_t(size - 1)), 0);

	refresh(*layout, ng::ranges_t(0), [&]{ layout->set_wrapping(false, 0); });
	OAK_ASSERT_EQ(layout->width(), unwrappedWidth);
	OAK_ASSERT_EQ(layout->height(), unwrappedHeight);
}

// A fixed wrap column has to be honoured exactly — bundle settings expose it as a
// column count, so "wrap at 40" must not depend on the viewport.
void test_explicit_wrap_column ()
{
	ng::buffer_t buffer;
	layout_ptr layout = make_layout(buffer, std::string(200, 'x') + "\n", true, 40);

	OAK_ASSERT_EQ(layout->wrap_column(), 40);
	OAK_ASSERT_EQ(layout->effective_wrap_column(), 40);

	CGFloat const narrowWidth = layout->width();
	refresh(*layout, ng::ranges_t(0), [&]{ layout->set_wrapping(true, 100); });
	OAK_ASSERT_EQ(layout->effective_wrap_column(), 100);
	OAK_ASSERT_GT(layout->width(), narrowWidth);
}

// Folding hides lines without editing them, and unfolding restores the exact
// original geometry.
void test_folding ()
{
	ng::buffer_t buffer;
	layout_ptr layout = make_layout(buffer);

	size_t const size   = buffer.size();
	CGFloat const height = layout->height();
	OAK_ASSERT_EQ((bool)layout->is_line_folded(3), false);

	// Fold the body of main(), lines 3..6 (0-based).
	refresh(*layout, ng::ranges_t(0), [&]{ layout->fold(buffer.begin(3), buffer.end(6)); });
	OAK_ASSERT_LT(layout->height(), height);
	OAK_ASSERT_EQ(buffer.size(), size);                    // folding is not editing
	OAK_ASSERT_EQ((bool)layout->is_line_folded(4), true);
	OAK_ASSERT_NE(layout->folded_as_string(), NULL_STR);
	// is_line_fold_start_marker is deliberately not asserted: it reports the
	// grammar's foldingStartMarker pattern, which needs installed bundles and says
	// nothing about a fold applied directly.

	refresh(*layout, ng::ranges_t(0), [&]{ layout->unfold(buffer.begin(3), buffer.end(6)); });
	OAK_ASSERT_EQ(layout->height(), height);
	OAK_ASSERT_EQ((bool)layout->is_line_folded(4), false);
	// "nothing folded" is NULL_STR rather than an empty string — that is what gets
	// stored as the document's folded-state attribute.
	OAK_ASSERT_EQ(layout->folded_as_string(), NULL_STR);
}

// A fold persists as a string so it can be restored when a document is reopened;
// that string has to survive the round trip.
void test_folded_state_round_trips ()
{
	ng::buffer_t buffer;
	layout_ptr layout = make_layout(buffer);

	refresh(*layout, ng::ranges_t(0), [&]{ layout->fold(buffer.begin(3), buffer.end(6)); });
	std::string const folded = layout->folded_as_string();
	CGFloat const foldedHeight = layout->height();

	ng::buffer_t other;
	other.insert(0, kSampleText);
	ng::layout_t restored(other, parse_theme(bundles::item_ptr()), "Menlo", 12, false, false, 0, folded);
	restored.set_viewport_size(kViewportSize);
	restored.update_metrics(CGRectMake(0, 0, 600, 400));

	OAK_ASSERT(restored.structural_integrity());
	OAK_ASSERT_EQ(restored.folded_as_string(), folded);
	OAK_ASSERT_EQ(restored.height(), foldedHeight);
}

// Up/down movement is the layout's job rather than the buffer's, because "the
// line above" means the visual line. These are the movements gui_layout.mm's
// keyDown table drove by hand.
void test_layout_aware_movement ()
{
	ng::buffer_t buffer;
	layout_ptr layout = make_layout(buffer);

	// Start of line 2 ("int main …"), then down a line and back up.
	ng::ranges_t sel(ng::index_t(buffer.begin(2)));
	ng::ranges_t down = ng::move(buffer, sel, kSelectionMoveDown, layout.get());
	OAK_ASSERT_EQ(buffer.convert(down.last().last.index).line, 3);

	ng::ranges_t back = ng::move(buffer, down, kSelectionMoveUp, layout.get());
	OAK_ASSERT_EQ(back.last().last.index, sel.last().last.index);

	// Up from the first line stays put rather than going negative.
	ng::ranges_t top = ng::move(buffer, ng::ranges_t(ng::index_t(0)), kSelectionMoveUp, layout.get());
	OAK_ASSERT_EQ(top.last().last.index, 0);

	// Document ends.
	ng::ranges_t end = ng::move(buffer, sel, kSelectionMoveToEndOfDocument, layout.get());
	OAK_ASSERT_EQ(end.last().last.index, buffer.size());
	ng::ranges_t begin = ng::move(buffer, end, kSelectionMoveToBeginOfDocument, layout.get());
	OAK_ASSERT_EQ(begin.last().last.index, 0);

	// Extending down selects rather than moves: the anchor stays behind.
	ng::ranges_t extended = ng::extend(buffer, sel, kSelectionExtendDown, layout.get());
	OAK_ASSERT_EQ(extended.last().first.index, sel.last().first.index);
	OAK_ASSERT_GT(extended.last().last.index, sel.last().last.index);
}

// With soft wrap on, "end of soft line" is a wrap point rather than the newline,
// which is the whole reason these movements take a layout.
void test_soft_line_movement ()
{
	ng::buffer_t buffer;
	layout_ptr layout = make_layout(buffer, std::string(500, 'x') + "\n", true, 40);

	ng::ranges_t sel(ng::index_t(0));
	ng::ranges_t eol = ng::move(buffer, sel, kSelectionMoveToEndOfSoftLine, layout.get());
	OAK_ASSERT_GT(eol.last().last.index, 0);
	OAK_ASSERT_LT(eol.last().last.index, 500);             // stopped at the wrap, not the newline

	// Hard end-of-line ignores wrapping and goes to the newline.
	ng::ranges_t hardEol = ng::move(buffer, sel, kSelectionMoveToEndOfLine, layout.get());
	OAK_ASSERT_EQ(hardEol.last().last.index, 500);
}

// The gutter asks which line is at a given y, and which y a given line is at.
// These have to agree, and the bands have to tile without gap or overlap, or line
// numbers drift from the text beside them.
void test_line_records ()
{
	ng::buffer_t buffer;
	layout_ptr layout = make_layout(buffer);

	CGFloat previousBottom = 0;
	for(size_t line = 0; line < 6; ++line)
	{
		ng::line_record_t byPos = layout->line_record_for(text::pos_t(line, 0));
		OAK_MASSERT_EQ("line " + std::to_string(line), byPos.line, line);
		OAK_MASSERT_LT("empty band " + std::to_string(line), byPos.top, byPos.bottom);
		// baseline is relative to the line's own top, not an absolute y.
		OAK_MASSERT_GT("baseline " + std::to_string(line), byPos.baseline, 0);
		OAK_MASSERT_LE("baseline " + std::to_string(line), byPos.baseline, byPos.bottom - byPos.top);

		if(line != 0)
			OAK_MASSERT_EQ("gap above line " + std::to_string(line), byPos.top, previousBottom);
		previousBottom = byPos.bottom;

		ng::line_record_t byY = layout->line_record_for(byPos.top + 1);
		OAK_MASSERT_EQ("y -> line " + std::to_string(line), byY.line, line);
	}
}

// Selections turn into rects for drawing; a caret is zero-width, a selection is
// not, and a multi-line selection needs a rect per line.
void test_rects_for_ranges ()
{
	ng::buffer_t buffer;
	layout_ptr layout = make_layout(buffer);

	std::vector<CGRect> caret = layout->rects_for_ranges(ng::ranges_t(ng::index_t(5)), kRectsIncludeCarets);
	OAK_ASSERT_EQ(caret.size(), 1);
	OAK_ASSERT_GT(CGRectGetHeight(caret[0]), 0);

	ng::ranges_t oneLine(ng::range_t(ng::index_t(0), ng::index_t(10)));
	std::vector<CGRect> rects = layout->rects_for_ranges(oneLine, kRectsIncludeSelections);
	OAK_ASSERT_EQ(rects.size(), 1);
	OAK_ASSERT_GT(CGRectGetWidth(rects[0]), 0);

	ng::ranges_t threeLines(ng::range_t(ng::index_t(0), ng::index_t(buffer.begin(3))));
	OAK_ASSERT_GT(layout->rects_for_ranges(threeLines, kRectsIncludeSelections).size(), 1);

	// A caret contributes no selection rect and vice versa.
	OAK_ASSERT_EQ(layout->rects_for_ranges(ng::ranges_t(ng::index_t(5)), kRectsIncludeSelections).size(), 0);
	OAK_ASSERT_EQ(layout->rects_for_ranges(oneLine, kRectsIncludeCarets).size(), 0);
}

// Drawing is the one thing that needs a graphics context, and a bitmap is enough.
// This is a crash/regression guard over the whole draw path — text, selection
// highlight, caret, indent guides — and it asserts pixels actually landed.
void test_draw_into_bitmap ()
{
	ng::buffer_t buffer;
	layout_ptr layout = make_layout(buffer);
	layout->set_draw_caret(true);
	layout->set_is_key(true);
	layout->set_draw_indent_guides(true);

	size_t const width = 600, height = 400, bytesPerRow = width * 4;
	std::vector<uint8_t> pixels(bytesPerRow * height, 0);
	CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGContextRef cgContext = CGBitmapContextCreate(pixels.data(), width, height, 8, bytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast);
	CGColorSpaceRelease(colorSpace);
	OAK_ASSERT(cgContext != nullptr);

	ng::context_t context(cgContext);
	ng::ranges_t selection(ng::range_t(ng::index_t(0), ng::index_t(20)));
	layout->draw(context, CGRectMake(0, 0, width, height), false, selection);

	CGContextRelease(cgContext);

	// Something was actually rendered rather than the call quietly no-op'ing.
	OAK_ASSERT(std::any_of(pixels.begin(), pixels.end(), [](uint8_t b){ return b != 0; }));
}

// The original harness' one real assertion, made reproducible: chop a text into
// fragments, insert them in a shuffled order so the layout is repeatedly patched
// rather than built once, and require it to stay structurally sound throughout.
// A fixed seed keeps a failure debuggable — the interactive version used
// arc4random and could not be replayed.
void test_randomized_inserts ()
{
	std::string source;
	for(size_t i = 0; i < 60; ++i)
		source += "line " + std::to_string(i) + ": the quick brown fox jumps over the lazy dog\n";

	std::vector<size_t> lengths;
	for(size_t i = 0; i < source.size(); i += lengths.back())
		lengths.push_back(std::min<size_t>(37, source.size() - i));

	std::vector<size_t> ordering(lengths.size());
	std::iota(ordering.begin(), ordering.end(), 0);
	std::shuffle(ordering.begin(), ordering.end(), std::mt19937(42));

	ng::buffer_t buffer;
	layout_ptr layout = std::make_shared<ng::layout_t>(buffer, parse_theme(bundles::item_ptr()), "Menlo", 12, true);
	layout->set_viewport_size(kViewportSize);

	std::vector<size_t> srcOffsets(lengths.size(), 0);
	for(size_t index : ordering)
	{
		size_t const offset = std::accumulate(lengths.begin(), lengths.begin() + index, (size_t)0);
		refresh(*layout, ng::ranges_t(0), [&]{
			buffer.replace(srcOffsets[index], srcOffsets[index], source.substr(offset, lengths[index]));
		});
		for(size_t i = index + 1; i < srcOffsets.size(); ++i)
			srcOffsets[i] += lengths[index];
	}

	OAK_ASSERT_EQ(buffer.size(), source.size());
	OAK_ASSERT_EQ(buffer.substr(0, buffer.size()), source);
	OAK_ASSERT(layout->structural_integrity());
	OAK_ASSERT_GT(layout->height(), 0);
}

// Deleting everything a fragment at a time is the other direction of the same
// incremental-patching path, and the one that historically underflowed.
void test_incremental_deletes ()
{
	ng::buffer_t buffer;
	layout_ptr layout = make_layout(buffer, kSampleText + kSampleText + kSampleText);

	while(buffer.size() != 0)
	{
		size_t const n = std::min<size_t>(7, buffer.size());
		refresh(*layout, ng::ranges_t(0), [&]{ buffer.replace(0, n, ""); });
	}

	OAK_ASSERT_EQ(buffer.size(), 0);
	OAK_ASSERT(layout->structural_integrity());
	OAK_ASSERT_EQ(layout->index_at_point(CGPointMake(0, 0)).index, 0);
}

// Multi-byte text must not be split mid-character by the layout: every rect
// boundary has to fall on a character boundary. The original harness carried
// these exact samples as a comment block for a human to eyeball.
void test_multibyte_text ()
{
	ng::buffer_t buffer;
	std::string const text =
		"surrogate: \xF0\xA0\xBB\xB5\n"                       // U+20EF5
		"thai: \xE0\xB9\x84\xE0\xB8\x9B\xE0\xB8\x81\xE0\xB8\xB4\xE0\xB8\x99\n"
		"rtl: \xD9\x88\xD9\x85\xD8\xB5\xD8\xA7\xD8\xAF\xD8\xB1\n"
		"wide: \xE5\x8D\x97\xE9\x87\x8E\n";
	layout_ptr layout = make_layout(buffer, text);

	OAK_ASSERT(layout->structural_integrity());

	// The offsets a character may legitimately start at, per the buffer itself.
	std::set<size_t> starts;
	for(size_t i = 0; i < buffer.size(); i += buffer[i].size())
		starts.insert(i);
	starts.insert(buffer.size());

	// Walking right one character at a time must only ever land on one of those,
	// and must reach the end rather than stalling.
	ng::ranges_t sel(ng::index_t(0));
	size_t steps = 0;
	while(sel.last().last.index < buffer.size() && steps++ < 1000)
	{
		sel = ng::move(buffer, sel, kSelectionMoveRight, layout.get());
		size_t const i = sel.last().last.index;
		OAK_MASSERT("split a character at " + std::to_string(i), starts.find(i) != starts.end());
	}
	OAK_ASSERT_EQ(sel.last().last.index, buffer.size());
	OAK_ASSERT_GT(steps, 20);                              // it really did walk
}
