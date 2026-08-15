#import "../src/FileBrowserDiskOperations.h"
#import "../src/FileBrowserDiskOperationsSupport.h"

// FileBrowserDiskOperations is Swift implementing an ObjC category, so nothing
// checks the implementation against FileBrowserDiskOperations.h at build time —
// and unlike the view ports, what this file gets wrong would corrupt files
// rather than draw the wrong pixels. So these go past constructibility and run
// the operations against a real temporary directory.
//
// What is deliberately not here: FBOperationTrash (a test must not put anything
// in the user's Trash), and any failing operation, because the failure path ends
// in -presentError:, which wants a window. The alert-driven replace/stop/skip
// branches are modal by nature and are verified in the running app.

static NSURL* CreateTemporaryDirectory ()
{
	NSURL* url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"t_file_browser_disk_operations.%d.%p", getpid(), (void*)[NSDate date]]] isDirectory:YES];
	[NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
	return url;
}

static void RemoveDirectory (NSURL* url)
{
	[NSFileManager.defaultManager removeItemAtURL:url error:nil];
}

void setup ()
{
	NSApplicationLoad();
}

// ===========================================================
// = The C++ that stayed behind (FileBrowserDiskOperations-   =
// = Support): path::relative_to / path::device / is_child    =
// ===========================================================

void test_symbolic_link_destination_is_relative_within_one_device ()
{
	NSURL* dir = CreateTemporaryDirectory();

	// Both the source and the link's directory have to exist: the same-device
	// test is a stat() of each, and path::device answers -1 for a path that is
	// not there. In the browser both always exist — you link an item you can see
	// into a folder you are looking at.
	NSURL* srcURL  = [dir URLByAppendingPathComponent:@"target.txt"];
	NSURL* destURL = [dir URLByAppendingPathComponent:@"link.txt"];
	[@"content" writeToURL:srcURL atomically:YES encoding:NSUTF8StringEncoding error:nil];

	// Same device, so the link is relative to the link's own directory — which
	// is what lets a folder be moved without breaking the links inside it.
	NSString* target = [FileBrowserDiskOperationsSupport symbolicLinkDestinationForURL:srcURL atURL:destURL];
	OAK_ASSERT(target != nil);
	OAK_ASSERT([target isEqualToString:@"target.txt"]);

	NSURL* subdirURL = [dir URLByAppendingPathComponent:@"sub" isDirectory:YES];
	[NSFileManager.defaultManager createDirectoryAtURL:subdirURL withIntermediateDirectories:YES attributes:nil error:nil];

	NSURL* nestedDestURL = [subdirURL URLByAppendingPathComponent:@"link.txt"];
	NSString* nestedTarget = [FileBrowserDiskOperationsSupport symbolicLinkDestinationForURL:srcURL atURL:nestedDestURL];
	OAK_ASSERT([nestedTarget isEqualToString:@"../target.txt"]);

	RemoveDirectory(dir);
}

void test_is_url_child_of_url ()
{
	NSURL* dir = CreateTemporaryDirectory();

	OAK_ASSERT([FileBrowserDiskOperationsSupport isURL:[dir URLByAppendingPathComponent:@"inside"] childOfURL:dir]);
	OAK_ASSERT(![FileBrowserDiskOperationsSupport isURL:dir childOfURL:[dir URLByAppendingPathComponent:@"inside"]]);

	RemoveDirectory(dir);
}

// ==========================================
// = The operations, against a real folder  =
// ==========================================

void test_perform_operation_creates_a_new_file ()
{
	FileBrowserViewController* controller = [FileBrowserViewController new];
	NSURL* dir = CreateTemporaryDirectory();

	NSURL* newFileURL = [dir URLByAppendingPathComponent:@"untitled.txt"];
	NSArray<NSURL*>* res = [controller performOperation:FBOperationNewFile sourceURLs:nil destinationURLs:@[ newFileURL ] unique:NO select:NO];

	OAK_ASSERT_EQ(res.count, 1);
	OAK_ASSERT([NSFileManager.defaultManager fileExistsAtPath:newFileURL.path]);

	RemoveDirectory(dir);
}

void test_perform_operation_creates_a_new_folder ()
{
	FileBrowserViewController* controller = [FileBrowserViewController new];
	NSURL* dir = CreateTemporaryDirectory();

	NSURL* newFolderURL = [dir URLByAppendingPathComponent:@"untitled folder" isDirectory:YES];
	NSArray<NSURL*>* res = [controller performOperation:FBOperationNewFolder sourceURLs:nil destinationURLs:@[ newFolderURL ] unique:NO select:NO];

	OAK_ASSERT_EQ(res.count, 1);

	BOOL isDirectory = NO;
	OAK_ASSERT([NSFileManager.defaultManager fileExistsAtPath:newFolderURL.path isDirectory:&isDirectory]);
	OAK_ASSERT(isDirectory);

	RemoveDirectory(dir);
}

