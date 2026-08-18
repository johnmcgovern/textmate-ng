#import "../src/SoftwareUpdate.h"

// Regression test for the alpha.13 crash: "Settings ▸ Software Update crashes".
//
// -checkForTestBuild:completionHandler: took an early return, synchronously, on
// the caller's queue when no update channel was configured. Called from
// NSBackgroundActivityScheduler's XPC queue that set `errorString` off the main
// thread; the KVO notification reached a @MainActor Swift getter through Cocoa
// Bindings, and Swift 6's executor check trapped the process.
//
// What this pins is the queue contract, not the binding: the completion handler
// is called on the main thread however the method was entered. That is the
// property the whole failure hinged on, and it is checkable without a
// preferences window, an observer, or a network round trip — the no-channel
// early return is exactly the path that crashed.
//
// Deliberately not asserted here: that a KVO notification for `checking` /
// `errorString` arrives on the main thread. It follows from this, and testing it
// directly would mean standing up the Swift pane and its bindings inside a test
// bundle that does not link it.

static void SpinRunLoopUntil (BOOL (^condition)(), NSTimeInterval timeout)
{
	NSDate* giveUp = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while(!condition() && [giveUp timeIntervalSinceNow] > 0)
		[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

void setup ()
{
	NSApplicationLoad();
}

void test_check_calls_back_on_the_main_thread_when_entered_from_a_background_queue ()
{
	// No channel configured is the first early return, and the one the crashing
	// machine actually took. Removing the key leaves the default suite as the
	// reporter's was; it is restored below.
	NSString* const key = @"SoftwareUpdateChannel";
	id saved = [NSUserDefaults.standardUserDefaults objectForKey:key];
	[NSUserDefaults.standardUserDefaults removeObjectForKey:key];

	__block BOOL called = NO;
	__block BOOL onMainThread = NO;
	__block NSError* reportedError = nil;

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		[SoftwareUpdate.sharedInstance checkForTestBuild:NO completionHandler:^(NSURL* remoteURL, NSString* remoteVersion, NSError* error){
			onMainThread  = NSThread.isMainThread;
			reportedError = error;
			called        = YES;
		}];
	});

	SpinRunLoopUntil(^{ return called; }, 5.0);

	if(saved)
		[NSUserDefaults.standardUserDefaults setObject:saved forKey:key];

	OAK_ASSERT(called);
	OAK_ASSERT(onMainThread);      // this is the assertion the crash was
	OAK_ASSERT(reportedError != nil);
}

void test_check_still_calls_back_when_entered_from_the_main_thread ()
{
	// The hop must not swallow the synchronous path menu actions use.
	NSString* const key = @"SoftwareUpdateChannel";
	id saved = [NSUserDefaults.standardUserDefaults objectForKey:key];
	[NSUserDefaults.standardUserDefaults removeObjectForKey:key];

	__block BOOL called = NO;
	__block BOOL onMainThread = NO;

	[SoftwareUpdate.sharedInstance checkForTestBuild:NO completionHandler:^(NSURL* remoteURL, NSString* remoteVersion, NSError* error){
		onMainThread = NSThread.isMainThread;
		called       = YES;
	}];

	if(saved)
		[NSUserDefaults.standardUserDefaults setObject:saved forKey:key];

	// Still synchronous from the main thread — no run loop spin before this.
	OAK_ASSERT(called);
	OAK_ASSERT(onMainThread);
}
