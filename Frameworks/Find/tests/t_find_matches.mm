#import "FindTesting.h"
#import "../src/FFResultNode.h"
#import <document/OakDocument.h>

// -acceptMatches: is where the results tree is assembled: one branch per
// distinct document, leaves in document order, CommonAncestor applied once to
// pick the base directory every file row is displayed relative to
// (Find.swift's -acceptMatches:). It is the most valuable thing in Find that can be tested
// without a window, and it is untested.
//
// Neither the method nor the `results` property is in Find.h — both live in the
// class extension — so they are declared in FindTesting.h, which has to be a
// header rather than an inline @interface: gen_xctest.rb wraps each test body in
// a namespace, and ObjC declarations may only appear at global scope.

static OakDocumentMatch* MatchIn (OakDocument* document, NSUInteger lineNumber)
{
	OakDocumentMatch* match = [OakDocumentMatch new];
	match.document = document;
	match.excerpt  = @"NEEDLE";
	match.first    = 0;
	match.last     = 6;
	return match;
}

// Establishes what the rest of this file depends on: that Find is constructible
// outside a bundled app. Its -init calls -initWithWindowNibName:@"UNUSED" — a
// placeholder, since the window is built in code — and stands up two pasteboard
// view controllers and two history lists. CrashReporter is the counterexample
// that makes this worth asserting rather than assuming.
void test_find_is_constructible ()
{
	Find* find = [Find new];
	OAK_ASSERT(find != nil);
	OAK_ASSERT(!find.isVisible);
}

void test_accept_matches_groups_leaves_under_one_branch_per_document ()
{
	Find* find = [Find new];
	find.results = [FFResultNode new];

	OakDocument* one = [OakDocument documentWithString:@"NEEDLE here\n" fileType:@"text.plain" customName:@"one.txt"];
	OakDocument* two = [OakDocument documentWithString:@"NEEDLE there\n" fileType:@"text.plain" customName:@"two.txt"];

	[find acceptMatches:@[ MatchIn(one, 1), MatchIn(one, 2), MatchIn(two, 1) ]];

	OAK_ASSERT_EQ(find.results.children.count, 2);
	OAK_ASSERT_EQ(find.results.countOfLeafs, 3);

	FFResultNode* firstFile = find.results.firstResultNode;
	OAK_ASSERT_EQ(firstFile.children.count, 2);
	OAK_ASSERT_EQ(firstFile.countOfLeafs, 2);
	OAK_ASSERT(firstFile.document == one);

	FFResultNode* secondFile = find.results.lastResultNode;
	OAK_ASSERT_EQ(secondFile.children.count, 1);
	OAK_ASSERT(secondFile.document == two);
}

// Consecutive matches in the same document share a branch; a return to an
// earlier document starts a *new* one, because the grouping compares against the
// previous match only rather than searching for an existing branch.
void test_accept_matches_starts_a_new_branch_when_a_document_recurs ()
{
	Find* find = [Find new];
	find.results = [FFResultNode new];

	OakDocument* one = [OakDocument documentWithString:@"NEEDLE\n" fileType:@"text.plain" customName:@"one.txt"];
	OakDocument* two = [OakDocument documentWithString:@"NEEDLE\n" fileType:@"text.plain" customName:@"two.txt"];

	[find acceptMatches:@[ MatchIn(one, 1), MatchIn(two, 1), MatchIn(one, 2) ]];

	OAK_ASSERT_EQ(find.results.children.count, 3);
	OAK_ASSERT_EQ(find.results.countOfLeafs, 3);
}

// Matches arriving in separate batches — which is how the search delivers them,
// one poll-timer tick at a time — accumulate into the same tree.
void test_accept_matches_accumulates_across_batches ()
{
	Find* find = [Find new];
	find.results = [FFResultNode new];

	OakDocument* one = [OakDocument documentWithString:@"NEEDLE\n" fileType:@"text.plain" customName:@"one.txt"];

	[find acceptMatches:@[ MatchIn(one, 1) ]];
	OAK_ASSERT_EQ(find.results.countOfLeafs, 1);

	[find acceptMatches:@[ MatchIn(one, 2) ]];
	OAK_ASSERT_EQ(find.results.countOfLeafs, 2);
	OAK_ASSERT_EQ(find.results.children.count, 2);
}
