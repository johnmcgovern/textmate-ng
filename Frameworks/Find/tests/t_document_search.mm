#import "../src/FFDocumentSearch.h"
#import <document/OakDocument.h>
#import <test/jail.h>
#import <ns/ns.h>

// FFDocumentSearch is the folder search's driver: it enumerates documents on a
// background queue, accumulates matches, and hands them to the UI in batches
// from a 0.2s poll timer on the main thread. It had no coverage.
//
// What makes it worth testing before the port is that none of the interesting
// behaviour is in the search — that belongs to OakDocumentController and the
// regexp layer — it is in the *handover*: a token that invalidates an in-flight
// enumeration, a mutable array shared across two queues, and a timer that
// reschedules itself until the search says it is done. Those are the parts a
// port rewrites and a compiler cannot check.
//
// Everything drives the real thing against real files in a temp jail, and turns
// the run loop rather than sleeping, because the results arrive on the main
// queue. Same shape as t_kevent_manager.mm.
//
// ⚠️ Test bundles compile with ARC off (CLANG_ENABLE_OBJC_ARC in
// ide/seed_xcodeproj.rb), so a `__block` *object* written from a callback is not
// retained. Everything captured out of a notification here is a primitive.

static BOOL wait_until (BOOL(^predicate)(void), NSTimeInterval timeout = 10.0)
{
	NSDate* giveUp = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while(!predicate() && [giveUp timeIntervalSinceNow] > 0)
		[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
	return predicate();
}

static FFDocumentSearch* SearchFor (NSString* needle, test::jail_t const& jail)
{
	FFDocumentSearch* search = [FFDocumentSearch new];
	search.searchString = needle;
	search.paths        = @[ [NSString stringWithUTF8String:jail.path().c_str()] ];
	// Required, not optional — see test_a_nil_glob_searches_nothing. Find.mm:933
	// always supplies one and the UI defaults it to "*".
	search.glob         = @"*";
	return search;
}

// A jail with three files: two containing the needle (three matches between
// them), one without, plus a nested directory so the walk has to recurse.
static void populate (test::jail_t& jail)
{
	jail.set_content("one.txt",     "alpha\nNEEDLE here\ngamma\ndelta NEEDLE again\n");
	jail.set_content("sub/two.txt", "first\nsecond\nthird NEEDLE\n");
	jail.set_content("sub/none.md", "nothing to see\n");
}

// =====================
// = The happy path    =
// =====================

void test_search_delivers_every_match_then_finishes ()
{
	test::jail_t jail;
	populate(jail);

	__block NSUInteger received = 0;
	__block BOOL finished = NO;

	FFDocumentSearch* search = SearchFor(@"NEEDLE", jail);

	// The matches array is read *inside* the callback on purpose — see
	// test_the_delivered_array_is_emptied_after_posting below.
	id r = [NSNotificationCenter.defaultCenter addObserverForName:FFDocumentSearchDidReceiveResultsNotification object:search queue:nil usingBlock:^(NSNotification* note){
		received += [note.userInfo[@"matches"] count];
	}];
	id f = [NSNotificationCenter.defaultCenter addObserverForName:FFDocumentSearchDidFinishNotification object:search queue:nil usingBlock:^(NSNotification* note){
		finished = YES;
	}];

	[search start];
	OAK_ASSERT(wait_until(^{ return finished; }));
	OAK_ASSERT_EQ(received, 3);

	[NSNotificationCenter.defaultCenter removeObserver:r];
	[NSNotificationCenter.defaultCenter removeObserver:f];
}

// A search that matches nothing still has to finish, or the UI stays stuck on
// "searching" forever.
void test_a_search_with_no_matches_still_finishes ()
{
	test::jail_t jail;
	populate(jail);

	__block NSUInteger received = 0;
	__block BOOL finished = NO;

	FFDocumentSearch* search = SearchFor(@"NOTHINGMATCHESTHIS", jail);
	id r = [NSNotificationCenter.defaultCenter addObserverForName:FFDocumentSearchDidReceiveResultsNotification object:search queue:nil usingBlock:^(NSNotification* note){
		received += [note.userInfo[@"matches"] count];
	}];
	id f = [NSNotificationCenter.defaultCenter addObserverForName:FFDocumentSearchDidFinishNotification object:search queue:nil usingBlock:^(NSNotification* note){
		finished = YES;
	}];

	[search start];
	OAK_ASSERT(wait_until(^{ return finished; }));
	OAK_ASSERT_EQ(received, 0);

	[NSNotificationCenter.defaultCenter removeObserver:r];
	[NSNotificationCenter.defaultCenter removeObserver:f];
}

// ==================================================
// = The handover: a shared array, cleared on post  =
// ==================================================

// -updateMatches: posts the *live* _matches array and then empties it, so the
// userInfo an observer keeps a reference to is worthless the moment the
// notification returns. Find.mm gets away with it by consuming synchronously.
// Pinned because it is exactly the shape a port "cleans up" into a copy — which
// would be an improvement, and therefore a behaviour change to make on purpose.
void test_the_delivered_array_is_emptied_after_posting ()
{
	test::jail_t jail;
	populate(jail);

	__block NSUInteger countInsideCallback = 0;
	__block NSUInteger countAfterReturn    = 0;
	__block BOOL finished = NO;

	FFDocumentSearch* search = SearchFor(@"NEEDLE", jail);
	__block NSArray* delivered = nil;   // retained by the notification's userInfo for the test's lifetime

	id r = [NSNotificationCenter.defaultCenter addObserverForName:FFDocumentSearchDidReceiveResultsNotification object:search queue:nil usingBlock:^(NSNotification* note){
		NSArray* matches = note.userInfo[@"matches"];
		if(!countInsideCallback)
		{
			countInsideCallback = matches.count;
			delivered = [matches retain];
		}
	}];
	id f = [NSNotificationCenter.defaultCenter addObserverForName:FFDocumentSearchDidFinishNotification object:search queue:nil usingBlock:^(NSNotification* note){
		finished = YES;
	}];

	[search start];
	OAK_ASSERT(wait_until(^{ return finished; }));

	countAfterReturn = delivered.count;

	OAK_ASSERT_GT(countInsideCallback, 0);
	OAK_ASSERT_EQ(countAfterReturn, 0);

	[delivered release];
	[NSNotificationCenter.defaultCenter removeObserver:r];
	[NSNotificationCenter.defaultCenter removeObserver:f];
}

// =================
// = Bookkeeping   =
// =================

void test_scanned_counts_cover_every_file ()
{
	test::jail_t jail;
	populate(jail);

	__block BOOL finished = NO;
	FFDocumentSearch* search = SearchFor(@"NEEDLE", jail);
	id f = [NSNotificationCenter.defaultCenter addObserverForName:FFDocumentSearchDidFinishNotification object:search queue:nil usingBlock:^(NSNotification* note){
		finished = YES;
	}];

	[search start];
	OAK_ASSERT(wait_until(^{ return finished; }));

	// All three files are scanned, including the one with no match.
	OAK_ASSERT_EQ(search.scannedFileCount, 3);
	OAK_ASSERT_GT(search.scannedByteCount, 0);
	OAK_ASSERT_GT(search.searchDuration, 0);

	[NSNotificationCenter.defaultCenter removeObserver:f];
}

// -start resets the match buffer but *not* the scanned counters, so a second
// search on the same object reports the sum of both. Unreachable from the UI —
// Find.mm assigns a fresh FFDocumentSearch per search (Find.mm:1111) — which is
// precisely why it has never been noticed. Pinned as behaviour, not endorsed.
void test_a_second_start_accumulates_the_scanned_counters ()
{
	test::jail_t jail;
	populate(jail);

	__block NSUInteger finishes = 0;
	FFDocumentSearch* search = SearchFor(@"NEEDLE", jail);
	id f = [NSNotificationCenter.defaultCenter addObserverForName:FFDocumentSearchDidFinishNotification object:search queue:nil usingBlock:^(NSNotification* note){
		++finishes;
	}];

	[search start];
	OAK_ASSERT(wait_until(^{ return finishes == 1; }));
	OAK_ASSERT_EQ(search.scannedFileCount, 3);

	[search start];
	OAK_ASSERT(wait_until(^{ return finishes == 2; }));
	OAK_ASSERT_EQ(search.scannedFileCount, 6);

	[NSNotificationCenter.defaultCenter removeObserver:f];
}

// =================
// = Cancellation  =
// =================

// -stop bumps the token the enumeration block compares against, so an in-flight
// search stops delivering and never posts DidFinish. The UI relies on this when
// a window closes mid-search.
void test_stop_prevents_the_finish_notification ()
{
	test::jail_t jail;
	populate(jail);

	__block BOOL finished = NO;
	FFDocumentSearch* search = SearchFor(@"NEEDLE", jail);
	id f = [NSNotificationCenter.defaultCenter addObserverForName:FFDocumentSearchDidFinishNotification object:search queue:nil usingBlock:^(NSNotification* note){
		finished = YES;
	}];

	[search start];
	[search stop];

	// Turn the run loop well past the point a live search would have finished.
	NSDate* until = [NSDate dateWithTimeIntervalSinceNow:1.0];
	while([until timeIntervalSinceNow] > 0)
		[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];

	OAK_ASSERT(!finished);

	[NSNotificationCenter.defaultCenter removeObserver:f];
}

// Calling -stop on a search that never started must be harmless — the results
// view controller does it unconditionally.
void test_stop_without_start_is_harmless ()
{
	FFDocumentSearch* search = [FFDocumentSearch new];
	[search stop];
	[search stop];
	OAK_ASSERT_EQ(search.scannedFileCount, 0);
}

// =================
// = Globbing      =
// =================

// `glob` looks optional — it is a plain property with no documented default,
// and nothing rejects a search without one. But GlobOptionsForPath puts
// `glob ? @[glob] : @[]` into kSearchFileGlobsKey, and an *empty* file-glob
// list matches no files at all, so a nil glob scans nothing and reports a
// clean, instant, entirely empty search.
//
// Unreachable from the UI, which always supplies one (Find.mm:933) — so this is
// a trap for the next caller rather than a live bug. Worth pinning before the
// port, because a Swift `String?` invites treating nil as "no filter".
void test_a_nil_glob_searches_nothing ()
{
	test::jail_t jail;
	populate(jail);

	__block BOOL finished = NO;
	FFDocumentSearch* search = SearchFor(@"NEEDLE", jail);
	search.glob = nil;
	id f = [NSNotificationCenter.defaultCenter addObserverForName:FFDocumentSearchDidFinishNotification object:search queue:nil usingBlock:^(NSNotification* note){
		finished = YES;
	}];

	[search start];
	OAK_ASSERT(wait_until(^{ return finished; }));
	OAK_ASSERT_EQ(search.scannedFileCount, 0);

	[NSNotificationCenter.defaultCenter removeObserver:f];
}

void test_glob_limits_which_files_are_searched ()
{
	test::jail_t jail;
	populate(jail);

	__block BOOL finished = NO;
	FFDocumentSearch* search = SearchFor(@"NEEDLE", jail);
	search.glob = @"*.md";
	id f = [NSNotificationCenter.defaultCenter addObserverForName:FFDocumentSearchDidFinishNotification object:search queue:nil usingBlock:^(NSNotification* note){
		finished = YES;
	}];

	[search start];
	OAK_ASSERT(wait_until(^{ return finished; }));

	// Only sub/none.md matches the glob, and it holds no NEEDLE.
	OAK_ASSERT_EQ(search.scannedFileCount, 1);

	[NSNotificationCenter.defaultCenter removeObserver:f];
}
