#import "../src/OakDocumentController.h"
#import "../src/OakDocument Private.h"
#import <Cocoa/Cocoa.h>
#import <sys/stat.h>

// Pins for OakDocumentController — the document registry, the untitled-count
// reservation, the last-recently-used ranks, and the directory walk that Find
// in Folder and the file chooser enumerate through — written against the
// ObjC++ and before any port of it (rule 18, rule 40).
//
// It had no test. Its C++ is two coherent pieces: the registry (three maps
// keyed by UUID, path and inode, under a mutex) and the walk (a glob list over
// path::entries with a deque of directories and a set of inodes seen). The
// port extracts each behind an ObjC face first, and these pins are what judge
// the extraction: identity through the registry, order and exclusion through
// the walk.
//
// The controller is a process-wide singleton and OakDocument registers itself
// with it, so every test creates its documents inside an autorelease pool and
// lets them go before the next — this bundle compiles with ARC off (rule 60),
// so a +0 document lives exactly as long as its pool.
//
// Not pinned: -showDocument:… — its implementation is a category in
// DocumentWindow, which this bundle does not link.

void setup ()
{
	NSApplicationLoad();
}

static int JailCounter = 0;

// A fresh directory per call.
static NSString* Jail ()
{
	NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"tm-document-controller-%d-%d", getpid(), ++JailCounter]];
	[NSFileManager.defaultManager removeItemAtPath:dir error:nil];
	[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return dir;
}

