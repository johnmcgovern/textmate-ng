#import "DocumentWindowTesting.h"
#import <document/OakDocument.h>

// NOTE on the extra parentheses below: OAK_ASSERT is a one-argument macro and
// the preprocessor does not treat @[ ] as grouping, so a comma inside an array
// literal would split the argument. Wrapping the expression is the fix.
//
// The first tests against DocumentWindowController — the 2885-line window
// controller, and the largest single file left in the migration.
//
// Two things are being established here, in this order, because the second
// depends on the answer to the first:
//
//  1. **Is the controller constructible in a test process at all?** Its -init
//     stands up an OakDocumentView, which is the C++ text engine, a window, a
//     tab bar, an array controller and eight KVO registrations. Find's
//     controller turned out to be constructible and CrashReporter's did not, so
//     this is asserted rather than assumed — it decides whether the rest of this
//     framework's coverage can use instances.
//
//  2. **The tab-reordering subsequence test**, which is the one piece of real
//     algorithm in the file and the one most likely to be quietly rewritten.

void test_document_window_controller_is_constructible ()
{
	DocumentWindowController* controller = [DocumentWindowController new];
	OAK_ASSERT(controller != nil);
	OAK_ASSERT(controller.window != nil);
	OAK_ASSERT_EQ(controller.documents.count, 0);
}

// ==================================================================
// = -documentsHaveCommonSubsequence: the animation decision         =
// ==================================================================
//
// Asked before replacing the tab array: if the old and new orders share a
// consistent subsequence, the change is animated, because tabs appear to slide.
// If they do not, animation is suppressed, because tabs would appear to swap
// places at random.
//
// It is a **class** method rather than an instance one. In the ObjC++ it was an
// instance method that touched no instance state, and hoisting it is what lets
// these tests run whatever the answer to the constructibility question above.
// The port keeps that spelling — DocumentWindowTesting.h pins it.

static OakDocument* Doc (NSString* name)
{
	return [OakDocument documentWithString:@"" fileType:@"text.plain" customName:name];
}

void test_identical_orders_have_a_common_subsequence ()
{
	OakDocument* a = Doc(@"a"); OakDocument* b = Doc(@"b"); OakDocument* c = Doc(@"c");
	OAK_ASSERT(([DocumentWindowController documents:@[ a, b, c ] hasCommonSubsequenceWithDocuments:@[ a, b, c ]]));
}

// Nothing in common is vacuously consistent — there is no pair to disagree
// about, so the move animates.
void test_disjoint_orders_have_a_common_subsequence ()
{
	OakDocument* a = Doc(@"a"); OakDocument* b = Doc(@"b");
	OakDocument* x = Doc(@"x"); OakDocument* y = Doc(@"y");
	OAK_ASSERT(([DocumentWindowController documents:@[ a, b ] hasCommonSubsequenceWithDocuments:@[ x, y ]]));
	OAK_ASSERT(([DocumentWindowController documents:@[] hasCommonSubsequenceWithDocuments:@[ x, y ]]));
	OAK_ASSERT(([DocumentWindowController documents:@[ a, b ] hasCommonSubsequenceWithDocuments:@[]]));
}

// Documents added and removed around a stable core still animate: the shared
// documents appear in the same relative order in both lists.
void test_insertions_around_a_stable_core_keep_the_subsequence ()
{
	OakDocument* a = Doc(@"a"); OakDocument* b = Doc(@"b"); OakDocument* c = Doc(@"c");
	OakDocument* n = Doc(@"new");

	OAK_ASSERT(([DocumentWindowController documents:@[ a, b, c ] hasCommonSubsequenceWithDocuments:@[ n, a, b, c ]]));
	OAK_ASSERT(([DocumentWindowController documents:@[ a, b, c ] hasCommonSubsequenceWithDocuments:@[ a, b ]]));
}

// And the case the whole thing exists to catch: two shared documents whose
// relative order is reversed. Animating that reads as tabs teleporting.
void test_a_reversed_pair_has_no_common_subsequence ()
{
	OakDocument* a = Doc(@"a"); OakDocument* b = Doc(@"b");
	OAK_ASSERT((![DocumentWindowController documents:@[ a, b ] hasCommonSubsequenceWithDocuments:@[ b, a ]]));
}

// The loop advances i and j *unconditionally* at the end of each iteration, on
// top of whichever branch already advanced one of them — so a non-shared element
// moves its index by two, not one. That reads like a bug and is load-bearing:
// rewriting it as the obvious two-pointer walk changes which reorderings animate.
// This case is the one that distinguishes them.
void test_the_double_advance_is_preserved ()
{
	OakDocument* a = Doc(@"a"); OakDocument* b = Doc(@"b"); OakDocument* c = Doc(@"c");
	OakDocument* x = Doc(@"x");

	// `x` is in neither intersection position; the ObjC++ skips past `a` as well
	// on that iteration, and so never compares a against a.
	OAK_ASSERT(([DocumentWindowController documents:@[ x, a, b ] hasCommonSubsequenceWithDocuments:@[ a, b ]]));
	OAK_ASSERT(([DocumentWindowController documents:@[ a, b, c ] hasCommonSubsequenceWithDocuments:@[ c, b, a ]] == NO));
}

// ==================================================================
// = Sticky tabs                                                     =
// ==================================================================
//
// A sticky tab survives "close other tabs". The set is created lazily, so
// asking about a document before anything is sticky must answer NO rather than
// trap — the implicitly-unwrapped-optional trap this project hit on
// FFResultsViewController's outline view.

void test_no_document_is_sticky_by_default ()
{
	DocumentWindowController* controller = [DocumentWindowController new];
	OAK_ASSERT(![controller isDocumentSticky:Doc(@"a")]);
}

void test_sticky_round_trips ()
{
	DocumentWindowController* controller = [DocumentWindowController new];
	OakDocument* a = Doc(@"a");
	OakDocument* b = Doc(@"b");

	[controller setDocument:a sticky:YES];
	OAK_ASSERT([controller isDocumentSticky:a]);
	OAK_ASSERT(![controller isDocumentSticky:b]);

	[controller setDocument:a sticky:NO];
	OAK_ASSERT(![controller isDocumentSticky:a]);
}

// Un-sticking something that was never sticky must not create the set or throw —
// it is reachable from the Tabs menu before anything has been made sticky.
void test_unsticking_an_unknown_document_is_harmless ()
{
	DocumentWindowController* controller = [DocumentWindowController new];
	[controller setDocument:Doc(@"a") sticky:NO];
	OAK_ASSERT(![controller isDocumentSticky:Doc(@"a")]);
}
