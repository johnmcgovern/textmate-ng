#import "FindTesting.h"

// -findOptionsForAction: is Find's option assembly: five check boxes and the
// action being performed go in, one FFFindOptions mask comes out, and that mask
// is what every search in the application is actually run with. It was untested,
// and it is the shape of thing a port reproduces from memory and gets subtly
// wrong — five near-identical ternaries in a row, in a fixed order, one of them
// reading a *derived* property rather than the ivar behind it.
//
// Asserted against FFFindOptions rather than find::options_t deliberately. The
// two are pinned to each other by static_assert in FFDocumentSearchSupport.mm and
// by t_find_options.mm at runtime, so checking the ObjC spelling checks both —
// and it leaves the port no room to invent a second spelling for a type that
// already has one.

// Builds a Find with all five options off. Each test turns on only what it is
// about, so a bit appearing in a mask can only have come from the property the
// test set.
static Find* FindWithNoOptions ()
{
	Find* find = [Find new];
	find.ignoreCase        = NO;
	find.ignoreWhitespace  = NO;
	find.regularExpression = NO;
	find.wrapAround        = NO;
	find.fullWords         = NO;
	return find;
}

void test_find_options_are_empty_when_every_check_box_is_off ()
{
	Find* find = FindWithNoOptions();
	OAK_ASSERT_EQ((NSUInteger)[find findOptionsForAction:FindActionFindNext], (NSUInteger)FFFindOptionsNone);
}

// One property at a time, so a transposed pair in the assembly is caught. The
// original is five ternaries in the order regularExpression, ignoreWhitespace,
// fullWords, ignoreCase, wrapAround — an order with no meaning, which is exactly
// why swapping two of them would go unnoticed.
void test_each_check_box_contributes_its_own_bit ()
{
	Find* ignoreCase = FindWithNoOptions();
	ignoreCase.ignoreCase = YES;
	OAK_ASSERT_EQ((NSUInteger)[ignoreCase findOptionsForAction:FindActionFindNext], (NSUInteger)FFFindOptionsIgnoreCase);

	Find* wrapAround = FindWithNoOptions();
	wrapAround.wrapAround = YES;
	OAK_ASSERT_EQ((NSUInteger)[wrapAround findOptionsForAction:FindActionFindNext], (NSUInteger)FFFindOptionsWrapAround);

	Find* fullWords = FindWithNoOptions();
	fullWords.fullWords = YES;
	OAK_ASSERT_EQ((NSUInteger)[fullWords findOptionsForAction:FindActionFindNext], (NSUInteger)FFFindOptionsFullWords);

	Find* regularExpression = FindWithNoOptions();
	regularExpression.regularExpression = YES;
	OAK_ASSERT_EQ((NSUInteger)[regularExpression findOptionsForAction:FindActionFindNext], (NSUInteger)FFFindOptionsRegularExpression);

	Find* ignoreWhitespace = FindWithNoOptions();
	ignoreWhitespace.ignoreWhitespace = YES;
	OAK_ASSERT_EQ((NSUInteger)[ignoreWhitespace findOptionsForAction:FindActionFindNext], (NSUInteger)FFFindOptionsIgnoreWhitespace);
}

void test_find_options_compose ()
{
	Find* find = FindWithNoOptions();
	find.ignoreCase = YES;
	find.wrapAround = YES;
	find.fullWords  = YES;

	FFFindOptions const options = [find findOptionsForAction:FindActionFindNext];
	OAK_ASSERT(options & FFFindOptionsIgnoreCase);
	OAK_ASSERT(options & FFFindOptionsWrapAround);
	OAK_ASSERT(options & FFFindOptionsFullWords);
	OAK_ASSERT(!(options & FFFindOptionsRegularExpression));
	OAK_ASSERT(!(options & FFFindOptionsIgnoreWhitespace));
}

// The one asymmetry in the five, and the reason this is not a table test.
// -ignoreWhitespace is not the ivar the check box writes: its getter answers NO
// whenever regularExpression is on, because -canIgnoreWhitespace is
// `_regularExpression == NO` and the check box is disabled in that state. So a
// regexp search never carries the ignore-whitespace bit, no matter what the box
// remembers from before.
//
// A port that stores five plain Bools and ORs them together compiles, passes
// every other test in this file, and silently changes what a regexp search
// matches.
void test_ignore_whitespace_is_suppressed_by_regular_expression ()
{
	Find* find = FindWithNoOptions();
	find.ignoreWhitespace  = YES;
	find.regularExpression = YES;

	FFFindOptions const options = [find findOptionsForAction:FindActionFindNext];
	OAK_ASSERT(options & FFFindOptionsRegularExpression);
	OAK_ASSERT(!(options & FFFindOptionsIgnoreWhitespace));

	// And it comes back when the regexp box is cleared — suppressed, not erased.
	find.regularExpression = NO;
	OAK_ASSERT([find findOptionsForAction:FindActionFindNext] & FFFindOptionsIgnoreWhitespace);
}

// The two bits the action adds rather than the user. Backwards for one action,
// all-matches for exactly three, and nothing for the rest.
void test_find_previous_searches_backwards ()
{
	Find* find = FindWithNoOptions();

	OAK_ASSERT([find findOptionsForAction:FindActionFindPrevious] & FFFindOptionsBackwards);
	OAK_ASSERT(!([find findOptionsForAction:FindActionFindNext] & FFFindOptionsBackwards));

	// Backwards and all-matches are exclusive branches of one if/else, so the
	// action that goes backwards never also asks for every match.
	OAK_ASSERT(!([find findOptionsForAction:FindActionFindPrevious] & FFFindOptionsAllMatches));
}

void test_the_counting_actions_ask_for_all_matches ()
{
	Find* find = FindWithNoOptions();

	FindActionTag const collects[] = { FindActionCountMatches, FindActionFindAll, FindActionReplaceAll };
	for(FindActionTag action : collects)
		OAK_MASSERT("action should carry FFFindOptionsAllMatches", [find findOptionsForAction:action] & FFFindOptionsAllMatches);

	// Replace, Replace & Find and Find Next work one match at a time.
	FindActionTag const single[] = { FindActionFindNext, FindActionFindPrevious, FindActionReplace, FindActionReplaceAndFind, FindActionReplaceSelected };
	for(FindActionTag action : single)
		OAK_MASSERT("action should not carry FFFindOptionsAllMatches", !([find findOptionsForAction:action] & FFFindOptionsAllMatches));
}

// The action bits are added to the check-box bits, not substituted for them.
void test_action_bits_are_added_to_the_check_box_bits ()
{
	Find* find = FindWithNoOptions();
	find.ignoreCase = YES;
	find.wrapAround = YES;

	FFFindOptions const options = [find findOptionsForAction:FindActionReplaceAll];
	OAK_ASSERT(options & FFFindOptionsIgnoreCase);
	OAK_ASSERT(options & FFFindOptionsWrapAround);
	OAK_ASSERT(options & FFFindOptionsAllMatches);
}
