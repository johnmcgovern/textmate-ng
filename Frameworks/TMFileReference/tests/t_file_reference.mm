#import <TMFileReference/TMFileReference.h>
#import "TMFRKVORecorder.h"

// TMFileReference is Swift behind a hand-written ObjC header, so nothing checks
// the two against each other at build time — the same gap OakTabBarView and
// BundleEditor recorded, and the reason this bundle drives the class through
// its *public ObjC surface* rather than importing anything internal.
//
// The interesting behaviour is all contract rather than computation: interning,
// the accessor/KVC-key split that `getter =` creates, and the KVO notifications
// several windows depend on to keep one file's icon in step.

static NSURL* TestURL (NSString* name)
{
	return [NSURL fileURLWithPath:[@"/tmp/tm-file-reference-tests" stringByAppendingPathComponent:name]];
}

// One object per URL is the class's whole purpose: several windows showing the
// same file have to share KVO notifications, which only works if they are
// looking at the same object.
void test_references_are_interned_per_url ()
{
	TMFileReference* a = [TMFileReference fileReferenceWithURL:TestURL(@"a.txt")];
	TMFileReference* b = [TMFileReference fileReferenceWithURL:TestURL(@"a.txt")];
	TMFileReference* c = [TMFileReference fileReferenceWithURL:TestURL(@"b.txt")];

	OAK_ASSERT(a);
	OAK_ASSERT(a == b);
	OAK_ASSERT(a != c);
	OAK_ASSERT([a isEqual:b]);
	OAK_ASSERT(![a isEqual:c]);
	OAK_ASSERT_EQ(a.hash, b.hash);
}

// The key is -absoluteURL, so a URL expressed relative to a base lands on the
// same object as the direct one.
void test_interning_resolves_a_relative_url ()
{
	NSURL* base = [NSURL fileURLWithPath:@"/tmp/tm-file-reference-tests" isDirectory:YES];

	TMFileReference* direct   = [TMFileReference fileReferenceWithURL:TestURL(@"c.txt")];
	TMFileReference* relative = [TMFileReference fileReferenceWithURL:[NSURL URLWithString:@"c.txt" relativeToURL:base]];
	OAK_ASSERT(direct == relative);
}

// …but -absoluteURL does NOT normalise the path, so a URL carrying a "." or ".."
// component is a *different* reference for the same file. That is a real sharp
// edge and it is pre-existing — the ObjC++ keyed the same map the same way — so
// it is pinned rather than quietly fixed: changing it to -standardizedFileURL
// would be a behaviour change, not a port, and belongs in its own commit.
void test_interning_does_not_normalise_dot_components ()
{
	TMFileReference* direct       = [TMFileReference fileReferenceWithURL:TestURL(@"d.txt")];
	TMFileReference* unnormalised = [TMFileReference fileReferenceWithURL:[NSURL fileURLWithPath:@"/tmp/tm-file-reference-tests/./d.txt"]];
	OAK_ASSERT(direct != unnormalised);
}

void test_nil_url_yields_nil ()
{
	OAK_ASSERT(![TMFileReference fileReferenceWithURL:nil]);
}

// An image-backed reference has no URL, is never interned, and so is only ever
// equal to itself — otherwise two of them would collide in any set.
void test_image_backed_references_are_not_interned ()
{
	NSImage* image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
	TMFileReference* a = [TMFileReference fileReferenceWithImage:image];
	TMFileReference* b = [TMFileReference fileReferenceWithImage:image];

	OAK_ASSERT(a != b);
	OAK_ASSERT(![a isEqual:b]);
	OAK_ASSERT([a isEqual:a]);
	OAK_ASSERT(a.image == image);
}

// =====================================
// = The `getter =` accessor/key split =
// =====================================

// `@property (getter = isClosable) BOOL closable` has two names: the selector
// -isClosable and the KVC key `closable`. Both have to resolve — bindings and
// the manual will/didChangeValueForKey: calls use the key, everything else uses
// the selector.
//
// ⚠️ This does NOT distinguish the two Swift spellings, and was written
// believing it did. `@objc(isClosable)` on the property renames the KVC key to
// `isClosable`, yet -valueForKey:@"closable" still finds it, because KVC's
// search order tries -isKey. Verified by mutation: the wrong spelling passes.
// The documented setSelected: trap is about the *setter*, so it only bites a
// readwrite property, and both of these are readonly.
void test_closable_has_both_its_selector_and_its_kvc_key ()
{
	TMFileReference* reference = [TMFileReference fileReferenceWithURL:TestURL(@"closable.txt")];

	OAK_ASSERT([reference respondsToSelector:@selector(isClosable)]);
	OAK_ASSERT(!reference.isClosable);
	OAK_ASSERT(![[reference valueForKey:@"closable"] boolValue]);

	[reference increaseOpenCount];
	OAK_ASSERT(reference.isClosable);
	OAK_ASSERT([[reference valueForKey:@"closable"] boolValue]);

	[reference decreaseOpenCount];
	OAK_ASSERT(!reference.isClosable);
}

