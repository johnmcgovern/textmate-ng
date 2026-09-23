#include <test/jail.h>
#include <settings/settings.h>

void test_settings ()
{
	test::jail_t jail;
	jail.set_content(".tm_properties", "testSetting = Hello");
	jail.set_content("dir/.tm_properties", "[ *.cc ]\ntestSetting = '${testSetting}, world!'");

	OAK_ASSERT_EQ(settings_for_path(jail.path("dir/file.cc")).get("testSetting"), "Hello, world!");
	OAK_ASSERT_EQ(settings_for_path(jail.path("dir/file.h")).get("testSetting"), "Hello");
}

void test_sections ()
{
	test::jail_t jail;
	jail.set_content(".tm_properties", "testSetting = 7\n[ *.cc; *.h ]\ntestSetting = 6\n[ *.mm ]\ntestSetting = 5\n");

	OAK_ASSERT_EQ(settings_for_path(jail.path("file.m")).get("testSetting",  3), 7);
	OAK_ASSERT_EQ(settings_for_path(jail.path("file.h")).get("testSetting",  3), 6);
	OAK_ASSERT_EQ(settings_for_path(jail.path("file.cc")).get("testSetting", 3), 6);
	OAK_ASSERT_EQ(settings_for_path(jail.path("file.mm")).get("testSetting", 3), 5);
}

void test_sections_with_only_directory ()
{
	test::jail_t jail;
	jail.set_content(".tm_properties", "testSetting = parent\n[ folder/** ]\ntestSetting = child\n");
	OAK_ASSERT_EQ(settings_for_path(NULL_STR, "", jail.path()).get("testSetting"), "parent");
	OAK_ASSERT_EQ(settings_for_path(NULL_STR, "", jail.path("folder")).get("testSetting"), "child");
}

void test_conversions ()
{
	test::jail_t jail;
	jail.set_content(".tm_properties", "bool = true\nint = 42\nfloat = 5.5\nstring = 'charlie'\n");
	settings_t s = settings_for_path(jail.path("file.cc"));

	OAK_ASSERT_EQ(s.get("bool",        false),      true);
	OAK_ASSERT_EQ(s.get("int",             7),        42);
	OAK_ASSERT_EQ(s.get("float",         1.1),       5.5);
	OAK_ASSERT_EQ(s.get("string",    "sheen"), "charlie");

	OAK_ASSERT_EQ(s.get("Nonbool",     false),     false);
	OAK_ASSERT_EQ(s.get("Nonint",          7),         7);
	OAK_ASSERT_EQ(s.get("Nonfloat",      1.1),       1.1);
	OAK_ASSERT_EQ(s.get("Nonstring", "sheen"),   "sheen");
}

void test_coercion ()
{
	test::jail_t jail;
	jail.set_content(".tm_properties", "int = 42\nfloat = 42.0\nstring_1 = '42'\nstring_2 = '42.0'\n");
	settings_t s = settings_for_path(jail.path("file.cc"));

	OAK_ASSERT_EQ(s.get("int",    0),   42);
	OAK_ASSERT_EQ(s.get("int",  0.0), 42.0);
	OAK_ASSERT_EQ(s.get("int",  "0"), "42");

	OAK_ASSERT_EQ(s.get("float",    0),     42);
	OAK_ASSERT_EQ(s.get("float",  0.0),   42.0);
	OAK_ASSERT_EQ(s.get("float",  "0"), "42.0");

	OAK_ASSERT_EQ(s.get("string_1",    0),     42);
	OAK_ASSERT_EQ(s.get("string_1",  0.0),   42.0);
	OAK_ASSERT_EQ(s.get("string_1",  "0"),   "42");

	OAK_ASSERT_EQ(s.get("string_2",    0),     42);
	OAK_ASSERT_EQ(s.get("string_2",  0.0),   42.0);
	OAK_ASSERT_EQ(s.get("string_2",  "0"), "42.0");
}

