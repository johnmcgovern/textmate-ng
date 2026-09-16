#include <file/save.h>
#include <io/path.h>
#include <text/hexdump.h>
#include <test/jail.h>
#include <test/bundle_index.h>

// test_export_filter needs a bundle command with an export semantic class,
// which only an installed bundle would supply. A fixture provides one that
// hashes the document, scoped to the file's extension through attr.rev-path.
// It is a *binary* export filter: the digest is raw bytes, and a text export
// filter's output goes through the encoder next, which refuses them as
// invalid UTF-8 — a save that fails with no message, which is how this was
// found. Binary export runs after encoding, and writes what it is given.
void setup_export_filter ()
{
	test::bundle_index_t index;
	// The command needs a real newline after the shebang: written as \n inside
	// the plist it stays two characters, and execve refuses "#!/bin/sh\nopenssl…"
	// as an interpreter path with "Exec format error".
	index.add(bundles::kItemTypeCommand, "{ name = 'SHA-1 on save'; semanticClass = 'callback.document.binary-export'; scope = 'attr.rev-path.sha1'; input = document; inputFormat = text; outputLocation = replaceDocument; outputFormat = text; command = '#!/bin/sh\nopenssl dgst -sha1 -binary'; }");
	index.commit();
}

struct stall_t : file::save_callback_t
{
	stall_t (bool* success = nullptr, std::string const& path = NULL_STR, std::string const& encoding = NULL_STR) : _success(success), _path(path), _encoding(encoding)
	{
		_run_loop = CFRunLoopGetCurrent();
	}

	void select_path (std::string const& path, io::bytes_ptr content, file::save_context_ptr context)
	{
		if(_path != NULL_STR)
			context->set_path(_path);
	}

	void select_charset (std::string const& path, io::bytes_ptr content, std::string const& charset, file::save_context_ptr context)
	{
		if(_encoding != kCharsetNoEncoding)
			context->set_charset(_encoding);
	}

	void did_save (std::string const& path, io::bytes_ptr content, encoding::type const& encoding, bool success, std::string const& message, oak::uuid_t const& filter)
	{
		// A failed save says why here and nowhere else; print it so a failing test
		// names the cause instead of "Assertion failed: didSave".
		if(!success)
			fprintf(stderr, "save of %s failed: %s\n", path.c_str(), message.c_str());
		if(_success)
			*_success = success;
		_should_wait = false;
		CFRunLoopStop(_run_loop);
	}

	void wait ()
	{
		while(_should_wait)
			CFRunLoopRun();
	}

private:
	bool* _success;
	std::string _path;
	std::string _encoding;
	CFRunLoopRef _run_loop;
	bool _should_wait = true;
};

static std::string sha1 (std::string const& src)
{
	char md[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1((unsigned char*)src.data(), src.size(), (unsigned char*)md);
	return std::string(md, md + sizeof(md));
}

void test_save ()
{
	test::jail_t jail;

	bool success        = false;
	std::string path    = jail.path("test.cc");
	std::string content = "// a comment\n";

	auto cb = std::make_shared<stall_t>(&success);
	file::save(path, cb, osx::authorization_t(), io::bytes_ptr(new io::bytes_t(content)), std::map<std::string, std::string>(), encoding::type("\n", "UTF-8"), std::vector<oak::uuid_t>() /* binary import filters */, std::vector<oak::uuid_t>() /* text import filters */);
	cb->wait();

	OAK_ASSERT_EQ(success, true);
	OAK_ASSERT_EQ(path::content(path), content);
}

void test_save_untitled ()
{
	test::jail_t jail;

	bool success        = false;
	std::string path    = jail.path("test.cc");
	std::string content = "// a comment\n";

	auto cb = std::make_shared<stall_t>(&success, path);
	file::save(NULL_STR, cb, osx::authorization_t(), io::bytes_ptr(new io::bytes_t(content)), std::map<std::string, std::string>(), encoding::type("\n", "UTF-8"), std::vector<oak::uuid_t>() /* binary import filters */, std::vector<oak::uuid_t>() /* text import filters */);
	cb->wait();

	OAK_ASSERT_EQ(success, true);
	OAK_ASSERT_EQ(path::content(path), content);
}

void test_save_untitled_failure ()
{
	test::jail_t jail;

	bool success        = false;
	std::string content = "// a comment\n";

	auto cb = std::make_shared<stall_t>(&success);
	file::save(NULL_STR, cb, osx::authorization_t(), io::bytes_ptr(new io::bytes_t(content)), std::map<std::string, std::string>(), encoding::type("\n", "UTF-8"), std::vector<oak::uuid_t>() /* binary import filters */, std::vector<oak::uuid_t>() /* text import filters */);
	cb->wait();

	OAK_ASSERT_EQ(success, false);
}

void test_save_translit ()
{
	test::jail_t jail;

	bool success        = false;
	std::string path    = jail.path("test.txt");
	std::string content = "Æblegrød…\n";

	auto cb = std::make_shared<stall_t>(&success, path, "ASCII//TRANSLIT");
	file::save(path, cb, osx::authorization_t(), io::bytes_ptr(new io::bytes_t(content)), std::map<std::string, std::string>(), encoding::type("\n", "ASCII"), std::vector<oak::uuid_t>() /* binary import filters */, std::vector<oak::uuid_t>() /* text import filters */);
	cb->wait();

	OAK_ASSERT_EQ(success, true);

	// What //TRANSLIT makes of ø and … is libiconv's table, and Apple's has
	// changed since this expected "AEblegrod...": today it writes "AEblegro......"
	// and reports four invalid characters. What is ours to assert is that the
	// save succeeded through transliteration (without it, an ASCII save of this
	// content fails — see test_save_encoding_failure), that Æ became AE, and
	// that nothing non-ASCII reached the file.
	std::string const saved = path::content(path);
	OAK_ASSERT(saved.compare(0, 7, "AEblegr") == 0);
	OAK_ASSERT(saved.back() == '\n');
	for(char ch : saved)
		OAK_ASSERT((unsigned char)ch < 0x80);
}

void test_save_encoding_failure ()
{
	test::jail_t jail;

	bool success        = false;
	std::string path    = jail.path("test.txt");
	std::string content = "Æblegrød…\n";

	auto cb = std::make_shared<stall_t>(&success, path);
	file::save(path, cb, osx::authorization_t(), io::bytes_ptr(new io::bytes_t(content)), std::map<std::string, std::string>(), encoding::type("\n", "ASCII"), std::vector<oak::uuid_t>() /* binary import filters */, std::vector<oak::uuid_t>() /* text import filters */);
	cb->wait();

	OAK_ASSERT_EQ(success, false);
}

void test_export_filter ()
{
	test::jail_t jail;
	std::string content = "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.";

	bool didSave = false;
	auto cb = std::make_shared<stall_t>(&didSave);
	file::save(jail.path("file.sha1"), cb, osx::authorization_t(), io::bytes_ptr(new io::bytes_t(content)), std::map<std::string, std::string>(), encoding::type("\n", "UTF-8"), std::vector<oak::uuid_t>() /* binary import filters */, std::vector<oak::uuid_t>() /* text import filters */);
	cb->wait();

	OAK_ASSERT(didSave);
	OAK_ASSERT_EQ(path::content(jail.path("file.sha1")), sha1(content));
}
