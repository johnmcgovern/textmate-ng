#include <file/type.h>
#include <plist/plist.h>
#include <test/jail.h>
#include <regexp/glob.h>
#include <settings/settings.h>
#include <test/bundle_index.h>

// Both tests resolve grammars, which only installed bundles would supply. A
// fixture index provides one grammar per scope the assertions name, with the
// extensions and first-line match the real bundles carry. path::rank prefers
// the longest extension at a '.', '_' or '/' boundary, which is what makes
// foo_spec.rb RSpec rather than Ruby and CMakeLists.txt CMake rather than text.
void setup_grammars ()
{
	test::bundle_index_t index;
	index.add(bundles::kItemTypeGrammar, "{ name = 'XML Property List'; scopeName = 'source.xml.plist'; firstLineMatch = '^<[?]xml'; }");
	index.add(bundles::kItemTypeGrammar, "{ name = 'Property List';     scopeName = 'source.plist';       fileTypes = ( plist ); }");
	index.add(bundles::kItemTypeGrammar, "{ name = 'Ruby';              scopeName = 'source.ruby';        fileTypes = ( rb ); }");
	index.add(bundles::kItemTypeGrammar, "{ name = 'RSpec';             scopeName = 'source.ruby.rspec';  fileTypes = ( 'spec.rb' ); }");
	index.add(bundles::kItemTypeGrammar, "{ name = 'CMake';             scopeName = 'source.cmake';       fileTypes = ( 'CMakeLists.txt' ); }");
	index.add(bundles::kItemTypeGrammar, "{ name = 'Git Config';        scopeName = 'source.config.git';  fileTypes = ( '.git/config' ); }");
	index.add(bundles::kItemTypeGrammar, "{ name = 'Plain Text';        scopeName = 'text.plain';         fileTypes = ( txt ); }");
	index.commit();
}

void test_file_type ()
{
	test::jail_t jail;

	std::string const xmlPlist = jail.path("xml.plist");
	OAK_ASSERT(plist::save(xmlPlist, true, plist::kPlistFormatXML));
	OAK_ASSERT_EQ(file::type(xmlPlist, io::bytes_ptr(new io::bytes_t(path::content(xmlPlist)))), "source.xml.plist");
	OAK_ASSERT_EQ(file::type(jail.path("ascii.plist"), io::bytes_ptr(new io::bytes_t("{ foo = 'bar'; }"))), "source.plist");
}