// ============================================================
// = Folder trust                                             =
// ============================================================
//
// A `.tm_properties` travels with a checkout, so its contents are whatever the
// code's author put there. Proved end to end on 2026-09-22: a repository
// carrying `PATH = "<repo>/bin:$PATH"` and a `git` beside it ran its own `git`
// as soon as a file from it was open and any Git command was used.
//
// The rule is by case, not by a list of names. Lowercase is a setting —
// `fontName`, `softTabs` — and cannot select a program. Uppercase is an
// environment variable, and a bundle is free to treat any of them as the program
// it runs: `TM_GIT` falls back to `git`, `TM_RUBY` to `ruby`, and eleven more
// across the bundles installed on the development machine. That list changes
// whenever a bundle does, which is exactly why enumerating it would be a guess
// wearing the costume of a fix.
//
// Each of these installs its own predicate and puts it back, because the state
// is process-wide and a test that leaves it set would decide the next one.

struct trust_guard_t
{
	trust_guard_t (bool answer) { settings_t::set_trust_predicate([answer](std::string const&){ return answer; }); }
	~trust_guard_t ()           { settings_t::set_trust_predicate(nullptr); }
};

// The control for everything below: an untrusted folder's settings still apply.
// Without this, a test asserting that nothing came through would pass just as
// well if the file were never read, and would say nothing at all.
void test_an_untrusted_project_file_still_sets_settings ()
{
	test::jail_t jail;
	jail.set_content(".tm_properties", "projectSetting = readMe\nTM_GIT = \"/EVIL/git\"\n");
	trust_guard_t guard(false);

	OAK_ASSERT_EQ(settings_for_path(jail.path("file.cc")).get("projectSetting"), "readMe");
}

void test_an_untrusted_project_file_may_not_set_the_environment ()
{
	test::jail_t jail;
	jail.set_content(".tm_properties", "projectSetting = readMe\nTM_GIT = \"/EVIL/git\"\nPATH = \"/EVIL:$PATH\"\n");
	trust_guard_t guard(false);

	auto const variables = variables_for_path(std::map<std::string, std::string>{ { "PATH", "/usr/bin" } }, jail.path("file.cc"));
	OAK_ASSERT_EQ(variables.find("PATH")->second, "/usr/bin");
	OAK_ASSERT_EQ((bool)(variables.find("TM_GIT") == variables.end()), true);
}

// Trust means trust. A folder the user has vouched for gets what it asks for,
// including the two that are dangerous — that is what being asked was *for*, and
// a "trusted" folder that still cannot set TM_GIT would make the prompt a lie.
void test_a_trusted_project_file_may_set_the_environment ()
{
	test::jail_t jail;
	jail.set_content(".tm_properties", "TM_GIT = \"/mine/git\"\nPATH = \"/mine:$PATH\"\n");
	trust_guard_t guard(true);

	auto const variables = variables_for_path(std::map<std::string, std::string>{ { "PATH", "/usr/bin" } }, jail.path("file.cc"));
	OAK_ASSERT_EQ(variables.find("TM_GIT")->second, "/mine/git");
	OAK_ASSERT_EQ(variables.find("PATH")->second, "/mine:/usr/bin");
}

// Nothing is trusted until the application installs a predicate. A code path
// that forgets to must get the safe answer, not the convenient one.
void test_nothing_is_trusted_by_default ()
{
	test::jail_t jail;
	jail.set_content(".tm_properties", "TM_GIT = \"/EVIL/git\"\n");
	settings_t::set_trust_predicate(nullptr);   // as if the application never spoke

	auto const variables = variables_for_path(std::map<std::string, std::string>(), jail.path("file.cc"));
	OAK_ASSERT_EQ((bool)(variables.find("TM_GIT") == variables.end()), true);
}

