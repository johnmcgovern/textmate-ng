#import "../src/DWOutputType.h"
#import <command/parser.h>

// DWOutputType is the ObjC spelling of output::type. The two are pinned by
// static_assert in DocumentWindowSupport.mm, so in principle these can never
// fail.
//
// They exist anyway, for the reason t_find_options.mm and t_scm_status.mm give:
// the static_assert lives in a file that exists only because C++ has to stay,
// and this project has already lost that guard once. TMSCMStatus.h still says
// its values are "pinned by static_assert in TMFileReference.mm" — a file that
// no longer exists, ported to Swift in 8601c693, taking the assertions with it.
// The runtime table is what survived. Keep both.
//
// This enum matters more than the other two, because it is the only one of the
// three that is **written to user defaults**: OakRunCommandWindowController
// stores the raw integer under `filterOutputType`. A divergence would not merely
// mis-render something — it would read back last week's "insert after input" as
// "replace document".

void test_dw_output_type_matches_the_cxx_enum ()
{
	struct { output::type cxx; DWOutputType objc; char const* name; } const pairs[] =
	{
		{ output::replace_input,     DWOutputTypeReplaceInput,     "replace_input"     },
		{ output::replace_document,  DWOutputTypeReplaceDocument,  "replace_document"  },
		{ output::at_caret,          DWOutputTypeAtCaret,          "at_caret"          },
		{ output::after_input,       DWOutputTypeAfterInput,       "after_input"       },
		{ output::new_window,        DWOutputTypeNewWindow,        "new_window"        },
		{ output::tool_tip,          DWOutputTypeToolTip,          "tool_tip"          },
		{ output::discard,           DWOutputTypeDiscard,          "discard"           },
		{ output::replace_selection, DWOutputTypeReplaceSelection, "replace_selection" },
	};

	for(auto const& pair : pairs)
		OAK_MASSERT_EQ(std::string("DWOutputType diverged from output::type for ") + pair.name, (NSInteger)pair.cxx, (NSInteger)pair.objc);
}

// The whole point of the split: an ObjC or Swift declaration of this property is
// NSInteger-wide and the C++ enum the compiler synthesised is not.
void test_dw_output_type_is_pointer_width ()
{
	OAK_ASSERT_EQ(sizeof(DWOutputType), sizeof(NSInteger));
	OAK_ASSERT(sizeof(DWOutputType) >= sizeof(output::type));
}

// Zero is load-bearing. -setOutputType: *removes* the user default when the
// value is zero rather than storing it, so "replace input" is both the C++
// default and the meaning of an absent key — and a renumbering that moved it
// would make a missing preference mean something else.
void test_replace_input_is_zero ()
{
	OAK_ASSERT_EQ((NSInteger)DWOutputTypeReplaceInput, 0);
	OAK_ASSERT_EQ((NSInteger)output::replace_input, 0);
}

// Eight distinct values, so no two destinations can collapse onto one another.
void test_dw_output_type_values_are_distinct ()
{
	DWOutputType const all[] = {
		DWOutputTypeReplaceInput, DWOutputTypeReplaceDocument, DWOutputTypeAtCaret,
		DWOutputTypeAfterInput, DWOutputTypeNewWindow, DWOutputTypeToolTip,
		DWOutputTypeDiscard, DWOutputTypeReplaceSelection,
	};

	std::set<NSInteger> seen;
	for(DWOutputType type : all)
		seen.insert((NSInteger)type);
	OAK_ASSERT_EQ(seen.size(), sizeof(all) / sizeof(all[0]));
}
