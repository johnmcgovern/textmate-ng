#import "../src/FindSupport.h"
#import <OakFoundation/OakFindProtocol.h>

// FFFindOperation is the ObjC spelling of find_operation_t, split out for the
// port the same way FFFindOptions was — and pinned the same way, by static_assert
// in FindSupport.mm and by this table at runtime.
//
// Both guards, for the reason t_find_options.mm gives: the static_assert lives in
// a file that exists only as long as C++ does. TMSCMStatus.h still claims its
// values are "pinned by static_assert in TMFileReference.mm", a file that was
// ported to Swift in 8601c693 and took the assertions with it. The runtime table
// is what survived that. Keep both.
//
// Unlike the options this one is an ordinal, not a mask, so what matters is that
// each name lands on the same *number* — a transposed pair here would make Find
// Next perform a Replace All.

void test_ff_find_operation_matches_the_cxx_enum ()
{
	struct { find_operation_t cxx; FFFindOperation objc; char const* name; } const pairs[] =
	{
		{ kFindOperationCount,                 FFFindOperationCount,                 "count"                 },
		{ kFindOperationCountInSelection,      FFFindOperationCountInSelection,      "countInSelection"      },
		{ kFindOperationFind,                  FFFindOperationFind,                  "find"                  },
		{ kFindOperationFindInSelection,       FFFindOperationFindInSelection,       "findInSelection"       },
		{ kFindOperationReplace,               FFFindOperationReplace,               "replace"               },
		{ kFindOperationReplaceAndFind,        FFFindOperationReplaceAndFind,        "replaceAndFind"        },
		{ kFindOperationReplaceAll,            FFFindOperationReplaceAll,            "replaceAll"            },
		{ kFindOperationReplaceAllInSelection, FFFindOperationReplaceAllInSelection, "replaceAllInSelection" },
	};

	for(auto const& pair : pairs)
		OAK_MASSERT_EQ(std::string("FFFindOperation diverged from find_operation_t for ") + pair.name, (NSInteger)pair.cxx, (NSInteger)pair.objc);
}

// The whole point of the split: an ObjC or Swift declaration of this property is
// NSInteger-wide, and the C++ enum the compiler synthesised is not.
void test_ff_find_operation_is_pointer_width ()
{
	OAK_ASSERT_EQ(sizeof(FFFindOperation), sizeof(NSInteger));
	OAK_ASSERT(sizeof(FFFindOperation) >= sizeof(find_operation_t));
}

// Eight distinct values, so no two operations can collapse onto one another.
void test_ff_find_operation_values_are_distinct ()
{
	FFFindOperation const all[] = {
		FFFindOperationCount, FFFindOperationCountInSelection,
		FFFindOperationFind, FFFindOperationFindInSelection,
		FFFindOperationReplace, FFFindOperationReplaceAndFind,
		FFFindOperationReplaceAll, FFFindOperationReplaceAllInSelection,
	};

	std::set<NSInteger> seen;
	for(FFFindOperation operation : all)
		seen.insert((NSInteger)operation);
	OAK_ASSERT_EQ(seen.size(), sizeof(all) / sizeof(all[0]));
}