static NSString* WriteFile (NSString* dir, NSString* relative, NSString* content = @"x\n")
{
	NSString* path = [dir stringByAppendingPathComponent:relative];
	[NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
	[content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
	return path;
}

static NSString* Names (NSArray<NSString*>* paths)
{
	NSMutableArray* names = [NSMutableArray array];
	for(NSString* path in paths)
		[names addObject:path.lastPathComponent];
	return [names componentsJoinedByString:@","];
}

static NSArray<NSString*>* Enumerate (NSArray* items, NSDictionary* options, NSUInteger stopAfter = NSNotFound)
{
	NSMutableArray<NSString*>* res = [NSMutableArray array];
	[OakDocumentController.sharedInstance enumerateDocumentsAtPaths:items options:options usingBlock:^(OakDocument* document, BOOL* stop){
		[res addObject:document.path ?: document.displayName];
		if(res.count == stopAfter)
			*stop = YES;
	}];
	return res;
}

// MARK: - Selector surface (rule 18)

void test_document_controller_answers_its_public_selectors ()
{
	OAK_ASSERT([OakDocumentController respondsToSelector:@selector(sharedInstance)]);

	NSArray<NSString*>* const required = @[
		@"untitledDocument",
		@"documentWithPath:",
		@"findDocumentWithIdentifier:",
		@"documents",
		@"openDocuments",
		@"lruRankForDocument:",
		@"didTouchDocument:",
		@"enumerateDocumentsAtPath:options:usingBlock:",
		@"enumerateDocumentsAtPaths:options:usingBlock:",
		@"register:",
		@"unregister:",
		@"update:",
		@"firstAvailableUntitledCount",
		@"showDocument:",
		@"showDocument:inProject:bringToFront:",
	];

	NSMutableArray* missing = [NSMutableArray array];
	for(NSString* name in required)
	{
		if(![OakDocumentController instancesRespondToSelector:NSSelectorFromString(name)])
			[missing addObject:name];
	}
	OAK_ASSERT_EQ(std::string([missing componentsJoinedByString:@", "].UTF8String), std::string(""));
}

// The option keys are strings other frameworks build dictionaries with
// (FileChooserSupport maps settings onto them); the spellings are the contract.
void test_search_option_keys ()
{
	OAK_ASSERT_EQ(std::string(kSearchFollowDirectoryLinksKey.UTF8String),  std::string("FollowDirectoryLinks"));
	OAK_ASSERT_EQ(std::string(kSearchFollowFileLinksKey.UTF8String),       std::string("FollowFileLinks"));
	OAK_ASSERT_EQ(std::string(kSearchDepthFirstSearchKey.UTF8String),      std::string("DepthFirstSearch"));
	OAK_ASSERT_EQ(std::string(kSearchIgnoreOrderingKey.UTF8String),        std::string("IgnoreOrdering"));
	OAK_ASSERT_EQ(std::string(kSearchExcludeDirectoryGlobsKey.UTF8String), std::string("ExcludeDirectoryGlobs"));
	OAK_ASSERT_EQ(std::string(kSearchExcludeFileGlobsKey.UTF8String),      std::string("ExcludeFileGlobs"));
	OAK_ASSERT_EQ(std::string(kSearchExcludeGlobsKey.UTF8String),          std::string("ExcludeGlobs"));
	OAK_ASSERT_EQ(std::string(kSearchDirectoryGlobsKey.UTF8String),        std::string("DirectoryGlobs"));
	OAK_ASSERT_EQ(std::string(kSearchFileGlobsKey.UTF8String),             std::string("FileGlobs"));
	OAK_ASSERT_EQ(std::string(kSearchGlobsKey.UTF8String),                 std::string("Globs"));
}

// MARK: - The registry

// One document per path while it lives, found by path and by identifier.
void test_a_path_yields_one_document_while_it_lives ()
{
	@autoreleasepool {
		NSString* dir = Jail();
		NSString* a = WriteFile(dir, @"a.txt");
		NSString* b = WriteFile(dir, @"b.txt");

		OakDocument* docA  = [OakDocumentController.sharedInstance documentWithPath:a];
		OakDocument* docA2 = [OakDocumentController.sharedInstance documentWithPath:a];
		OakDocument* docB  = [OakDocumentController.sharedInstance documentWithPath:b];

		OAK_ASSERT(docA == docA2);
		OAK_ASSERT(docA != docB);
		OAK_ASSERT([OakDocumentController.sharedInstance findDocumentWithIdentifier:docA.identifier] == docA);
		OAK_ASSERT([OakDocumentController.sharedInstance findDocumentWithIdentifier:docB.identifier] == docB);
		OAK_ASSERT([OakDocumentController.sharedInstance findDocumentWithIdentifier:[NSUUID UUID]] == nil);
		OAK_ASSERT([[OakDocumentController.sharedInstance documents] containsObject:docA]);
	}
}

// The registry holds documents weakly: once nothing else does, the identifier
// no longer resolves and the path yields a new object.
void test_a_released_document_leaves_the_registry ()
{
	NSString* dir = Jail();
	NSString* a = WriteFile(dir, @"a.txt");

	NSUUID* identifier = nil;
	@autoreleasepool {
		OakDocument* doc = [OakDocumentController.sharedInstance documentWithPath:a];
		identifier = [doc.identifier copy];
	}
	OAK_ASSERT([OakDocumentController.sharedInstance findDocumentWithIdentifier:identifier] == nil);

	@autoreleasepool {
		OakDocument* again = [OakDocumentController.sharedInstance documentWithPath:a];
		OAK_ASSERT(![again.identifier isEqual:identifier]);
	}
	[identifier release];
}

// The same file reached through a hard link is the same document — that is
// what the inode map is for.
void test_a_hard_link_to_an_open_file_yields_the_same_document ()
{
	@autoreleasepool {
		NSString* dir  = Jail();
		NSString* a    = WriteFile(dir, @"a.txt");
		NSString* link = [dir stringByAppendingPathComponent:@"same-inode.txt"];
		OAK_ASSERT(::link(a.fileSystemRepresentation, link.fileSystemRepresentation) == 0);

		OakDocument* docA    = [OakDocumentController.sharedInstance documentWithPath:a];
		OakDocument* docLink = [OakDocumentController.sharedInstance documentWithPath:link];
		OAK_ASSERT(docA == docLink);
	}
}

// A document whose path changes is re-registered under the new one.
void test_a_document_follows_its_path_change ()
{
	@autoreleasepool {
		NSString* dir = Jail();
		NSString* a = WriteFile(dir, @"a.txt");
		NSString* b = WriteFile(dir, @"b.txt");

		OakDocument* doc = [OakDocumentController.sharedInstance documentWithPath:a];
		doc.path = b;
		OAK_ASSERT([OakDocumentController.sharedInstance documentWithPath:b] == doc);
		OAK_ASSERT([OakDocumentController.sharedInstance documentWithPath:a] != doc);
	}
}

// MARK: - Untitled counts

// Untitled documents take the lowest free number, and a number is free again
// once its document is gone: "untitled", "untitled 2", then "untitled" again.
void test_untitled_numbers_are_the_lowest_free_and_are_reused ()
{
	@autoreleasepool {
		OakDocument* first  = [OakDocumentController.sharedInstance untitledDocument];
		OAK_ASSERT_EQ(std::string(first.displayName.UTF8String), std::string("untitled"));
		OAK_ASSERT_EQ((size_t)first.untitledCount, (size_t)1);

		OakDocument* second = [OakDocumentController.sharedInstance untitledDocument];
		OAK_ASSERT_EQ(std::string(second.displayName.UTF8String), std::string("untitled 2"));
		OAK_ASSERT_EQ((size_t)[OakDocumentController.sharedInstance firstAvailableUntitledCount], (size_t)3);
	}
	@autoreleasepool {
		OAK_ASSERT_EQ((size_t)[OakDocumentController.sharedInstance firstAvailableUntitledCount], (size_t)1);
		OakDocument* third = [OakDocumentController.sharedInstance untitledDocument];
		OAK_ASSERT_EQ(std::string(third.displayName.UTF8String), std::string("untitled"));
	}
}

// MARK: - Open documents

// -openDocuments lists what is open: untitled ones first, by number, then
// paths in localized order.
void test_open_documents_are_untitled_first_then_paths_in_order ()
{
	@autoreleasepool {
		NSString* dir = Jail();
		NSString* beta  = WriteFile(dir, @"beta.txt");
		NSString* alpha = WriteFile(dir, @"alpha.txt");

		OakDocument* docBeta     = [OakDocumentController.sharedInstance documentWithPath:beta];
		OakDocument* docAlpha    = [OakDocumentController.sharedInstance documentWithPath:alpha];
		OakDocument* untitled    = [OakDocumentController.sharedInstance untitledDocument];
		OakDocument* notOpened   = [OakDocumentController.sharedInstance documentWithPath:WriteFile(dir, @"closed.txt")];
		(void)notOpened;

		[docBeta open];
		[docAlpha open];
		[untitled open];

		NSArray<OakDocument*>* open = [OakDocumentController.sharedInstance openDocuments];
		OAK_ASSERT_EQ((size_t)open.count, (size_t)3);
		OAK_ASSERT(open[0] == untitled);
		OAK_ASSERT(open[1] == docAlpha);
		OAK_ASSERT(open[2] == docBeta);

		[docBeta close];
		[docAlpha close];
		[untitled close];
		OAK_ASSERT_EQ((size_t)[OakDocumentController.sharedInstance openDocuments].count, (size_t)0);
	}
}

// MARK: - Last recently used

// Touching a document gives it a higher rank than anything touched before;
// an untouched one ranks zero. Untitled documents rank by identifier.
void test_touching_documents_ranks_them_in_touch_order ()
{
	@autoreleasepool {
		NSString* dir = Jail();
		OakDocument* a = [OakDocumentController.sharedInstance documentWithPath:WriteFile(dir, @"a.txt")];
		OakDocument* b = [OakDocumentController.sharedInstance documentWithPath:WriteFile(dir, @"b.txt")];
		OakDocument* c = [OakDocumentController.sharedInstance documentWithPath:WriteFile(dir, @"c.txt")];
		OakDocument* untitled = [OakDocumentController.sharedInstance untitledDocument];

		OAK_ASSERT([OakDocumentController.sharedInstance lruRankForDocument:c] == 0);

		[OakDocumentController.sharedInstance didTouchDocument:a];
		[OakDocumentController.sharedInstance didTouchDocument:b];
		[OakDocumentController.sharedInstance didTouchDocument:untitled];
		[OakDocumentController.sharedInstance didTouchDocument:nil]; // harmless

		NSInteger rankA = [OakDocumentController.sharedInstance lruRankForDocument:a];
		NSInteger rankB = [OakDocumentController.sharedInstance lruRankForDocument:b];
		NSInteger rankU = [OakDocumentController.sharedInstance lruRankForDocument:untitled];
		OAK_ASSERT(rankA > 0);
		OAK_ASSERT(rankB > rankA);
		OAK_ASSERT(rankU > rankB);
		OAK_ASSERT([OakDocumentController.sharedInstance lruRankForDocument:c] == 0);

		[OakDocumentController.sharedInstance didTouchDocument:a];
		OAK_ASSERT([OakDocumentController.sharedInstance lruRankForDocument:a] > rankU);
	}
}

// MARK: - The directory walk

// The tree every walk test uses:
//
//   root/b.txt, root/a.txt          two files, listed case-insensitively
//   root/sub1/c.txt                 a subdirectory
//   root/sub1/deep/d.txt            a subdirectory of that
//   root/sub2/e.txt                 a second subdirectory
//   root/build/skip.txt             a directory to exclude by name
//   root/notes.log                  a file to exclude by glob
//   root/linked -> elsewhere/       a symlink to a directory outside the tree
//   root/f.txt -> elsewhere/f.txt   a symlink to a file outside the tree
// `elsewhere` is a sibling of `root` under one jail, named to sort after it:
// a followed link is reported in whichever directory's batch is current, and
// batches sort by full path, so the fixture decides that order rather than
// leaving it to temp-directory numbering.
static NSString* WalkTree (NSString** elsewhereOut = nullptr)
{
	NSString* jail = Jail();
	NSString* root = [jail stringByAppendingPathComponent:@"root"];
	NSString* elsewhere = [jail stringByAppendingPathComponent:@"zz-elsewhere"];
	WriteFile(root, @"b.txt");
	WriteFile(root, @"a.txt");
	WriteFile(root, @"sub1/c.txt");
	WriteFile(root, @"sub1/deep/d.txt");
	WriteFile(root, @"sub2/e.txt");
	WriteFile(root, @"build/skip.txt");
	WriteFile(root, @"notes.log");
	WriteFile(elsewhere, @"g.txt");
	WriteFile(elsewhere, @"f.txt");
	[NSFileManager.defaultManager createSymbolicLinkAtPath:[root stringByAppendingPathComponent:@"linked"] withDestinationPath:elsewhere error:nil];
	[NSFileManager.defaultManager createSymbolicLinkAtPath:[root stringByAppendingPathComponent:@"f.txt"] withDestinationPath:[elsewhere stringByAppendingPathComponent:@"f.txt"] error:nil];
	if(elsewhereOut)
		*elsewhereOut = elsewhere;
	return root;
}

// Breadth first by default: a directory's files, sorted, then each
// subdirectory in turn. Links are resolved only once every directory has been
// walked, so a followed file link comes last; directory links are not followed
// unless asked.
void test_walk_is_breadth_first_and_sorted ()
{
	@autoreleasepool {
		NSString* root = WalkTree();
		NSArray* found = Enumerate(@[ root ], @{});
		OAK_ASSERT_EQ(std::string(Names(found).UTF8String), std::string("a.txt,b.txt,notes.log,skip.txt,c.txt,e.txt,d.txt,f.txt"));
	}
}

void test_walk_can_be_depth_first ()
{
	@autoreleasepool {
		NSString* root = WalkTree();
		NSArray* found = Enumerate(@[ root ], @{ kSearchDepthFirstSearchKey: @YES });
		OAK_ASSERT_EQ(std::string(Names(found).UTF8String), std::string("a.txt,b.txt,notes.log,skip.txt,c.txt,d.txt,e.txt,f.txt"));
	}
}

// Exclusions are checked before inclusions, in the order the option keys are
// read, so an excluded name never reaches the "*" that would admit it.
void test_walk_excludes_directories_and_files_by_glob ()
{
	@autoreleasepool {
		NSString* root = WalkTree();
		NSArray* found = Enumerate(@[ root ], @{
			kSearchExcludeDirectoryGlobsKey: @[ @"build" ],
			kSearchExcludeFileGlobsKey:      @[ @"*.log" ],
			kSearchDirectoryGlobsKey:        @[ @"*" ],
			kSearchFileGlobsKey:             @[ @"*" ],
		});
		OAK_ASSERT_EQ(std::string(Names(found).UTF8String), std::string("a.txt,b.txt,c.txt,e.txt,d.txt,f.txt"));
	}
}

// Once any glob is given, a path that matches none of them is excluded — so a
// list of exclusions alone matches nothing at all. Every consumer (Find's
// FFGlobOptionsForPath, the file chooser) also passes an include glob, and a
// port that "fixed" this would change what every one of them searches.
void test_exclusions_alone_match_nothing ()
{
	@autoreleasepool {
		NSString* root = WalkTree();
		NSArray* found = Enumerate(@[ root ], @{ kSearchExcludeFileGlobsKey: @[ @"*.log" ] });
		OAK_ASSERT_EQ((size_t)found.count, (size_t)0);
	}
}

void test_walk_follows_directory_links_only_when_asked ()
{
	@autoreleasepool {
		NSString* root = WalkTree();
		NSArray* found = Enumerate(@[ root ], @{ kSearchFollowDirectoryLinksKey: @YES });
		OAK_ASSERT([Names(found) containsString:@"g.txt"]);
	}
}

void test_walk_can_leave_file_links_alone ()
{
	@autoreleasepool {
		NSString* root = WalkTree();
		NSArray* found = Enumerate(@[ root ], @{ kSearchFollowFileLinksKey: @NO });
		OAK_ASSERT(![Names(found) containsString:@"f.txt"]);
		OAK_ASSERT([Names(found) containsString:@"a.txt"]);
	}
}

// A file named directly is reported once, and a file reached twice — by name
// and again inside its directory — only once.
void test_walk_reports_a_named_file_once ()
{
	@autoreleasepool {
		NSString* root = WalkTree();
		NSArray* found = Enumerate(@[ [root stringByAppendingPathComponent:@"a.txt"], root ], @{});
		NSString* names = Names(found);
		OAK_ASSERT([names hasPrefix:@"a.txt,"]);
		OAK_ASSERT_EQ((size_t)[[names componentsSeparatedByString:@"a.txt"] count], (size_t)2);
	}
}

void test_walk_stops_when_asked ()
{
	@autoreleasepool {
		NSString* root = WalkTree();
		NSArray* found = Enumerate(@[ root ], @{}, 2);
		OAK_ASSERT_EQ(std::string(Names(found).UTF8String), std::string("a.txt,b.txt"));
	}
}

// An untitled document whose directory is the one being walked is reported
// first — that is how a search over a project folder includes the buffer you
// have not saved yet.
void test_walk_reports_untitled_documents_in_the_directory_first ()
{
	@autoreleasepool {
		NSString* root = WalkTree();
		OakDocument* untitled = [OakDocumentController.sharedInstance untitledDocument];
		untitled.directory = root;
		[untitled open];

		NSArray* found = Enumerate(@[ root ], @{});
		OAK_ASSERT([found.firstObject isEqualToString:untitled.displayName]);
		OAK_ASSERT_EQ((size_t)found.count, (size_t)9);

		[untitled close];
	}
}
