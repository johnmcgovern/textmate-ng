#include <regexp/regexp.h>

void test_match ()
{
	// Named, not a literal: the match points into the string it searched, and the
	// std::string overload now refuses a temporary (see regexp.h).
	std::string const subject = " foo bar fud";
	regexp::match_t const match = regexp::search("(\\w+)\\s+(\\w+)", subject);
	OAK_ASSERT(match);
	OAK_ASSERT_EQ(match[0], "foo bar");
	OAK_ASSERT_EQ(match[1], "foo");
	OAK_ASSERT_EQ(match[2], "bar");
	OAK_ASSERT_EQ(match[3], NULL_STR);
}
