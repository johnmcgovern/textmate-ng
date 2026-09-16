#include "../src/drivers/api.h"
#include <scm/scm.h>
#include <test/jail.h>
#include <io/path.h>
#include <io/exec.h>
#include <text/format.h>

void test_basic_status ()
{
	test::jail_t jail;

	// The driver can only be exercised where Mercurial is installed, which it is
	// not on the CI image nor on the development machine as of 2026-09-15. An
	// absent tool is a skip with its reason printed, not a failure: a red test
	// that says "install hg" tells CI nothing about the code.
	std::string const hg = scm::find_executable("hg", "TM_HG");
	if(hg == NULL_STR)
	{
		fprintf(stderr, "test_basic_status (hg): skipped, no hg executable on PATH (set TM_HG or install mercurial)\n");
		return;
	}

	std::string const wcPath = jail.path();
	std::string const script = text::format("{ cd '%1$s' && '%2$s' init && touch {clean,ignored,modified,added,missing,untracked}.txt && echo ignored.txt > .hgignore && '%2$s' add {.hgignore,{clean,modified,missing}.txt} && '%2$s' commit -u 'Test User' -m 'Initial commit' && '%2$s' add added.txt && rm missing.txt && echo foo > modified.txt; } >/dev/null", wcPath.c_str(), hg.c_str());
	if(io::exec("/bin/sh", "-c", script.c_str(), nullptr) == NULL_STR)
		OAK_FAIL("error in setup: " + script);

	if(auto info = scm::info(jail.path()))
	{
		wait_for_status(info);

		auto vars = info->scm_variables();
		OAK_ASSERT_EQ(vars["TM_SCM_NAME"],   "hg");
		OAK_ASSERT_EQ(vars["TM_SCM_BRANCH"], "default");

		OAK_ASSERT_EQ(info->status(jail.path("clean.txt")),     scm::status::none);
		OAK_ASSERT_EQ(info->status(jail.path("ignored.txt")),   scm::status::ignored);
		OAK_ASSERT_EQ(info->status(jail.path("modified.txt")),  scm::status::modified);
		OAK_ASSERT_EQ(info->status(jail.path("added.txt")),     scm::status::added);
		OAK_ASSERT_EQ(info->status(jail.path("missing.txt")),   scm::status::deleted);
		OAK_ASSERT_EQ(info->status(jail.path("untracked.txt")), scm::status::unversioned);
	}
	else
	{
		OAK_FAIL("error getting wc: " + wcPath);
	}
}
