#import "FindTesting.h"

// The five status strings Find puts under its results list. All pure given a
// count, and every one of them picks a different sentence at N = 1 — which is
// the kind of thing a port quietly gets wrong, because N = 1 is the case nobody
// re-reads and every manual test happens to hit N > 1.
//
// These assert the *shape* — singular vs plural, which sentence, whether the
// count appears at all — rather than the exact wording, except where the wording
// is the thing under test. A reworded string should not fail a test; a string
// that says "1 results" should.

static NSString* LocalizedCount (NSUInteger n)
{
	return [NSNumberFormatter localizedStringFromNumber:@(n) numberStyle:NSNumberFormatterDecimalStyle];
}

// ==================================
// = What a finished search reports =
// ==================================

void test_result_count_string_pluralises ()
{
	OAK_ASSERT([[Find resultCountStringForCount:0 searchString:@"needle"] isEqualToString:@"No results found for “needle”."]);
	OAK_ASSERT([[Find resultCountStringForCount:1 searchString:@"needle"] isEqualToString:@"Found one result for “needle”."]);
	OAK_ASSERT([[Find resultCountStringForCount:2 searchString:@"needle"] isEqualToString:@"Found 2 results for “needle”."]);
}

// The count is spelled out as a word at one, and as a numeral otherwise — so
// "1" must never appear in the singular sentence.
void test_result_count_string_says_one_not_1 ()
{
	NSString* singular = [Find resultCountStringForCount:1 searchString:@"needle"];
	OAK_ASSERT([singular rangeOfString:@"one"].location != NSNotFound);
	OAK_ASSERT([singular rangeOfString:@"1"].location == NSNotFound);
}

// The plural sentence uses positional specifiers (`%2$@ results for “%1$@”`)
// because the count and the search string appear in the opposite order to the
// arguments. Get the positions wrong and the sentence reads
// "Found needle results for “2”" — which compiles, and which this catches.
void test_result_count_string_does_not_transpose_its_arguments ()
{
	NSString* plural = [Find resultCountStringForCount:7 searchString:@"needle"];
	OAK_ASSERT([plural isEqualToString:@"Found 7 results for “needle”."]);
	OAK_ASSERT([plural rangeOfString:@"“needle”"].location != NSNotFound);
}

// Counts are localized, so a four-digit count carries a group separator. This is
// what stops a port from reaching for a plain string interpolation of the number.
void test_result_count_string_localizes_the_count ()
{
	NSString* many = [Find resultCountStringForCount:1234 searchString:@"needle"];
	OAK_ASSERT([many rangeOfString:LocalizedCount(1234)].location != NSNotFound);
}

// ==========================================
// = And what it reports after a row is cut =
// ==========================================

void test_shown_result_count_string_pluralises ()
{
	OAK_ASSERT([[Find shownResultCountStringForCount:0 searchString:@"needle"] isEqualToString:@"No results for “needle”."]);
	OAK_ASSERT([[Find shownResultCountStringForCount:1 searchString:@"needle"] isEqualToString:@"Showing one result for “needle”."]);
	OAK_ASSERT([[Find shownResultCountStringForCount:2 searchString:@"needle"] isEqualToString:@"Showing 2 results for “needle”."]);
}

// "Found" and "Showing" are two different sentences for two different moments —
// what the search turned up, versus what is left in the list after rows were
// removed. A port that reuses one for both loses that distinction, and nothing
// else in the suite would notice.
void test_found_and_shown_are_different_sentences ()
{
	OAK_ASSERT(![[Find resultCountStringForCount:2 searchString:@"needle"] isEqualToString:[Find shownResultCountStringForCount:2 searchString:@"needle"]]);
	OAK_ASSERT(![[Find resultCountStringForCount:0 searchString:@"needle"] isEqualToString:[Find shownResultCountStringForCount:0 searchString:@"needle"]]);
}

// ===================================================
// = The parenthetical a folder search appends (:1188) =
// ===================================================

void test_searched_files_suffix_pluralises ()
{
	OAK_ASSERT([[Find searchedFilesSuffixForFileCount:1 seconds:@"0.5"] isEqualToString:@" (searched one file in 0.5 seconds)"]);
	OAK_ASSERT([[Find searchedFilesSuffixForFileCount:2 seconds:@"0.5"] isEqualToString:@" (searched 2 files in 0.5 seconds)"]);
	OAK_ASSERT([[Find searchedFilesSuffixForFileCount:0 seconds:@"0.5"] isEqualToString:@" (searched 0 files in 0.5 seconds)"]);
}

// The two branches take their arguments in opposite orders — the singular is
// `%@` (seconds), the plural is `%2$@ … %1$@` (count, then seconds). They are one
// ternary inside one -stringWithFormat: call, sharing an argument list, which is
// how they came to disagree. Swapping them yields " (searched 0.5 files in 2
// seconds)".
void test_searched_files_suffix_does_not_transpose_count_and_seconds ()
{
	NSString* singular = [Find searchedFilesSuffixForFileCount:1 seconds:@"12.3"];
	OAK_ASSERT([singular rangeOfString:@"one file"].location != NSNotFound);
	OAK_ASSERT([singular rangeOfString:@"12.3 seconds"].location != NSNotFound);

	NSString* plural = [Find searchedFilesSuffixForFileCount:9 seconds:@"12.3"];
	OAK_ASSERT([plural rangeOfString:@"9 files"].location != NSNotFound);
	OAK_ASSERT([plural rangeOfString:@"12.3 seconds"].location != NSNotFound);
}