// The user's own settings are not a project file and are not subject to trust —
// they cannot be written by a repository. Without this the rule could quietly
// become "deny the environment everywhere", which is a different and much worse
// change.
void test_the_users_own_settings_are_not_subject_to_trust ()
{
	test::jail_t jail;
	jail.set_content("global.tmProperties", "PATH = \"/mine:$PATH\"\nTM_GIT = \"/mine/git\"\n");
	settings_t::set_global_settings_path(jail.path("global.tmProperties"));
	trust_guard_t guard(false);

	auto const variables = variables_for_path(std::map<std::string, std::string>{ { "PATH", "/usr/bin" } }, jail.path("file.cc"));
	OAK_ASSERT_EQ(variables.find("PATH")->second, "/mine:/usr/bin");
	OAK_ASSERT_EQ(variables.find("TM_GIT")->second, "/mine/git");

	settings_t::set_global_settings_path(NULL_STR);
}

// `~/.tm_properties` is the user's own, and the walk reaches it because it stops
// at home. It must not be subject to trust: a repository cannot write it, and if
// it were untrusted every existing setup using it would silently lose its
// environment with no folder to trust, because it is not in one.
//
// Written against the real home path rather than a jail, because the rule is
// literally "is this that file" and a jail would test a different string. It
// reads whatever is actually there, so it asserts a property that holds either
// way: whatever the home file sets, an untrusted predicate does not change it.
void test_the_home_properties_file_is_not_subject_to_trust ()
{
	std::string const homeFile = path::join(path::home(), ".tm_properties");

	settings_t::set_trust_predicate([](std::string const&){ return true; });
	auto const whenTrusting = variables_for_path(std::map<std::string, std::string>(), path::join(path::home(), "file.cc"));

	settings_t::set_trust_predicate([](std::string const&){ return false; });
	auto const whenNotTrusting = variables_for_path(std::map<std::string, std::string>(), path::join(path::home(), "file.cc"));

	settings_t::set_trust_predicate(nullptr);

	OAK_ASSERT_EQ((bool)(whenTrusting == whenNotTrusting), true);
}

// `CWD` and `TM_PROPERTIES_PATH` are not the file's to set: parse_sections adds
// both to the top of every `.tm_properties` it reads — the file's own directory,
// and the list of property files that applied. They say where the file *is*, not
// what it asks for, so they cannot select a program and trust has nothing to
// withhold from them. The trusted half of each test is the control: it shows the
// fixture measures what it claims, so a failure in the untrusted half is about
// trust and nothing else.
void test_an_untrusted_project_file_can_still_refer_to_its_own_directory ()
{
	test::jail_t jail;
	jail.set_content(".tm_properties", "projectDirectory = \"$CWD/sub\"\n");

	{
		trust_guard_t guard(true);
		OAK_ASSERT_EQ(settings_for_path(jail.path("file.cc")).get("projectDirectory"), jail.path("sub"));
	}
	{
		trust_guard_t guard(false);
		OAK_ASSERT_EQ(settings_for_path(jail.path("file.cc")).get("projectDirectory"), jail.path("sub"));
	}
}

void test_an_untrusted_project_file_is_still_listed_in_TM_PROPERTIES_PATH ()
{
	test::jail_t jail;
	jail.set_content(".tm_properties", "projectSetting = readMe\n");

	auto listed = [&jail](){
		auto const variables = variables_for_path(std::map<std::string, std::string>{ }, jail.path("file.cc"));
		auto const it = variables.find("TM_PROPERTIES_PATH");
		return it != variables.end() && it->second.find(jail.path(".tm_properties")) != std::string::npos;
	};
	{
		trust_guard_t guard(true);
		OAK_ASSERT_EQ(listed(), true);
	}
	{
		trust_guard_t guard(false);
		OAK_ASSERT_EQ(listed(), true);
	}
}

// And the exemption is by origin, not by name. A file that writes `CWD` itself is
// making an uppercase assignment like any other, and an untrusted one is refused.
void test_an_untrusted_project_file_may_not_set_CWD_itself ()
{
	test::jail_t jail;
	jail.set_content(".tm_properties", "CWD = \"/EVIL\"\nprojectDirectory = \"$CWD/sub\"\n");
	trust_guard_t guard(false);

	OAK_ASSERT_EQ(settings_for_path(jail.path("file.cc")).get("projectDirectory"), jail.path("sub"));
}
