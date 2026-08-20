#import "../src/SCMManager.h"

// Written against the ObjC++ SCMManager, before the Swift port, so these judge the
// original and not the translation (the DocumentWindowController lesson, rule 18).
//
// SCMManager is a block-observer registry, not a KVO object, so its whole public
// contract is selectors: -repositoryAtURL:, -addObserverToRepositoryAtURL:usingBlock:
// and -removeObserver: are called from FileBrowserViewController.swift and
// FileItemObserver.swift, and SCMRepository's read-only properties are walked by the
// ObjC++ FileItemObserverSupport. None of them is reached through a protocol, so a
// rename or a mis-imported Swift spelling in the port would be invisible to the
// compiler and to a green build — exactly the silently-dead-API failure rule 18 is
// for. The Swift class must keep every selector below.
//
// The manager is a singleton; the repository cache is a strongToWeakObjectsMapTable
// (the manager does not own repositories, their observers and directories do), which
// is why -repositoryAtURL: on a path outside any working copy walking up to the
// volume root and returning nil is a behaviour worth pinning rather than an
// implementation detail — rule 33: getting that optional/loop translation wrong is a
// crash, not a silence.

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

void test_scm_manager_keeps_its_selector_surface ()
{
	SEL const managerSelectors[] = {
		@selector(addObserverToRepositoryAtURL:usingBlock:),
		@selector(removeObserver:),
		@selector(repositoryAtURL:),
	};
	for(SEL selector : managerSelectors)
		OAK_ASSERT([SCMManager instancesRespondToSelector:selector]);

	OAK_ASSERT([SCMManager respondsToSelector:@selector(sharedInstance)]);
}

void test_scm_repository_keeps_its_selector_surface ()
{
	// The read-only surface FileItemObserverSupport and the browser consume. `enabled`
	// has no `getter=`, so the ObjC selector is -enabled, not -isEnabled — pinned so
	// the Swift `@objc var enabled` (which would otherwise import as -isEnabled) has to
	// carry an `@objc(enabled)`.
	SEL const repositorySelectors[] = {
		@selector(URL),
		@selector(enabled),
		@selector(tracksDirectories),
		@selector(hasStatus),
		@selector(status),
		@selector(variables),
	};
	for(SEL selector : repositorySelectors)
		OAK_ASSERT([SCMRepository instancesRespondToSelector:selector]);
}

void test_scm_manager_is_a_singleton ()
{
	OAK_ASSERT(SCMManager.sharedInstance != nil);
	OAK_ASSERT(SCMManager.sharedInstance == SCMManager.sharedInstance);
}

void test_repository_at_url_outside_a_working_copy_is_nil ()
{
	// A fresh temp directory is not inside a repository, so the walk up the parent
	// chain finds no driver and stops at the volume root, returning nil. This is the
	// whole while-loop in -repositoryAtURL: (rule 33: the nil return and the parent
	// walk are the part a literal Swift translation is most likely to turn into a
	// crash or an infinite loop).
	OAK_ASSERT([SCMManager.sharedInstance repositoryAtURL:TempDirectory()] == nil);
}
