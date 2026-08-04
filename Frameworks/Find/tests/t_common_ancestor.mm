#import "../src/CommonAncestor.h"

// CommonAncestor reduces the folder search's path list to the directory that
// results are displayed relative to (Find.mm:1137 hands it straight to
// -resultNodeWithMatch:baseDirectory:). It is the one piece of Find that is a
// pure function over strings — one filesystem touch at the very end — which
// makes it the piece that can be pinned exactly before the port.
//
// It is worth pinning precisely because of *how* it works: the scan is
// character-wise over the raw strings, not component-wise over path segments,
// with a running index of the last '/' seen. A Swift rewrite will reach for
// pathComponents and a common-prefix reduce, which is the obvious spelling and
// is not the same function. These tests are what tells the two apart.

static NSString* Ancestor (NSArray<NSString*>* paths)
{
	return CommonAncestor(paths);
}

// A directory that does not exist, so the trailing fileExistsAtPath: check is a
// no-op and these cases test the string scan alone.
static NSString* const kAbsent = @"/tm-find-tests-absent";

// =====================
// = The ordinary case =
// =====================

void test_common_ancestor_of_siblings ()
{
	NSString* res = Ancestor(@[ [kAbsent stringByAppendingString:@"/x/a.txt"], [kAbsent stringByAppendingString:@"/x/b.txt"] ]);
	OAK_ASSERT([res isEqualToString:[kAbsent stringByAppendingString:@"/x"]]);
}

void test_common_ancestor_of_different_branches ()
{
	NSString* res = Ancestor(@[ [kAbsent stringByAppendingString:@"/x/1"], [kAbsent stringByAppendingString:@"/y/2"] ]);
	OAK_ASSERT([res isEqualToString:kAbsent]);
}

void test_common_ancestor_of_three_paths ()
{
	NSString* res = Ancestor(@[
		[kAbsent stringByAppendingString:@"/x/deep/1"],
		[kAbsent stringByAppendingString:@"/x/deep/2"],
		[kAbsent stringByAppendingString:@"/x/other/3"],
	]);
	OAK_ASSERT([res isEqualToString:[kAbsent stringByAppendingString:@"/x"]]);
}

// Nothing in common below the root falls back to "/" rather than to the empty
// string — the caller passes the result on as a base directory, so "" would
// make every displayed path absolute.
void test_no_common_directory_falls_back_to_root ()
{
	NSString* res = Ancestor(@[ @"/aaa/1", @"/bbb/2" ]);
	OAK_ASSERT([res isEqualToString:@"/"]);
}

// The scan compares characters, so "/foo" and "/foobar" share a four-character
// prefix that is not a path boundary. The last-separator index is what keeps
// that from becoming an answer of "/foo".
void test_a_shared_string_prefix_is_not_a_shared_directory ()
{
	NSString* res = Ancestor(@[ @"/foo/bar", @"/foobar/baz" ]);
	OAK_ASSERT([res isEqualToString:@"/"]);
}

// ===============
// = Degenerate  =
// ===============

void test_a_single_path_is_returned_unchanged ()
{
	NSString* only = [kAbsent stringByAppendingString:@"/dir"];
	OAK_ASSERT([Ancestor(@[ only ]) isEqualToString:only]);
}

void test_an_empty_list_is_nil ()
{
	OAK_ASSERT(Ancestor(@[]) == nil);
}

// Identical paths never mismatch, so the answer comes from the last separator
// seen — the enclosing directory, not the path itself.
void test_duplicate_paths_yield_their_directory ()
{
	NSString* path = [kAbsent stringByAppendingString:@"/x/a.txt"];
	NSString* res  = Ancestor(@[ path, path ]);
	OAK_ASSERT([res isEqualToString:[kAbsent stringByAppendingString:@"/x"]]);
}

// ==============================================
// = A defect, recorded rather than endorsed    =
// ==============================================

// When one path is a prefix of another the loop runs to the shorter one's end
// without ever mismatching, so the answer is the last separator *within* that
// prefix — the grandparent, not the directory the two actually share. Searching
// a folder together with a file inside it produces exactly this pair.
//
// Pinned as current behaviour so the port reproduces it deliberately or changes
// it deliberately. Same treatment as TMFileReference's -absoluteURL
// normalisation: a behaviour change belongs in its own commit.
void test_a_path_prefixing_another_yields_the_grandparent ()
{
	NSString* res = Ancestor(@[ [kAbsent stringByAppendingString:@"/a/b"], [kAbsent stringByAppendingString:@"/a/b/c"] ]);
	OAK_ASSERT([res isEqualToString:[kAbsent stringByAppendingString:@"/a"]]);
}

// ==========================
// = The filesystem touch   =
// ==========================

static NSString* TempDirectory ()
{
	NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tm-find-common-ancestor"];
	[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return dir;
}

// The last step exists so that searching a single file shows results relative
// to its folder rather than to the file. It is a stat, so it only fires for
// paths that really exist.
void test_an_existing_file_yields_its_directory ()
{
	NSString* dir  = TempDirectory();
	NSString* file = [dir stringByAppendingPathComponent:@"only.txt"];
	[@"x" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];

	OAK_ASSERT([Ancestor(@[ file ]) isEqualToString:dir]);
}

void test_an_existing_directory_is_kept ()
{
	NSString* dir = TempDirectory();
	OAK_ASSERT([Ancestor(@[ dir ]) isEqualToString:dir]);
}
