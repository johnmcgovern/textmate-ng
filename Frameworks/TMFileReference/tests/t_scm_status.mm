#import <TMFileReference/TMFileReference.h>
#import <TMFileReference/FileItemImage.h>
#import <scm/status.h>

// TMSCMStatus is the ObjC spelling of scm::status::type. The two are converted
// by a plain cast at the framework boundary, so everything here is about them
// staying interchangeable.
//
// The reason this is worth testing at all rather than trusting the header: the
// C++ enum is **4 bytes** (its largest value is 128, so the compiler picks
// `unsigned int`) while NSUInteger is **8**. A hand-written declaration that got
// that wrong would not fail to compile — it would corrupt whatever sits next to
// the property. TMSCMStatus removes the trap by making both sides read the same
// ObjC declaration; these tests are what stops the two drifting apart again.

void test_widths_are_what_the_cast_assumes ()
{
	// The mismatch that motivated the change, asserted rather than described.
	OAK_ASSERT_EQ(sizeof(scm::status::type), 4);
	OAK_ASSERT_EQ(sizeof(TMSCMStatus), sizeof(NSUInteger));
	OAK_ASSERT_EQ(sizeof(TMSCMStatus), 8);

	// Widening is therefore always safe; narrowing would not be, which is why
	// the ObjC side is the wider of the two.
	OAK_ASSERT(sizeof(TMSCMStatus) >= sizeof(scm::status::type));
}

// Value-for-value. A divergence here compiles clean and draws the wrong badge.
void test_every_value_round_trips ()
{
	struct { scm::status::type cxx; TMSCMStatus objc; char const* name; } const pairs[] =
	{
		{ scm::status::unknown,     TMSCMStatusUnknown,     "unknown"     },
		{ scm::status::none,        TMSCMStatusNone,        "none"        },
		{ scm::status::unversioned, TMSCMStatusUnversioned, "unversioned" },
		{ scm::status::modified,    TMSCMStatusModified,    "modified"    },
		{ scm::status::added,       TMSCMStatusAdded,       "added"       },
		{ scm::status::deleted,     TMSCMStatusDeleted,     "deleted"     },
		{ scm::status::conflicted,  TMSCMStatusConflicted,  "conflicted"  },
		{ scm::status::ignored,     TMSCMStatusIgnored,     "ignored"     },
		{ scm::status::mixed,       TMSCMStatusMixed,       "mixed"       },
	};

	for(auto const& pair : pairs)
	{
		OAK_ASSERT_EQ((NSUInteger)pair.cxx, (NSUInteger)pair.objc);
		OAK_ASSERT_EQ((NSUInteger)(TMSCMStatus)pair.cxx, (NSUInteger)pair.objc);
		OAK_ASSERT_EQ((NSUInteger)(scm::status::type)pair.objc, (NSUInteger)pair.cxx);
	}
}

// It is NS_OPTIONS rather than NS_ENUM because callers really do mask it —
// FileItemSCMStatus.mm and FileChooser.mm both test
// `status & (modified|added|deleted|conflicted)`. That only works if the values
// stay disjoint bits, which a careless renumbering would break.
void test_the_values_are_disjoint_bits ()
{
	NSUInteger seen = 0;
	for(TMSCMStatus status : { TMSCMStatusNone, TMSCMStatusUnversioned, TMSCMStatusModified, TMSCMStatusAdded, TMSCMStatusDeleted, TMSCMStatusConflicted, TMSCMStatusIgnored, TMSCMStatusMixed })
	{
		OAK_ASSERT_EQ(status & (status - 1), 0); // exactly one bit set
		OAK_ASSERT_EQ(seen & status, 0);         // and not one already used
		seen |= status;
	}

	// The mask the file browser actually uses, spelled the way it spells it.
	TMSCMStatus const interesting = TMSCMStatusModified|TMSCMStatusAdded|TMSCMStatusDeleted|TMSCMStatusConflicted;
	OAK_ASSERT(TMSCMStatusModified & interesting);
	OAK_ASSERT(!(TMSCMStatusIgnored & interesting));
}

// The property is the surface the change was made for, so it is exercised
// through a real TMFileReference rather than only as a type.
void test_the_property_round_trips_through_a_file_reference ()
{
	TMFileReference* reference = [TMFileReference fileReferenceWithURL:[NSURL fileURLWithPath:@"/tmp/tm-scm-status-fixture.txt"]];
	OAK_ASSERT(reference);

	reference.SCMStatus = TMSCMStatusModified;
	OAK_ASSERT_EQ((NSUInteger)reference.SCMStatus, (NSUInteger)TMSCMStatusModified);

	// Assigned the way SCMManager.mm assigns it: a C++ value cast at the call
	// site. If the widths ever disagreed, this is where it would show.
	scm::status::type const fromCxx = scm::status::conflicted;
	reference.SCMStatus = (TMSCMStatus)fromCxx;
	OAK_ASSERT_EQ((NSUInteger)reference.SCMStatus, (NSUInteger)TMSCMStatusConflicted);

	reference.SCMStatus = TMSCMStatusNone;
}

// CreateIconImageForURL takes the status too, and is the other exported
// signature that used to be C++-typed. Drawing is what it is for, so the
// assertion is that it produces an image at all for each status rather than
// what the image looks like.
void test_icon_image_is_produced_for_every_status ()
{
	NSURL* url = [NSURL fileURLWithPath:@"/tmp/tm-scm-status-fixture.txt"];
	for(TMSCMStatus status : { TMSCMStatusUnknown, TMSCMStatusNone, TMSCMStatusUnversioned, TMSCMStatusModified, TMSCMStatusAdded, TMSCMStatusDeleted, TMSCMStatusConflicted, TMSCMStatusIgnored, TMSCMStatusMixed })
	{
		NSImage* image = CreateIconImageForURL(url, NO, NO, NO, NO, status);
		OAK_ASSERT(image);
		OAK_ASSERT_EQ(image.size.width, 16);
		OAK_ASSERT_EQ(image.size.height, 16);
	}
}