void test_searched_files_suffix_localizes_the_file_count ()
{
	OAK_ASSERT([[Find searchedFilesSuffixForFileCount:4096 seconds:@"1"] rangeOfString:LocalizedCount(4096)].location != NSNotFound);
}

// It is a suffix, appended to a sentence that already ends in a full stop, so it
// has to start with its own space and must not start a new sentence.
void test_searched_files_suffix_is_appendable ()
{
	NSString* suffix = [Find searchedFilesSuffixForFileCount:3 seconds:@"1"];
	OAK_ASSERT([suffix hasPrefix:@" ("]);
	OAK_ASSERT([suffix hasSuffix:@")"]);

	NSString* whole = [[Find resultCountStringForCount:3 searchString:@"needle"] stringByAppendingString:suffix];
	OAK_ASSERT([whole isEqualToString:@"Found 3 results for “needle”. (searched 3 files in 1 seconds)"]);
}

// ==========================
// = Replace All's tally    =
// ==========================

// Two independent counts, two independent plurals, in one sentence — so all four
// combinations are reachable and exactly one of them ("1 replacement … 1 file")
// is the one a port gets wrong.
void test_replacement_status_string_pluralises_both_counts_independently ()
{
	OAK_ASSERT([[Find replacementStatusStringForReplacementCount:1 fileCount:1] isEqualToString:@"1 replacement made across 1 file."]);
	OAK_ASSERT([[Find replacementStatusStringForReplacementCount:2 fileCount:1] isEqualToString:@"2 replacements made across 1 file."]);
	OAK_ASSERT([[Find replacementStatusStringForReplacementCount:1 fileCount:2] isEqualToString:@"1 replacement made across 2 files."]);
	OAK_ASSERT([[Find replacementStatusStringForReplacementCount:5 fileCount:3] isEqualToString:@"5 replacements made across 3 files."]);
}

// Unlike the sentences above, this one uses the numeral at one — "1 replacement",
// not "one replacement". The inconsistency is in the original and is preserved
// on purpose; it is recorded here so a port does not "fix" it into a difference.
void test_replacement_status_string_uses_the_numeral_at_one ()
{
	NSString* one = [Find replacementStatusStringForReplacementCount:1 fileCount:1];
	OAK_ASSERT([one rangeOfString:@"1 replacement"].location != NSNotFound);
	OAK_ASSERT([one rangeOfString:@"one replacement"].location == NSNotFound);
}

void test_replacement_status_string_localizes_its_counts ()
{
	NSString* many = [Find replacementStatusStringForReplacementCount:2048 fileCount:1024];
	OAK_ASSERT([many rangeOfString:LocalizedCount(2048)].location != NSNotFound);
	OAK_ASSERT([many rangeOfString:LocalizedCount(1024)].location != NSNotFound);
}

// ===================================================
// = What an in-document Replace reports (didReplace) =
// ===================================================

// A 2×3 table indexed by [regexp][min(count, 2)] — so "occurrence"/"match" is
// chosen by whether the search was a regexp, which is a distinction no other
// status string in this file makes.
void test_replaced_status_string_pluralises ()
{
	OAK_ASSERT([[Find replacedStatusStringForCount:0 findString:@"x" regularExpression:NO] isEqualToString:@"Nothing replaced (no occurrences of “x”)."]);
	OAK_ASSERT([[Find replacedStatusStringForCount:1 findString:@"x" regularExpression:NO] isEqualToString:@"Replaced one occurrence of “x”."]);
	OAK_ASSERT([[Find replacedStatusStringForCount:2 findString:@"x" regularExpression:NO] isEqualToString:@"Replaced 2 occurrences of “x”."]);
}

void test_replaced_status_string_says_matches_for_a_regular_expression ()
{
	OAK_ASSERT([[Find replacedStatusStringForCount:0 findString:@"x" regularExpression:YES] isEqualToString:@"Nothing replaced (no matches for “x”)."]);
	OAK_ASSERT([[Find replacedStatusStringForCount:1 findString:@"x" regularExpression:YES] isEqualToString:@"Replaced one match of “x”."]);
	OAK_ASSERT([[Find replacedStatusStringForCount:2 findString:@"x" regularExpression:YES] isEqualToString:@"Replaced 2 matches of “x”."]);

	// Every row differs from its non-regexp twin, so the flag cannot be ignored.
	for(NSUInteger n = 0; n < 4; ++n)
		OAK_MASSERT("regexp and literal wording should differ", ![[Find replacedStatusStringForCount:n findString:@"x" regularExpression:YES] isEqualToString:[Find replacedStatusStringForCount:n findString:@"x" regularExpression:NO]]);
}

// The row index is `count > 2 ? 2 : count`, which reads like an off-by-one and is
// not one: at exactly 2 it already takes the plural row. Pinned because it is the
// clamp a port most plausibly rewrites as `min(count, 2)` — the same thing — or
// as `count > 1 ? 2 : count`, which is also the same thing here, or as
// `count >= 2 ? 2 : count`. All three agree; a `> 3` typo would not, and nothing
// else would catch it.
void test_replaced_status_string_clamps_at_two ()
{
	NSString* two    = [Find replacedStatusStringForCount:2 findString:@"x" regularExpression:NO];
	NSString* three  = [Find replacedStatusStringForCount:3 findString:@"x" regularExpression:NO];
	NSString* many   = [Find replacedStatusStringForCount:99 findString:@"x" regularExpression:NO];

	OAK_ASSERT([two   isEqualToString:@"Replaced 2 occurrences of “x”."]);
	OAK_ASSERT([three isEqualToString:@"Replaced 3 occurrences of “x”."]);
	OAK_ASSERT([many  isEqualToString:@"Replaced 99 occurrences of “x”."]);
}
