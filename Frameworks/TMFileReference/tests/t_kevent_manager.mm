#import <TMFileReference/KEventManager.h>
#import <test/jail.h>

// KEventManager watches paths through dispatch_source VNODE sources, one per
// path component, and had no coverage at all — which is why the descriptor
// lifetime bug in -tearDownEventSource survived: nothing ever set a watcher up
// and tore it down in a test.
//
// Everything here drives the real thing against real files in a temp jail, and
// turns the run loop rather than sleeping, because the sources deliver on the
// main queue.
//
// ⚠️ Test bundles compile with **ARC off** (see CLANG_ENABLE_OBJC_ARC in
// ide/seed_xcodeproj.rb), so a `__block` *object* variable written from a
// callback is NOT retained — the value here is an autoreleased NSURL, and
// reading it after the run loop turns is a use-after-free. Copy what is needed
// out of the callback instead, which is why the path is captured as a
// std::string below. Cost of learning that: a SIGSEGV in objc_msgSend.

// Spin until `predicate` holds or the timeout expires, so a regression fails
// instead of hanging the bundle.
static BOOL wait_until (BOOL(^predicate)(void), NSTimeInterval timeout = 5.0)
{
	NSDate* giveUp = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while(!predicate() && [giveUp timeIntervalSinceNow] > 0)
		[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
	return predicate();
}

void test_observer_fires_when_the_file_is_written ()
{
	test::jail_t jail;
	jail.set_content("watched.txt", "before");

	__block NSUInteger events = 0;
	NSURL* url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:jail.path("watched.txt").c_str()]];
	id observer = [KEventManager.sharedInstance addObserverToItemAtURL:url usingBlock:^(NSURL* changedURL, NSUInteger mask){
		++events;
	}];

	OAK_ASSERT(observer);

	jail.set_content("watched.txt", "after");
	OAK_ASSERT(wait_until(^{ return events != 0; }));

	[KEventManager.sharedInstance removeObserver:observer];
}

void test_observer_stops_firing_once_removed ()
{
	test::jail_t jail;
	jail.set_content("removed.txt", "before");

	__block NSUInteger events = 0;
	NSURL* url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:jail.path("removed.txt").c_str()]];
	id observer = [KEventManager.sharedInstance addObserverToItemAtURL:url usingBlock:^(NSURL* changedURL, NSUInteger mask){
		++events;
	}];

	jail.set_content("removed.txt", "after");
	OAK_ASSERT(wait_until(^{ return events != 0; }));

	// Removing the last observer is what tears the event source down — the path
	// the descriptor bug lived on.
	[KEventManager.sharedInstance removeObserver:observer];

	NSUInteger const before = events;
	jail.set_content("removed.txt", "after removal");

	// Give any stray event a chance to arrive rather than asserting immediately.
	wait_until(^{ return events != before; }, 0.5);
	OAK_ASSERT_EQ(events, before);
}

// Two observers on one path share a node, so the source must survive the first
// removal and only tear down with the second.
void test_a_shared_path_survives_one_observer_leaving ()
{
	test::jail_t jail;
	jail.set_content("shared.txt", "before");

	__block NSUInteger firstEvents = 0, secondEvents = 0;
	NSURL* url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:jail.path("shared.txt").c_str()]];

	id first  = [KEventManager.sharedInstance addObserverToItemAtURL:url usingBlock:^(NSURL* u, NSUInteger m){ ++firstEvents;  }];
	id second = [KEventManager.sharedInstance addObserverToItemAtURL:url usingBlock:^(NSURL* u, NSUInteger m){ ++secondEvents; }];

	[KEventManager.sharedInstance removeObserver:first];

	jail.set_content("shared.txt", "after");
	OAK_ASSERT(wait_until(^{ return secondEvents != 0; }));

	[KEventManager.sharedInstance removeObserver:second];
}

// Tearing a watcher down and immediately setting another one up is the exact
// sequence -handleKEvent: runs on a rename, and the one that made the early
// close() dangerous: the descriptor number would have been free for the new
// open() to claim while the cancelled source still referenced it. Repeated so
// that a reused number is likely rather than theoretical.
void test_rapid_teardown_and_setup_keeps_watching_the_right_file ()
{
	test::jail_t jail;
	jail.set_content("churn.txt", "before");
	jail.set_content("decoy.txt", "decoy");

	NSURL* url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:jail.path("churn.txt").c_str()]];

	for(NSUInteger i = 0; i < 20; ++i)
	{
		id observer = [KEventManager.sharedInstance addObserverToItemAtURL:url usingBlock:^(NSURL* u, NSUInteger m){ }];
		[KEventManager.sharedInstance removeObserver:observer];

		// Claim descriptors in the window a prematurely-closed one would have
		// left open, which is what turns the bug from latent into observable.
		int decoys[8];
		for(size_t j = 0; j < 8; ++j)
			decoys[j] = open(jail.path("decoy.txt").c_str(), O_RDONLY|O_CLOEXEC);
		for(size_t j = 0; j < 8; ++j)
		{
			if(decoys[j] != -1)
				close(decoys[j]);
		}
	}

	// After all that churn a fresh observer must still report changes to the
	// file it was actually given — a recycled descriptor would have it reporting
	// the decoy instead.
	__block std::string reportedName;
	id observer = [KEventManager.sharedInstance addObserverToItemAtURL:url usingBlock:^(NSURL* changedURL, NSUInteger mask){
		// -UTF8String rather than ns::to_s: this framework does not depend on
		// `ns`, and the std::string assignment copies before the autoreleased
		// buffer can go away.
		reportedName = changedURL.path.lastPathComponent.UTF8String ?: "";
	}];

	jail.set_content("churn.txt", "after");
	OAK_ASSERT(wait_until(^{ return !reportedName.empty(); }));
	OAK_ASSERT_EQ(reportedName, "churn.txt");

	[KEventManager.sharedInstance removeObserver:observer];
}
