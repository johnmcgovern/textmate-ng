#include <plist/plist.h>
#include <plist/ascii.h>

// Written against the fuzzer's first two findings (2026-09-16). Both were Debug
// assertions on malformed input, which end the process; Release compiled the
// assertion out and did something else. These pin the behaviour now: a clean
// parse failure, and a string that comes back whatever its bytes.

void test_a_numeric_key_is_its_string ()
{
	// As before the fix: numbers convert to strings, so "{ 42 = 1; }" is a
	// dictionary keyed by "42" (t_simple pins the same thing from the other side).
	bool success = false;
	plist::any_t plist = plist::parse_ascii("{ 42 = foo; }", &success);
	OAK_ASSERT_EQ(success, true);
	std::string value;
	OAK_ASSERT(plist::get_key_path(plist, "42", value));
	OAK_ASSERT_EQ(value, "foo");
}

void test_a_structured_key_is_a_parse_failure_not_an_assertion ()
{
	// An array or a dictionary cannot become a string, and asking made the old
	// code assert. Now the parse fails and says so.
	bool success = true;
	plist::parse_ascii("{ ( 1 ) = foo; }", &success);
	OAK_ASSERT_EQ(success, false);

	success = true;
	plist::parse_ascii("{ { a = b; } = foo; }", &success);
	OAK_ASSERT_EQ(success, false);
}

void test_a_string_key_still_parses ()
{
	bool success = false;
	plist::any_t plist = plist::parse_ascii("{ foo = bar; \"1\" = baz; }", &success);
	OAK_ASSERT_EQ(success, true);
	std::string foo, one;
	OAK_ASSERT(plist::get_key_path(plist, "foo", foo));
	OAK_ASSERT(plist::get_key_path(plist, "1", one));
	OAK_ASSERT_EQ(foo, "bar");
	OAK_ASSERT_EQ(one, "baz");
}

void test_to_s_survives_a_string_that_is_not_utf8 ()
{
	// The fuzzer's input: a UUID with one stray byte. Pretty-printing it walked
	// the string as UTF-8 and asserted on the byte after it.
	bool success = false;
	plist::any_t plist = plist::parse_ascii("{ uuid = \"0A0DA1FC-59DE-4FD9-9A3C-\xD5" "3C6811A3C39\"; }", &success);
	OAK_ASSERT_EQ(success, true);
	std::string res = to_s(plist);
	OAK_ASSERT(res.find("uuid") != std::string::npos);
	OAK_ASSERT(res.find("3C6811A3C39") != std::string::npos);
}