void test_modified_has_both_its_selector_and_its_kvc_key ()
{
	TMFileReference* reference = [TMFileReference fileReferenceWithURL:TestURL(@"modified.txt")];
	[reference increaseOpenCount];

	OAK_ASSERT([reference respondsToSelector:@selector(isModified)]);
	OAK_ASSERT(!reference.isModified);
	OAK_ASSERT(![[reference valueForKey:@"modified"] boolValue]);

	[reference increaseModifiedCount];
	OAK_ASSERT(reference.isModified);
	OAK_ASSERT([[reference valueForKey:@"modified"] boolValue]);

	[reference decreaseModifiedCount];
	OAK_ASSERT(!reference.isModified);
	[reference decreaseOpenCount];
}

// Counts, not flags: two windows opening the same file each contribute one, and
// the file stays closable until both let go.
void test_counts_accumulate_across_owners ()
{
	TMFileReference* reference = [TMFileReference fileReferenceWithURL:TestURL(@"counts.txt")];

	[reference increaseOpenCount];
	[reference increaseOpenCount];
	OAK_ASSERT(reference.isClosable);

	[reference decreaseOpenCount];
	OAK_ASSERT(reference.isClosable); // still open, one owner remains

	[reference decreaseOpenCount];
	OAK_ASSERT(!reference.isClosable);
}

// =======
// = KVO =
// =======

// The counters are incremented by several owners independently, so there is no
// single assignment for Swift to observe — the notifications are posted by hand
// and would simply stop if a port dropped them.
void test_open_and_modified_counts_notify ()
{
	TMFileReference* reference = [TMFileReference fileReferenceWithURL:TestURL(@"kvo.txt")];
	TMFRKVORecorder* observer = [TMFRKVORecorder new];

	[reference addObserver:observer forKeyPath:@"closable" options:0 context:NULL];
	[reference addObserver:observer forKeyPath:@"modified" options:0 context:NULL];

	[reference increaseOpenCount];
	[reference increaseModifiedCount];

	OAK_ASSERT([observer sawKeyPath:@"closable"]);
	OAK_ASSERT([observer sawKeyPath:@"modified"]);

	[reference removeObserver:observer forKeyPath:@"closable"];
	[reference removeObserver:observer forKeyPath:@"modified"];

	[reference decreaseModifiedCount];
	[reference decreaseOpenCount];
}

// Changing the SCM status invalidates the cached icon, and views bound to
// `image` have to be told — otherwise a file's badge would only appear the next
// time something else happened to redraw it.
void test_scm_status_change_invalidates_the_image ()
{
	TMFileReference* reference = [TMFileReference fileReferenceWithURL:TestURL(@"badge.txt")];
	TMFRKVORecorder* observer = [TMFRKVORecorder new];

	OAK_ASSERT(reference.image); // populate the cache first — there is nothing to invalidate otherwise

	[reference addObserver:observer forKeyPath:@"image" options:0 context:NULL];
	reference.SCMStatus = TMSCMStatusModified;
	OAK_ASSERT([observer sawKeyPath:@"image"]);

	// Setting the same value again changes nothing, so it must not notify.
	[observer reset];
	reference.SCMStatus = TMSCMStatusModified;
	OAK_ASSERT(![observer sawKeyPath:@"image"]);

	[reference removeObserver:observer forKeyPath:@"image"];
	reference.SCMStatus = TMSCMStatusNone;
}

// `icon` is derived from `image` and `modified`, and the dependency is declared
// rather than observed — a binding on `icon` only updates because of this.
void test_icon_declares_its_dependencies ()
{
	NSSet* keyPaths = [TMFileReference keyPathsForValuesAffectingValueForKey:@"icon"];
	OAK_ASSERT([keyPaths containsObject:@"image"]);
	OAK_ASSERT([keyPaths containsObject:@"modified"]);
}

// ==========
// = Images =
// ==========

void test_image_for_url_is_returned_at_the_requested_size ()
{
	NSImage* image = [TMFileReference imageForURL:TestURL(@"sized.txt") size:NSMakeSize(32, 32)];
	OAK_ASSERT(image);
	OAK_ASSERT_EQ(image.size.width, 32);
	OAK_ASSERT_EQ(image.size.height, 32);

	// …and resizing the copy must not have resized the shared one.
	OAK_ASSERT_EQ([TMFileReference fileReferenceWithURL:TestURL(@"sized.txt")].image.size.width, 16);
}

// The dimmed variant is a different image, not the same one mutated — the
// undimmed original stays available to everything else showing the file.
void test_icon_is_dimmed_only_while_modified ()
{
	TMFileReference* reference = [TMFileReference fileReferenceWithURL:TestURL(@"dimmed.txt")];
	[reference increaseOpenCount];

	OAK_ASSERT(reference.icon == reference.image); // not modified: the icon is the image

	[reference increaseModifiedCount];
	OAK_ASSERT(reference.icon != reference.image);
	OAK_ASSERT_EQ(reference.icon.size.width, reference.image.size.width);

	[reference decreaseModifiedCount];
	[reference decreaseOpenCount];
}
