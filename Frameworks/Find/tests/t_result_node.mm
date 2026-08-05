#import "../src/FFResultNode.h"
#import "FFKVORecorder.h"

// FFResultNode is the model behind the find results outline view: a root, one
// branch per file, one leaf per match. What makes it worth testing before the
// port is that the four counters — leafs, excluded, read-only, excluded
// read-only — are maintained *incrementally*. Every setter pushes its own delta
// into the parent, so the tree's totals are never recomputed and any error is
// permanent and silent. That is the same shape as the tab bar's "count of
// visible tabs always reported zero" bug this project already shipped once.
//
// Two things a Swift port has to get right, both invisible in the header:
//
//  - Adding the first child to a *leaf* converts it into a branch, and the
//    conversion subtracts the node's own leaf count. The subtraction runs
//    through `_parent.countOfLeafs += count - _countOfLeafs` on NSUInteger,
//    so it is an unsigned wraparound that is correct only because it wraps
//    back. Swift's UInt traps on exactly that, which is a compile-clean port
//    that crashes on the second match in a file.
//  - A node's `excluded` and `isReadOnly` are *derived* from the counters
//    rather than stored, and the derivation differs for leaves and branches.
//
// The tests drive the public ObjC surface only, and pass a nil match: none of
// the counter logic reads it, and the alternative is standing up the document
// registry to learn nothing extra.

static FFResultNode* Leaf ()
{
	return [FFResultNode resultNodeWithMatch:nil];
}

// The production tree, as Find.mm builds it: a bare root, a branch per file,
// leaves under it.
static FFResultNode* TreeWithRoot (FFResultNode** rootOut, FFResultNode** fileOut, NSUInteger matches)
{
	FFResultNode* root = [FFResultNode new];
	FFResultNode* file = Leaf();
	[root addResultNode:file];

	for(NSUInteger i = 0; i < matches; ++i)
		[file addResultNode:Leaf()];

	if(rootOut) *rootOut = root;
	if(fileOut) *fileOut = file;
	return root;
}

// ==================
// = Initial states =
// ==================

// The root is `[FFResultNode new]` in Find.mm — no match, no children, and
// counting nothing. It must not count itself, or every search starts one match
// over.
void test_a_fresh_root_counts_nothing ()
{
	FFResultNode* root = [FFResultNode new];
	OAK_ASSERT_EQ(root.countOfLeafs, 0);
	OAK_ASSERT(root.children == nil);
	OAK_ASSERT(root.firstResultNode == nil);
	OAK_ASSERT(root.lastResultNode == nil);
}

void test_a_leaf_counts_itself ()
{
	FFResultNode* leaf = Leaf();
	OAK_ASSERT_EQ(leaf.countOfLeafs, 1);
	OAK_ASSERT_EQ(leaf.countOfExcluded, 0);
	OAK_ASSERT_EQ(leaf.countOfReadOnly, 0);
}

// =========================
// = The counter algebra   =
// =========================

// The conversion described at the top: the node stops counting itself as it
// starts counting children, so one child of a former leaf is still a total of
// one.
void test_adding_a_child_converts_a_leaf_into_a_branch ()
{
	FFResultNode* file = Leaf();
	OAK_ASSERT_EQ(file.countOfLeafs, 1);

	[file addResultNode:Leaf()];
	OAK_ASSERT_EQ(file.countOfLeafs, 1);

	[file addResultNode:Leaf()];
	OAK_ASSERT_EQ(file.countOfLeafs, 2);
}

// The same conversion, one level down, where the delta has to travel through a
// parent that is itself mid-conversion. This is the case that wraps.
void test_counts_reach_the_root_through_the_conversion ()
{
	FFResultNode* root = nil; FFResultNode* file = nil;
	TreeWithRoot(&root, &file, 2);

	OAK_ASSERT_EQ(file.countOfLeafs, 2);
	OAK_ASSERT_EQ(root.countOfLeafs, 2);
}

void test_a_second_file_adds_to_the_root ()
{
	FFResultNode* root = nil; FFResultNode* fileA = nil;
	TreeWithRoot(&root, &fileA, 2);

	FFResultNode* fileB = Leaf();
	[root addResultNode:fileB];
	[fileB addResultNode:Leaf()];

	OAK_ASSERT_EQ(fileB.countOfLeafs, 1);
	OAK_ASSERT_EQ(root.countOfLeafs, 3);
}

