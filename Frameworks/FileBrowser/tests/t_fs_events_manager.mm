#import "../src/FSEventsManager.h"

// Written against the ObjC++ FSEventsManager, before the Swift port, so these
// judge the original and not the translation (the DocumentWindowController
// lesson).
//
// The testable seam is -reloadDirectoryAtURL:, which drives the same delivery
// path the FSEventStream callback drives but synchronously and without waiting
// on the real event stream. What it cannot reach is the observeSubdirectories:
// flag: -reloadDirectoryAtURL: looks the directory up by the very URL it then
// passes to -didObserveChangeInDirectoryAtURL:, so changeInCurrentDirectory is
// always true and the subdirectory branch never runs. That branch is only
// reachable from the callback's walk up the parent chain, so it is pinned here
// only to the extent that a subdirectory observer still fires for its *own*
// directory — see test_an_observer_fires_for_its_own_directory_either_way.
//
// The manager is a singleton, so every test removes what it adds. Directories
// are held by a strongToWeakObjectsMapTable — the map does not own them, their
// clients do — which is why "the last observer going away drops the directory"
// is a behaviour worth its own test rather than an implementation detail.

static NSURL* TempDirectory ()
{
	NSURL* url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]] isDirectory:YES];
	[[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
	return url;
}

void setup ()
{
	NSApplicationLoad();
}

void test_fs_events_manager_keeps_its_selector_surface ()
{
	// Rule 18. Every one of these has a caller outside this framework or inside
	// FileItemObserver, and none of them is reached through a protocol, so a
	// rename or a mis-imported Swift spelling would be invisible to the compiler.
	SEL const selectors[] = {
		@selector(addObserverToDirectoryAtURL:usingBlock:),
		@selector(addObserverToDirectoryAtURL:observeSubdirectories:usingBlock:),
		@selector(removeObserver:),
		@selector(reloadDirectoryAtURL:),
	};

	for(SEL selector : selectors)
		OAK_ASSERT([FSEventsManager instancesRespondToSelector:selector]);

	OAK_ASSERT([FSEventsManager respondsToSelector:@selector(sharedInstance)]);
}

void test_fs_events_manager_is_a_singleton ()
{
	OAK_ASSERT(FSEventsManager.sharedInstance != nil);
	OAK_ASSERT(FSEventsManager.sharedInstance == FSEventsManager.sharedInstance);
}

void test_an_observer_fires_for_its_own_directory ()
{
	NSURL* url = TempDirectory();

	__block NSUInteger count = 0;
	__block NSURL* observed = nil;
	id token = [FSEventsManager.sharedInstance addObserverToDirectoryAtURL:url usingBlock:^(NSURL* changedURL){
		++count;
		observed = changedURL;
	}];
	OAK_ASSERT(token != nil);

	[FSEventsManager.sharedInstance reloadDirectoryAtURL:url];
	OAK_ASSERT_EQ(count, 1);
	OAK_ASSERT([observed isEqual:url]);

	[FSEventsManager.sharedInstance removeObserver:token];
}

void test_an_observer_fires_for_its_own_directory_either_way ()
{
	// observeSubdirectories only widens delivery; it must not suppress the
	// observer's own directory. Cheap, and it is the half of that flag the
	// synchronous seam can actually reach.
	NSURL* url = TempDirectory();

	__block NSUInteger count = 0;
	id token = [FSEventsManager.sharedInstance addObserverToDirectoryAtURL:url observeSubdirectories:YES usingBlock:^(NSURL*){
		++count;
	}];

	[FSEventsManager.sharedInstance reloadDirectoryAtURL:url];
	OAK_ASSERT_EQ(count, 1);

	[FSEventsManager.sharedInstance removeObserver:token];
}

void test_two_observers_on_one_directory_both_fire ()
{
	NSURL* url = TempDirectory();

	__block NSUInteger first = 0, second = 0;
	id a = [FSEventsManager.sharedInstance addObserverToDirectoryAtURL:url usingBlock:^(NSURL*){ ++first;  }];
	id b = [FSEventsManager.sharedInstance addObserverToDirectoryAtURL:url usingBlock:^(NSURL*){ ++second; }];
	OAK_ASSERT(a != b);

	[FSEventsManager.sharedInstance reloadDirectoryAtURL:url];
	OAK_ASSERT_EQ(first, 1);
	OAK_ASSERT_EQ(second, 1);

	// Removing one leaves the other delivering — the directory outlives the
	// client that went away, because a second client still holds it.
	[FSEventsManager.sharedInstance removeObserver:a];
	[FSEventsManager.sharedInstance reloadDirectoryAtURL:url];
	OAK_ASSERT_EQ(first, 1);
	OAK_ASSERT_EQ(second, 2);

	[FSEventsManager.sharedInstance removeObserver:b];
}

void test_removing_the_last_observer_stops_delivery ()
{
	NSURL* url = TempDirectory();

	__block NSUInteger count = 0;
	id token = [FSEventsManager.sharedInstance addObserverToDirectoryAtURL:url usingBlock:^(NSURL*){ ++count; }];

	[FSEventsManager.sharedInstance reloadDirectoryAtURL:url];
	OAK_ASSERT_EQ(count, 1);

	[FSEventsManager.sharedInstance removeObserver:token];
	[FSEventsManager.sharedInstance reloadDirectoryAtURL:url];
	OAK_ASSERT_EQ(count, 1);
}

void test_reloading_an_unobserved_directory_is_a_no_op ()
{
	// -reloadDirectoryAtURL: on a URL nobody watches sends to nil. Pinned because
	// the Swift translation of `[[_directories objectForKey:url] …]` is an
	// optional chain, and getting that wrong is a crash rather than a silence.
	[FSEventsManager.sharedInstance reloadDirectoryAtURL:TempDirectory()];
	OAK_ASSERT(true);
}