void test_create_glob ()
{
	test::jail_t jail;
	settings_t::set_default_settings_path(jail.path("default"));
	settings_t::set_global_settings_path(jail.path("global"));

	OAK_ASSERT_EQ(file::type_from_path("/path/to/foo.rb"),         "source.ruby");
	OAK_ASSERT_EQ(file::type_from_path("/path/to/foo_spec.rb"),    "source.ruby.rspec");
	OAK_ASSERT_EQ(file::type_from_path("/path/to/CMakeLists.txt"), "source.cmake");
	OAK_ASSERT_EQ(file::type_from_path("/path/to/.git/config"),    "source.config.git");
	OAK_ASSERT_EQ(file::type_from_path("/path/to/foo.txt"),        "text.plain");
	OAK_ASSERT_EQ(file::type_from_path("/path/to/foo.config"),     NULL_STR);
	OAK_ASSERT_EQ(file::type_from_path("/path/to/config"),         NULL_STR);

	file::set_type("/path/to/foo_spec.rb",    "*_spec.rb");
	file::set_type("/path/to/foo.rb",         "*.rb");
	file::set_type("/path/to/CMakeLists.txt", "CMakeLists.txt");
	file::set_type("/path/to/foo.txt",        "*.txt");
	file::set_type("/path/to/.git/config",    ".git/config");
	file::set_type("/path/to/foo.config",     "*.config");
	file::set_type("/path/to/config",         "config");
	file::set_type("/path/to/.config",        ".config");
	file::set_type("_config",                 "_config");
	file::set_type("foo.xyz_rb",              "*.xyz_rb");
	file::set_type("Makefile",                "Makefile");
	file::set_type("/path/to/foo.erb",        "*.erb");
	file::set_type("/path/to/foo.css.erb",    "*.css.erb");
	file::set_type("/path/to/foo.html.erb",   "*.html.erb");
	file::set_type("/path/to/foo_v1.0.dmg",   "*.dmg");

	OAK_ASSERT_EQ(settings_for_path("/foo/bar_spec.rb"      ).get(kSettingsFileTypeKey, "unset"), "*_spec.rb");
	OAK_ASSERT_EQ(settings_for_path("/foo/bar.rb"           ).get(kSettingsFileTypeKey, "unset"), "*.rb");
	OAK_ASSERT_EQ(settings_for_path("/foo/bar.txt"          ).get(kSettingsFileTypeKey, "unset"), "*.txt");
	OAK_ASSERT_EQ(settings_for_path("/foo/bar.config"       ).get(kSettingsFileTypeKey, "unset"), "*.config");
	OAK_ASSERT_EQ(settings_for_path("/foo/CMakeLists.txt"   ).get(kSettingsFileTypeKey, "unset"), "CMakeLists.txt");
	OAK_ASSERT_EQ(settings_for_path("/foo/.git/config"      ).get(kSettingsFileTypeKey, "unset"), ".git/config");
	OAK_ASSERT_EQ(settings_for_path("/foo/config"           ).get(kSettingsFileTypeKey, "unset"), "config");
	OAK_ASSERT_EQ(settings_for_path("/foo/.config"          ).get(kSettingsFileTypeKey, "unset"), ".config");
	OAK_ASSERT_EQ(settings_for_path("/foo/_config"          ).get(kSettingsFileTypeKey, "unset"), "_config");
	OAK_ASSERT_EQ(settings_for_path("/foo/bar.git/config"   ).get(kSettingsFileTypeKey, "unset"), "config");
	OAK_ASSERT_EQ(settings_for_path("/foo/bar_config"       ).get(kSettingsFileTypeKey, "unset"), "unset");
	OAK_ASSERT_EQ(settings_for_path("/foo/barCMakeLists.txt").get(kSettingsFileTypeKey, "unset"), "*.txt");
	OAK_ASSERT_EQ(settings_for_path("/foo/Makefile"         ).get(kSettingsFileTypeKey, "unset"), "Makefile");
	OAK_ASSERT_EQ(settings_for_path("/foo/bar.xyz_rb"       ).get(kSettingsFileTypeKey, "unset"), "*.xyz_rb");
	OAK_ASSERT_EQ(settings_for_path("/foo/bar.erb"          ).get(kSettingsFileTypeKey, "unset"), "*.erb");
	OAK_ASSERT_EQ(settings_for_path("/foo/bar.css.erb"      ).get(kSettingsFileTypeKey, "unset"), "*.css.erb");
	OAK_ASSERT_EQ(settings_for_path("/foo/bar.html.erb"     ).get(kSettingsFileTypeKey, "unset"), "*.html.erb");
	OAK_ASSERT_EQ(settings_for_path("/foo/bar.dmg"          ).get(kSettingsFileTypeKey, "unset"), "*.dmg");

	OAK_ASSERT_EQ(settings_for_path("bar_spec.rb"      ).get(kSettingsFileTypeKey, "unset"), "*_spec.rb");
	OAK_ASSERT_EQ(settings_for_path("bar.rb"           ).get(kSettingsFileTypeKey, "unset"), "*.rb");
	OAK_ASSERT_EQ(settings_for_path("bar.txt"          ).get(kSettingsFileTypeKey, "unset"), "*.txt");
	OAK_ASSERT_EQ(settings_for_path("bar.config"       ).get(kSettingsFileTypeKey, "unset"), "*.config");
	OAK_ASSERT_EQ(settings_for_path("CMakeLists.txt"   ).get(kSettingsFileTypeKey, "unset"), "CMakeLists.txt");
	OAK_ASSERT_EQ(settings_for_path(".git/config"      ).get(kSettingsFileTypeKey, "unset"), ".git/config");
	OAK_ASSERT_EQ(settings_for_path("config"           ).get(kSettingsFileTypeKey, "unset"), "config");
	OAK_ASSERT_EQ(settings_for_path(".config"          ).get(kSettingsFileTypeKey, "unset"), ".config");
	OAK_ASSERT_EQ(settings_for_path("_config"          ).get(kSettingsFileTypeKey, "unset"), "_config");
	OAK_ASSERT_EQ(settings_for_path("bar.git/config"   ).get(kSettingsFileTypeKey, "unset"), "config");
	OAK_ASSERT_EQ(settings_for_path("bar_config"       ).get(kSettingsFileTypeKey, "unset"), "unset");
	OAK_ASSERT_EQ(settings_for_path("barCMakeLists.txt").get(kSettingsFileTypeKey, "unset"), "*.txt");
	OAK_ASSERT_EQ(settings_for_path("Makefile"         ).get(kSettingsFileTypeKey, "unset"), "Makefile");
	OAK_ASSERT_EQ(settings_for_path("bar.xyz_rb"       ).get(kSettingsFileTypeKey, "unset"), "*.xyz_rb");
	OAK_ASSERT_EQ(settings_for_path("bar.erb"          ).get(kSettingsFileTypeKey, "unset"), "*.erb");
	OAK_ASSERT_EQ(settings_for_path("bar.css.erb"      ).get(kSettingsFileTypeKey, "unset"), "*.css.erb");
	OAK_ASSERT_EQ(settings_for_path("bar.html.erb"     ).get(kSettingsFileTypeKey, "unset"), "*.html.erb");
	OAK_ASSERT_EQ(settings_for_path("bar.dmg"          ).get(kSettingsFileTypeKey, "unset"), "*.dmg");
}