// -removeFromParent is the undo, and it has to unwind all four counters. The
// results view calls it when the user removes a row.
void test_removing_a_leaf_reverses_every_counter ()
{
	FFResultNode* root = nil; FFResultNode* file = nil;
	TreeWithRoot(&root, &file, 2);

	FFResultNode* last = file.lastResultNode;
	last.excluded = YES;
	last.readOnly = YES;

	OAK_ASSERT_EQ(root.countOfLeafs, 2);
	OAK_ASSERT_EQ(root.countOfExcluded, 1);
	OAK_ASSERT_EQ(root.countOfReadOnly, 1);
	OAK_ASSERT_EQ(root.countOfExcludedReadOnly, 1);

	[last removeFromParent];

	OAK_ASSERT_EQ(file.countOfLeafs, 1);
	OAK_ASSERT_EQ(root.countOfLeafs, 1);
	OAK_ASSERT_EQ(root.countOfExcluded, 0);
	OAK_ASSERT_EQ(root.countOfReadOnly, 0);
	OAK_ASSERT_EQ(root.countOfExcludedReadOnly, 0);
	OAK_ASSERT_EQ(file.children.count, 1);
}

// =====================================
// = excluded / readOnly are derived   =
// =====================================

// A leaf is excluded when its own count says so; a branch only when *every*
// leaf under it is. The checkbox in the results view reads this directly, so
// the branch case is the tri-state it renders.
void test_a_branch_is_excluded_only_when_all_its_leaves_are ()
{
	FFResultNode* root = nil; FFResultNode* file = nil;
	TreeWithRoot(&root, &file, 2);

	FFResultNode* first = file.firstResultNode;
	FFResultNode* last  = file.lastResultNode;

	first.excluded = YES;
	OAK_ASSERT(first.excluded);
	OAK_ASSERT(!file.excluded);
	OAK_ASSERT_EQ(file.countOfExcluded, 1);

	last.excluded = YES;
	OAK_ASSERT(file.excluded);
	OAK_ASSERT_EQ(file.countOfExcluded, 2);
	OAK_ASSERT_EQ(root.countOfExcluded, 2);
}

// Excluding a branch pushes down to its children — but skips read-only ones,
// because excluding a file that cannot be written is meaningless and would
// leave the branch permanently mixed.
void test_excluding_a_branch_skips_read_only_children ()
{
	FFResultNode* root = nil; FFResultNode* file = nil;
	TreeWithRoot(&root, &file, 2);

	FFResultNode* locked = file.firstResultNode;
	locked.readOnly = YES;
	OAK_ASSERT(locked.isReadOnly);

	file.excluded = YES;

	OAK_ASSERT(!locked.excluded);
	OAK_ASSERT(file.lastResultNode.excluded);
	OAK_ASSERT_EQ(file.countOfExcluded, 1);
}

// The fourth counter exists to answer "how many of the excluded ones were
// excluded only because they are read-only", which is what lets the view show
// a replace count that matches what a replace would actually do.
void test_excluded_read_only_tracks_both_flags ()
{
	FFResultNode* root = nil; FFResultNode* file = nil;
	TreeWithRoot(&root, &file, 1);

	FFResultNode* leaf = file.firstResultNode;

	leaf.excluded = YES;
	OAK_ASSERT_EQ(root.countOfExcluded, 1);
	OAK_ASSERT_EQ(root.countOfExcludedReadOnly, 0);

	leaf.readOnly = YES;
	OAK_ASSERT_EQ(root.countOfReadOnly, 1);
	OAK_ASSERT_EQ(root.countOfExcludedReadOnly, 1);
}

// The two setters are symmetric, and that is worth a test of its own because
// they reach the pair by different routes: -setExcluded: recomputes it from
// `_countOfReadOnly`, while -setReadOnly: recomputes it from `self.excluded`,
// which is itself derived. Either order therefore has to land on the same
// answer, and a port that keeps one route and drops the other passes every
// other test in this file.
void test_excluded_read_only_is_order_independent ()
{
	FFResultNode* rootA = nil; FFResultNode* fileA = nil;
	TreeWithRoot(&rootA, &fileA, 1);
	fileA.firstResultNode.readOnly = YES;
	fileA.firstResultNode.excluded = YES;

	FFResultNode* rootB = nil; FFResultNode* fileB = nil;
	TreeWithRoot(&rootB, &fileB, 1);
	fileB.firstResultNode.excluded = YES;
	fileB.firstResultNode.readOnly = YES;

	OAK_ASSERT_EQ(rootA.countOfExcludedReadOnly, 1);
	OAK_ASSERT_EQ(rootB.countOfExcludedReadOnly, 1);
	OAK_ASSERT_EQ(rootA.countOfExcluded, rootB.countOfExcluded);
	OAK_ASSERT_EQ(rootA.countOfReadOnly, rootB.countOfReadOnly);
}

