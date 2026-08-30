#import "HTMLOutputTesting.h"
#import <ns/ns.h>
#import <Cocoa/Cocoa.h>

// Coverage for HOLocalURLRewriter, written before the port.
//
// This is the rewriter that turns `file://` into a same-origin URL in a bundle
// command's streaming HTML output. It is the one piece of HTMLOutput whose bug
// only appears under load: the stream arrives in 8KB reads, and a `file://` that
// straddles a read boundary is invisible to any test that feeds the whole thing
// at once. So most of what is below feeds it deliberately awkward splits.
//
// It works on bytes, not text. A chunk boundary can also fall inside a UTF-8
// sequence, and going through NSString would corrupt exactly the case the carry
// exists to handle — hence NSData throughout.

void setup ()
{
	NSApplicationLoad();
}

static NSData* data_of (char const* str)
{
	return [NSData dataWithBytes:str length:strlen(str)];
}

static std::string str_of (NSData* data)
{
	return std::string((char const*)data.bytes, data.length);
}

static std::string feed (HOLocalURLRewriter* rewriter, char const* chunk)
{
	return str_of([rewriter rewriteChunk:data_of(chunk)]);
}

static char const* const kLocal = "x-txmt-filehandle://job/__tm_local__";

// ==================================================================
// = Whole matches inside one chunk                                 =
// ==================================================================

void test_rewriter_replaces_a_complete_file_url ()
{
	HOLocalURLRewriter* rewriter = [HOLocalURLRewriter new];
	OAK_ASSERT_EQ(feed(rewriter, "<img src='file:///tmp/a.png'>"), std::string("<img src='") + kLocal + "/tmp/a.png'>");
	OAK_ASSERT_EQ((size_t)rewriter.carry.length, (size_t)0);
}

void test_rewriter_replaces_every_occurrence ()
{
	HOLocalURLRewriter* rewriter = [HOLocalURLRewriter new];
	std::string const expect = std::string("a") + kLocal + "1b" + kLocal + "2c";
	OAK_ASSERT_EQ(feed(rewriter, "afile://1bfile://2c"), expect);
}

void test_rewriter_passes_text_with_no_match_through ()
{
	HOLocalURLRewriter* rewriter = [HOLocalURLRewriter new];
	OAK_ASSERT_EQ(feed(rewriter, "<p>nothing here</p>"), std::string("<p>nothing here</p>"));
	OAK_ASSERT_EQ((size_t)rewriter.carry.length, (size_t)0);
}

// ==================================================================
// = The carry: matches split across a read boundary                =
// ==================================================================

void test_rewriter_holds_back_a_partial_match_and_completes_it ()
{
	HOLocalURLRewriter* rewriter = [HOLocalURLRewriter new];

	// "fil" could still become "file://", so **nothing after `<a href='` is
	// emitted** — the partial is held rather than guessed at.
	OAK_ASSERT_EQ(feed(rewriter, "<a href='fil"), std::string("<a href='"));
	OAK_ASSERT_EQ(str_of(rewriter.carry), std::string("fil"));

	// The next chunk completes it, and the replacement spans the boundary.
	OAK_ASSERT_EQ(feed(rewriter, "e:///tmp/x'>"), std::string(kLocal) + "/tmp/x'>");
	OAK_ASSERT_EQ((size_t)rewriter.carry.length, (size_t)0);
}

void test_rewriter_splits_at_every_offset_inside_the_prefix ()
{
	// One byte at a time is the worst case, and the one a 8KB reader hits only
	// when the stream happens to align that way.
	for(size_t split = 1; split < 7; ++split)
	{
		std::string const whole = "x file:///p y";
		HOLocalURLRewriter* rewriter = [HOLocalURLRewriter new];

		std::string got = feed(rewriter, whole.substr(0, 2 + split).c_str());
		got += feed(rewriter, whole.substr(2 + split).c_str());
		got += str_of(rewriter.carry);

		OAK_ASSERT_EQ(got, std::string("x ") + kLocal + "/p y");
	}
}

void test_rewriter_releases_a_partial_that_turns_out_not_to_match ()
{
	HOLocalURLRewriter* rewriter = [HOLocalURLRewriter new];

	OAK_ASSERT_EQ(feed(rewriter, "see fil"), std::string("see "));
	OAK_ASSERT_EQ(str_of(rewriter.carry), std::string("fil"));

	// "filter" is not "file://" — the held bytes come back out, in order.
	OAK_ASSERT_EQ(feed(rewriter, "ter"), std::string("filter"));
	OAK_ASSERT_EQ((size_t)rewriter.carry.length, (size_t)0);
}

void test_rewriter_keeps_only_the_longest_prefix_suffix ()
{
	HOLocalURLRewriter* rewriter = [HOLocalURLRewriter new];

	// Ends in "f", which is a one-character prefix of "file://", so exactly one
	// byte is held — not the whole trailing word.
	OAK_ASSERT_EQ(feed(rewriter, "half"), std::string("hal"));
	OAK_ASSERT_EQ(str_of(rewriter.carry), std::string("f"));

	// A trailing character that begins no prefix is emitted immediately.
	HOLocalURLRewriter* other = [HOLocalURLRewriter new];
	OAK_ASSERT_EQ(feed(other, "done."), std::string("done."));
	OAK_ASSERT_EQ((size_t)other.carry.length, (size_t)0);
}

void test_rewriter_holds_back_the_whole_chunk_when_it_is_all_prefix ()
{
	HOLocalURLRewriter* rewriter = [HOLocalURLRewriter new];

	// The read loop skips a chunk that comes back empty; this is the case that
	// makes that check necessary rather than defensive.
	OAK_ASSERT_EQ(feed(rewriter, "file:/"), std::string(""));
	OAK_ASSERT_EQ(str_of(rewriter.carry), std::string("file:/"));

	// The `/` completes the seventh character of "file://" rather than being path:
	// "file:/" + "/q" is the prefix plus a bare "q". Measured, after asserting
	// "/q" and being wrong about where the boundary falls.
	OAK_ASSERT_EQ(feed(rewriter, "/q"), std::string(kLocal) + "q");
}

// ==================================================================
// = Bytes, not text                                                =
// ==================================================================

void test_rewriter_survives_a_utf8_sequence_split_across_chunks ()
{
	HOLocalURLRewriter* rewriter = [HOLocalURLRewriter new];

	// U+00E9 is 0xC3 0xA9. Split between them: neither half is valid UTF-8 on its
	// own, and the rewriter must pass both through untouched. Going through
	// NSString here would substitute a replacement character and corrupt the page.
	OAK_ASSERT_EQ(feed(rewriter, "caf\xc3"), std::string("caf\xc3"));
	OAK_ASSERT_EQ(feed(rewriter, "\xa9 au lait"), std::string("\xa9 au lait"));
}

void test_rewriter_passes_an_empty_chunk_through ()
{
	HOLocalURLRewriter* rewriter = [HOLocalURLRewriter new];
	OAK_ASSERT_EQ(feed(rewriter, ""), std::string(""));

	// And an empty chunk does not discard a carry held from before.
	OAK_ASSERT_EQ(feed(rewriter, "fi"), std::string(""));
	OAK_ASSERT_EQ(feed(rewriter, ""), std::string(""));
	OAK_ASSERT_EQ(str_of(rewriter.carry), std::string("fi"));
	OAK_ASSERT_EQ(feed(rewriter, "le://z"), std::string(kLocal) + "z");
}