// The unique: flag is what makes "New File" twice in a row give "untitled 2",
// and it is the one piece of non-trivial string work in the port (a regex that
// has to keep the extension on the end).
void test_unique_destination_urls_number_a_taken_name ()
{
	FileBrowserViewController* controller = [FileBrowserViewController new];
	NSURL* dir = CreateTemporaryDirectory();

	NSURL* newFileURL = [dir URLByAppendingPathComponent:@"untitled.txt"];

	NSArray<NSURL*>* first = [controller performOperation:FBOperationNewFile sourceURLs:nil destinationURLs:@[ newFileURL ] unique:YES select:NO];
	OAK_ASSERT([first.firstObject.lastPathComponent isEqualToString:@"untitled.txt"]);

	NSArray<NSURL*>* second = [controller performOperation:FBOperationNewFile sourceURLs:nil destinationURLs:@[ newFileURL ] unique:YES select:NO];
	OAK_ASSERT([second.firstObject.lastPathComponent isEqualToString:@"untitled 2.txt"]);

	NSArray<NSURL*>* third = [controller performOperation:FBOperationNewFile sourceURLs:nil destinationURLs:@[ newFileURL ] unique:YES select:NO];
	OAK_ASSERT([third.firstObject.lastPathComponent isEqualToString:@"untitled 3.txt"]);

	// Two of the same name in one operation are uniqued against each other, not
	// just against the disk.
	NSURL* pairURL = [dir URLByAppendingPathComponent:@"pair.txt"];
	NSArray<NSURL*>* pair = [controller performOperation:FBOperationNewFile sourceURLs:nil destinationURLs:@[ pairURL, pairURL ] unique:YES select:NO];
	OAK_ASSERT_EQ(pair.count, 2);
	OAK_ASSERT([pair[0].lastPathComponent isEqualToString:@"pair.txt"]);
	OAK_ASSERT([pair[1].lastPathComponent isEqualToString:@"pair 2.txt"]);

	RemoveDirectory(dir);
}

void test_perform_operation_renames_a_file ()
{
	FileBrowserViewController* controller = [FileBrowserViewController new];
	NSURL* dir = CreateTemporaryDirectory();

	NSURL* srcURL  = [dir URLByAppendingPathComponent:@"before.txt"];
	NSURL* destURL = [dir URLByAppendingPathComponent:@"after.txt"];
	[@"content" writeToURL:srcURL atomically:YES encoding:NSUTF8StringEncoding error:nil];

	NSArray<NSURL*>* res = [controller performOperation:FBOperationRename withURLs:@{ srcURL: destURL } unique:NO select:NO];

	OAK_ASSERT_EQ(res.count, 1);
	OAK_ASSERT(![NSFileManager.defaultManager fileExistsAtPath:srcURL.path]);
	OAK_ASSERT([NSFileManager.defaultManager fileExistsAtPath:destURL.path]);

	RemoveDirectory(dir);
}

void test_perform_operation_copies_a_file ()
{
	FileBrowserViewController* controller = [FileBrowserViewController new];
	NSURL* dir = CreateTemporaryDirectory();

	NSURL* srcURL  = [dir URLByAppendingPathComponent:@"source.txt"];
	NSURL* destURL = [dir URLByAppendingPathComponent:@"copy.txt"];
	[@"content" writeToURL:srcURL atomically:YES encoding:NSUTF8StringEncoding error:nil];

	NSArray<NSURL*>* res = [controller performOperation:FBOperationCopy withURLs:@{ srcURL: destURL } unique:NO select:NO];

	OAK_ASSERT_EQ(res.count, 1);
	OAK_ASSERT([NSFileManager.defaultManager fileExistsAtPath:srcURL.path]);
	OAK_ASSERT([[NSString stringWithContentsOfURL:destURL encoding:NSUTF8StringEncoding error:nil] isEqualToString:@"content"]);

	RemoveDirectory(dir);
}

// The link case is the one that reaches the C++ above from the operation side.
void test_perform_operation_creates_a_relative_symbolic_link ()
{
	FileBrowserViewController* controller = [FileBrowserViewController new];
	NSURL* dir = CreateTemporaryDirectory();

	NSURL* srcURL  = [dir URLByAppendingPathComponent:@"target.txt"];
	NSURL* destURL = [dir URLByAppendingPathComponent:@"link.txt"];
	[@"content" writeToURL:srcURL atomically:YES encoding:NSUTF8StringEncoding error:nil];

	NSArray<NSURL*>* res = [controller performOperation:FBOperationLink withURLs:@{ srcURL: destURL } unique:NO select:NO];

	OAK_ASSERT_EQ(res.count, 1);
	NSString* destination = [NSFileManager.defaultManager destinationOfSymbolicLinkAtPath:destURL.path error:nil];
	OAK_ASSERT([destination isEqualToString:@"target.txt"]);

	RemoveDirectory(dir);
}