// Clearing either flag clears the pair, by the same two routes.
void test_clearing_either_flag_clears_the_pair ()
{
	FFResultNode* root = nil; FFResultNode* file = nil;
	TreeWithRoot(&root, &file, 1);

	FFResultNode* leaf = file.firstResultNode;
	leaf.excluded = YES;
	leaf.readOnly = YES;
	OAK_ASSERT_EQ(root.countOfExcludedReadOnly, 1);

	leaf.readOnly = NO;
	OAK_ASSERT_EQ(root.countOfExcludedReadOnly, 0);
	OAK_ASSERT_EQ(root.countOfExcluded, 1);
}

// ==========================================
// = An edge the derivation walks into      =
// ==========================================

// A branch whose children have all been removed still *has* a children array,
// so the derivation compares 0 excluded against 0 leaves and reports the empty
// branch as excluded. Nothing renders it today — Find.mm removes empty parents
// — but it is the difference between `children != nil` and `children.count`,
// and a Swift port with an empty array instead of an optional would land here
// by default rather than by choice.
void test_an_emptied_branch_reports_itself_excluded ()
{
	FFResultNode* root = [FFResultNode new];
	FFResultNode* leaf = Leaf();
	[root addResultNode:leaf];
	[leaf removeFromParent];

	OAK_ASSERT_EQ(root.countOfLeafs, 0);
	OAK_ASSERT_EQ(root.children.count, 0);
	OAK_ASSERT(root.children != nil);
	OAK_ASSERT(root.excluded);
}

// ==================
// = Tree accessors =
// ==================

// Find.mm builds its FindMatch list from firstResultNode/lastResultNode, so
// their order is the order matches are stepped through.
void test_first_and_last_follow_insertion_order ()
{
	FFResultNode* root = nil; FFResultNode* file = nil;
	TreeWithRoot(&root, &file, 3);

	OAK_ASSERT_EQ(file.children.count, 3);
	OAK_ASSERT(file.firstResultNode == file.children.firstObject);
	OAK_ASSERT(file.lastResultNode == file.children.lastObject);
	OAK_ASSERT(file.firstResultNode != file.lastResultNode);
}

void test_a_child_knows_its_parent ()
{
	FFResultNode* root = nil; FFResultNode* file = nil;
	TreeWithRoot(&root, &file, 1);

	OAK_ASSERT(file.parent == root);
	OAK_ASSERT(file.firstResultNode.parent == file);
	OAK_ASSERT(root.parent == nil);
}

// ==================================================
// = KVO, which is how the results view sees changes =
// ==================================================

// The cell views bind to objectValue.excluded / .readOnly / .replaceString and
// recompute from them (FFResultsViewController.mm:60-61, :115), so these
// properties' contract is KVO compliance, not just a value.
//
// The dangerous case is a *branch*: -setExcluded: on a file row loops over its
// children setting theirs. In ObjC++ that loop goes through objc_msgSend and
// therefore through KVO's swizzled setter, so every child checkbox updates. A
// Swift property that is `@objc` but not `dynamic` is called directly from
// within Swift, bypassing the swizzle — the parent updates and the children
// silently do not.
void test_excluding_a_branch_notifies_its_children ()
{
	FFResultNode* root = nil; FFResultNode* file = nil;
	TreeWithRoot(&root, &file, 2);

	FFResultNode* child = file.firstResultNode;
	FFKVORecorder* recorder = [FFKVORecorder new];
	[child addObserver:recorder forKeyPath:@"excluded" options:NSKeyValueObservingOptionNew context:NULL];

	file.excluded = YES;

	OAK_ASSERT(child.excluded);
	OAK_ASSERT([recorder sawKeyPath:@"excluded"]);

	[child removeObserver:recorder forKeyPath:@"excluded"];
}

void test_replace_string_notifies_observers ()
{
	FFResultNode* root = nil; FFResultNode* file = nil;
	TreeWithRoot(&root, &file, 1);

	FFResultNode* leaf = file.firstResultNode;
	FFKVORecorder* recorder = [FFKVORecorder new];
	[leaf addObserver:recorder forKeyPath:@"replaceString" options:NSKeyValueObservingOptionNew context:NULL];

	leaf.replaceString = @"replacement";

	OAK_ASSERT([recorder sawKeyPath:@"replaceString"]);

	[leaf removeObserver:recorder forKeyPath:@"replaceString"];
}
