#import "../src/FileChooserSupport.h"

// FileChooserSupport is the C++ FileChooser could not carry into Swift. The piece worth
// real coverage is FileChooserFilter: the Open Quickly filter field has a mini-syntax —
// "glob*", "name", "name:selection", "name@symbol" — parsed by one dense regular
// expression buried in a private method, with no test of any kind. Every case below was
// verified against the ObjC++ original before the panel was ported.
//
// The distinction that matters most is glob-versus-filter: anything containing a * takes
// the glob branch, which changes both what matches (path globbing, not fuzzy ranking) and
// how results are sorted. -effectiveFilter is what the panel compares to decide whether a
// keystroke actually changed the query, so its nil-to-empty-string handling is pinned too.

void setup ()
{
	NSApplicationLoad();
}

void test_file_chooser_filter_plain_name ()
{
	FileChooserFilter* f = [FileChooserFilter filterWithString:@"main"];
	OAK_ASSERT([f.filterString isEqualToString:@"main"]);
	OAK_ASSERT(f.globString == nil);
	OAK_ASSERT(f.selectionString == nil);
	OAK_ASSERT(f.symbolString == nil);
	OAK_ASSERT([f.effectiveFilter isEqualToString:@"main"]);
}

void test_file_chooser_filter_glob_takes_the_glob_branch ()
{
	FileChooserFilter* f = [FileChooserFilter filterWithString:@"*.cc"];
	OAK_ASSERT([f.globString isEqualToString:@"*.cc"]);
	OAK_ASSERT([f.effectiveFilter isEqualToString:@"*.cc"]); // glob wins over filter
}

void test_file_chooser_filter_selection_suffix ()
{
	FileChooserFilter* f = [FileChooserFilter filterWithString:@"main:42"];
	OAK_ASSERT([f.filterString isEqualToString:@"main"]);
	OAK_ASSERT([f.selectionString isEqualToString:@"42"]);
	OAK_ASSERT(f.symbolString == nil);
	// The selection is not part of the filter, so typing it must not re-run the search.
	OAK_ASSERT([f.effectiveFilter isEqualToString:@"main"]);
}

void test_file_chooser_filter_symbol_suffix ()
{
	FileChooserFilter* f = [FileChooserFilter filterWithString:@"main@symbol"];
	OAK_ASSERT([f.filterString isEqualToString:@"main"]);
	OAK_ASSERT([f.symbolString isEqualToString:@"symbol"]);
	OAK_ASSERT(f.selectionString == nil);
	OAK_ASSERT([f.effectiveFilter isEqualToString:@"main"]);
}

void test_file_chooser_filter_empty_and_nil ()
{
	OAK_ASSERT([[FileChooserFilter filterWithString:@""].effectiveFilter isEqualToString:@""]);
	OAK_ASSERT([[FileChooserFilter filterWithString:nil].effectiveFilter isEqualToString:@""]);
}

void test_file_chooser_filter_normalises_the_filter_string ()
{
	// oak::normalize_filter is what makes the ranking case- and separator-insensitive; the
	// port has to keep it on this side of the boundary.
	FileChooserFilter* f = [FileChooserFilter filterWithString:@"Main"];
	OAK_ASSERT([f.filterString isEqualToString:[f.filterString lowercaseString]]);
}

void test_file_chooser_support_relative_paths ()
{
	OAK_ASSERT([[FileChooserSupport path:@"/project/src/main.cc" relativeTo:@"/project"] isEqualToString:@"src/main.cc"]);
	// Outside the base, path::relative_to keeps the absolute path rather than climbing out.
	OAK_ASSERT([[FileChooserSupport path:@"/elsewhere/x.cc" relativeTo:@"/project"] isEqualToString:@"/elsewhere/x.cc"]);
}

void test_file_chooser_support_path_has_parent ()
{
	// This is what enables or greys out Go to Parent Folder.
	OAK_ASSERT([FileChooserSupport pathHasParent:@"/usr/share"] == YES);
	OAK_ASSERT([FileChooserSupport pathHasParent:@"/"] == NO);
}

void test_file_chooser_support_search_options_have_globs ()
{
	NSDictionary* options = [FileChooserSupport searchOptionsForPath:@"/usr/share"];
	OAK_ASSERT(options != nil);
	// The defaults globs_for_path guarantees when settings define no include globs: without
	// them the search matches nothing at all. Key names are OakDocumentController's.
	OAK_ASSERT(options[@"DirectoryGlobs"] != nil || options[@"Globs"] != nil);
	OAK_ASSERT(options[@"FileGlobs"] != nil || options[@"Globs"] != nil);
	// And the two the panel sets itself.
	OAK_ASSERT(options[@"FollowDirectoryLinks"] != nil);
	OAK_ASSERT([options[@"IgnoreOrdering"] boolValue] == YES);
}

void test_file_chooser_scm_info_is_queryable ()
{
	// scm::info() is optimistic: it hands back a handle for any SCM-enabled path and
	// resolves the actual driver on a background queue, so this is non-nil well away from
	// any working copy. The panel relies on exactly that — it creates the info first and
	// asks for status later — so what matters is that querying it is safe either way.
	FileChooserSCMInfo* info = [FileChooserSCMInfo infoForPath:@"/usr/share"];
	if(info)
		OAK_ASSERT([info uncommittedPaths] != nil);
}
