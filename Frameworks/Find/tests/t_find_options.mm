#import "../src/FFFindOptions.h"
#import <regexp/find.h>

// FFFindOptions is the ObjC spelling of find::options_t. The two are converted
// explicitly in FFDocumentSearchSupport.mm, which pins them with static_assert
// — so in principle these tests can never fail.
//
// They exist anyway, for the same reason t_scm_status.mm does: the static_assert
// lives in a file that exists only because C++ has to stay, and this project has
// already lost that guard once. TMSCMStatus.h still says its values are "pinned
// by static_assert in TMFileReference.mm" — a file that no longer exists, ported
// to Swift in 8601c693, taking the assertions with it. The runtime table is what
// survived. Keep both.

void test_ff_find_options_is_pointer_width ()
{
	// The whole point of the NS_OPTIONS split: an ObjC/Swift declaration of this
	// property is NSUInteger-wide, and find::options_t is not.
	OAK_ASSERT_EQ(sizeof(FFFindOptions), sizeof(NSUInteger));
	OAK_ASSERT_EQ(sizeof(FFFindOptions), 8);
	OAK_ASSERT(sizeof(FFFindOptions) >= sizeof(find::options_t));
}

void test_ff_find_options_matches_the_cxx_enum ()
{
	struct { find::options_t cxx; FFFindOptions objc; char const* name; } const pairs[] =
	{
		{ find::none,               FFFindOptionsNone,              "none"               },
		{ find::full_words,         FFFindOptionsFullWords,         "full_words"         },
		{ find::ignore_case,        FFFindOptionsIgnoreCase,        "ignore_case"        },
		{ find::ignore_whitespace,  FFFindOptionsIgnoreWhitespace,  "ignore_whitespace"  },
		{ find::regular_expression, FFFindOptionsRegularExpression, "regular_expression" },
		{ find::backwards,          FFFindOptionsBackwards,         "backwards"          },
		{ find::not_bol,            FFFindOptionsNotBOL,            "not_bol"            },
		{ find::not_eol,            FFFindOptionsNotEOL,            "not_eol"            },
		{ find::wrap_around,        FFFindOptionsWrapAround,        "wrap_around"        },
		{ find::all_matches,        FFFindOptionsAllMatches,        "all_matches"        },
		{ find::extend_selection,   FFFindOptionsExtendSelection,   "extend_selection"   },
		{ find::filesize_limit,     FFFindOptionsFileSizeLimit,     "filesize_limit"     },
	};

	for(auto const& pair : pairs)
		OAK_MASSERT_EQ(std::string("FFFindOptions diverged from find::options_t for ") + pair.name, (NSUInteger)pair.cxx, (NSUInteger)pair.objc);
}

// The bits are a mask, which is why this is NS_OPTIONS and not NS_ENUM — Find.mm
// builds it with | and tests it with &.
void test_ff_find_options_composes_as_a_mask ()
{
	FFFindOptions const combined = FFFindOptionsRegularExpression | FFFindOptionsIgnoreCase;

	OAK_ASSERT(combined & FFFindOptionsRegularExpression);
	OAK_ASSERT(combined & FFFindOptionsIgnoreCase);
	OAK_ASSERT(!(combined & FFFindOptionsBackwards));

	// And survives the round trip the support file performs.
	find::options_t const asCxx = (find::options_t)combined;
	OAK_ASSERT(asCxx & find::regular_expression);
	OAK_ASSERT(asCxx & find::ignore_case);
	OAK_ASSERT_EQ((NSUInteger)asCxx, (NSUInteger)combined);
}
