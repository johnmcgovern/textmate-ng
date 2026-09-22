// tm_fuzz — a mutational fuzzer for the parsers that read bytes a user did not
// write: the ASCII property-list reader, the encoding classifier and
// transcoder, and the grammar engine (over both the text it colours and the
// grammar it is given). Built with -fsanitize=address,undefined by bin/fuzz,
// which also assembles a corpus and runs every target in turn.
//
// Why not libFuzzer: no toolchain on the build machine ships it (Apple's clang
// has no libclang_rt.fuzzer, and there is no Homebrew LLVM), and pulling one
// in for four twenty-line targets is a bigger dependency than the targets.
// This is not coverage-guided; it mutates corpus entries at random and relies
// on the sanitizers to turn a memory error into an abort. Coverage feedback
// (-fsanitize-coverage, which Apple's clang does support) is the obvious next
// step if a target stops finding anything.
//
// A finding is a process death: the sanitizer prints its report and aborts,
// and the input that caused it is still on disk at <out>/current.<target>,
// because it is written before every run and removed only after a clean one.
// A hang is a finding too: each run is under an alarm, and SIGALRM aborts with
// the input preserved the same way.
//
//   tm_fuzz <target> --corpus DIR --out DIR [--seconds N] [--seed N]
//                    [--max-size N] [--grammar FILE] [--timeout N]
//   tm_fuzz <target> --replay FILE [--grammar FILE] [--timeout N]
//
// Targets: ascii, encoding, grammar, grammar-plist. --replay runs one saved
// input (a preserved current.<target>) through the target once and exits,
// which is how a finding is reproduced under a debugger or with
// UBSAN_OPTIONS=print_stacktrace=1.

#include <plist/plist.h>
#include <plist/ascii.h>
#include <parse/grammar.h>
#include <parse/parse.h>
#include <encoding/encoding.h>
#include <settings/parser.h>
#include <regexp/format_string.h>
#include <file/encoding.h>
#include <file/bytes.h>
#include <test/bundle_index.h>

#include <dirent.h>
#include <sys/stat.h>
#include <signal.h>
#include <unistd.h>

// ============
// = Corpus   =
// ============

static std::vector<std::string> read_corpus (std::string const& dir, size_t maxSize)
{
	std::vector<std::string> res;
	if(DIR* d = opendir(dir.c_str()))
	{
		while(dirent* entry = readdir(d))
		{
			if(entry->d_name[0] == '.')
				continue;
			std::string path = dir + "/" + entry->d_name;
			struct stat st;
			if(stat(path.c_str(), &st) != 0 || !S_ISREG(st.st_mode) || (size_t)st.st_size > maxSize)
				continue;
			if(FILE* fp = fopen(path.c_str(), "rb"))
			{
				std::string content(st.st_size, '\0');
				size_t n = fread(&content[0], 1, content.size(), fp);
				fclose(fp);
				content.resize(n);
				res.push_back(content);
			}
		}
		closedir(d);
	}
	return res;
}

static std::string replayFileContent (std::string const& path)
{
	std::string content;
	if(FILE* fp = fopen(path.c_str(), "rb"))
	{
		char buf[4096];
		while(size_t n = fread(buf, 1, sizeof(buf), fp))
			content.append(buf, n);
		fclose(fp);
	}
	return content;
}

static void write_file (std::string const& path, std::string const& content)
{
	if(FILE* fp = fopen(path.c_str(), "wb"))
	{
		fwrite(content.data(), 1, content.size(), fp);
		fclose(fp);
	}
}

// ============
// = Mutation =
// ============

struct rng_t
{
	rng_t (uint64_t seed) : _state(seed ? seed : 0x9E3779B97F4A7C15ULL) { }
	uint64_t next ()
	{
		_state ^= _state << 13;
		_state ^= _state >> 7;
		_state ^= _state << 17;
		return _state;
	}
	size_t below (size_t n) { return n ? next() % n : 0; }
private:
	uint64_t _state;
};

static char const* const kInterestingBytes = "\x00\x01\x7F\x80\xFF\n\r\t \"'\\{}()[]<>;=,:/*+?.^$|#&%";

static std::string mutate (std::string input, std::vector<std::string> const& corpus, rng_t& rng, size_t maxSize)
{
	size_t const rounds = 1 + rng.below(4);
	for(size_t round = 0; round < rounds; ++round)
	{
		switch(rng.below(10))
		{
			case 0: // flip a bit
				if(!input.empty())
					input[rng.below(input.size())] ^= (char)(1 << rng.below(8));
			break;

			case 1: // set a byte to something interesting
				if(!input.empty())
					input[rng.below(input.size())] = kInterestingBytes[rng.below(strlen(kInterestingBytes) + 1)];
			break;

			case 2: // set a byte to anything
				if(!input.empty())
					input[rng.below(input.size())] = (char)rng.below(256);
			break;

			case 3: // insert a byte
				if(input.size() < maxSize)
					input.insert(rng.below(input.size() + 1), 1, (char)rng.below(256));
			break;

			case 4: // delete a range
				if(!input.empty())
				{
					size_t from = rng.below(input.size());
					size_t len  = 1 + rng.below(std::min<size_t>(64, input.size() - from));
					input.erase(from, len);
				}
			break;

			case 5: // duplicate a range
				if(!input.empty() && input.size() < maxSize)
				{
					size_t from = rng.below(input.size());
					size_t len  = 1 + rng.below(std::min<size_t>(256, input.size() - from));
					input.insert(rng.below(input.size() + 1), input.substr(from, len));
				}
			break;

			case 6: // splice with another corpus entry
				if(!corpus.empty())
				{
					std::string const& other = corpus[rng.below(corpus.size())];
					if(!other.empty())
					{
						size_t from = rng.below(other.size());
						size_t len  = 1 + rng.below(std::min<size_t>(512, other.size() - from));
						size_t at   = rng.below(input.size() + 1);
						input.replace(at, std::min(len, input.size() - at), other.substr(from, len));
					}
				}
			break;

			case 7: // truncate
				if(!input.empty())
					input.resize(rng.below(input.size()));
			break;

			case 8: // repeat a byte many times (repetition blow-ups)
				if(input.size() < maxSize)
					input.insert(rng.below(input.size() + 1), 1 + rng.below(1024), kInterestingBytes[rng.below(strlen(kInterestingBytes))]);
			break;

			case 9: // insert a small integer in text form
				if(input.size() < maxSize)
				{
					static char const* const numbers[] = { "0", "-1", "1", "255", "256", "65535", "65536", "2147483647", "2147483648", "-2147483648", "4294967295", "4294967296", "9223372036854775807", "18446744073709551615" };
					input.insert(rng.below(input.size() + 1), numbers[rng.below(sizeof(numbers) / sizeof(numbers[0]))]);
				}
			break;
		}
	}
	if(input.size() > maxSize)
		input.resize(maxSize);
	return input;
}

// ===========
// = Targets =
// ===========

static void run_ascii (std::string const& input)
{
	bool success = false;
	plist::any_t plist = plist::parse_ascii(input, &success);
	if(success)
		to_s(plist, plist::kStandard);
}

static std::vector<std::string> const& transcode_charsets ()
{
	static std::vector<std::string> const charsets = { kCharsetUTF8, kCharsetUTF16LE, kCharsetUTF16BE, kCharsetUTF32LE, kCharsetUTF32BE, "ISO-8859-1", "WINDOWS-1252", "SHIFT_JIS", "GB18030", "EUC-KR", "MACROMAN" };
	return charsets;
}

// `.tm_properties` — the only parser here whose input arrives by cloning a
// repository rather than by opening a file the user chose. It is read by walking
// up from the document, so a checkout brings its own, and on 2026-09-22 one of
// them turned out to be able to choose which programs bundle commands ran.
//
// Two layers, because the parser alone is the smaller half. `parse_ini` splits
// sections and assignments; `format_string::expand` then substitutes `${VAR}`
// in every value, which is where a self-referencing or deeply nested expansion
// would go wrong. The environment handed in is deliberately small and
// self-referential, so `${a}` resolves to something that mentions `${a}`.
static void run_settings (std::string const& input)
{
	ini_file_t iniFile("fuzz.tm_properties");
	parse_ini(input.data(), input.data() + input.size(), iniFile);

	std::map<std::string, std::string> environment = {
		{ "a", "${b}" },
		{ "b", "${a}" },
		{ "PATH", "/usr/bin" },
		{ "TM_FUZZ", "x" },
	};

	for(auto const& section : iniFile.sections)
	{
		for(auto const& name : section.names)
			format_string::expand(name, environment);
		for(auto const& value : section.values)
			environment[value.name] = format_string::expand(value.value, environment);
	}
}

static void run_encoding (std::string const& input)
{
	encoding::charset_from_bom(input.begin(), input.end());

	for(auto const& charset : encoding::charsets())
		encoding::probability(input.data(), input.data() + input.size(), charset);

	auto bytes = std::make_shared<io::bytes_t>(input);
	for(auto const& charset : transcode_charsets())
		encoding::convert(bytes, charset, kCharsetUTF8);
}

static void parse_text (parse::grammar_ptr const& grammar, std::string const& buf)
{
	parse::stack_ptr state = grammar->seed();
	for(std::string::size_type i = 0; i != buf.size(); )
	{
		auto eol = buf.find('\n', i);
		eol = eol != std::string::npos ? ++eol : buf.size();

		std::map<size_t, scope::scope_t> scopes;
		state = parse::parse(buf.data() + i, buf.data() + eol, state, scopes, i == 0);
		i = eol;
	}
}

static plist::dictionary_t load_grammar_plist (std::string const& path)
{
	plist::dictionary_t res = plist::load(path);
	if(res.empty())
	{
		fprintf(stderr, "tm_fuzz: could not load grammar ‘%s’\n", path.c_str());
		exit(2);
	}
	return res;
}

static parse::grammar_ptr grammar_from_plist (plist::dictionary_t const& plist)
{
	// A fresh index each time: bundles::set_index replaces the process-wide one,
	// and parse_grammar resolves includes through it.
	static std::unique_ptr<test::bundle_index_t> index;
	index.reset(new test::bundle_index_t);
	bundles::item_ptr item = index->add(bundles::kItemTypeGrammar, plist);
	index->commit();
	return parse::parse_grammar(item);
}

// ========
// = Main =
// ========

static std::string current_path;

static void on_alarm (int)
{
	char const msg[] = "tm_fuzz: timeout — the input is preserved at the path printed at start\n";
	write(2, msg, sizeof(msg) - 1);
	abort();
}

static void usage (FILE* io)
{
	fprintf(io, "usage: tm_fuzz <ascii|encoding|grammar|grammar-plist> --corpus DIR --out DIR [--seconds N] [--seed N] [--max-size N] [--grammar FILE] [--timeout N]\n");
}

int main (int argc, char* argv[])
{
	if(argc < 2)
	{
		usage(stderr);
		return 2;
	}

	std::string target = argv[1];
	std::string corpusDir, outDir, grammarPath, replayPath;
	double seconds = 60;
	uint64_t seed = (uint64_t)time(nullptr) ^ (uint64_t)getpid();
	size_t maxSize = 64 * 1024;
	unsigned timeoutSeconds = 10;

	for(int i = 2; i + 1 < argc; i += 2)
	{
		std::string flag = argv[i], value = argv[i+1];
		if(flag == "--corpus")        corpusDir = value;
		else if(flag == "--out")      outDir = value;
		else if(flag == "--seconds")  seconds = atof(value.c_str());
		else if(flag == "--seed")     seed = strtoull(value.c_str(), nullptr, 10);
		else if(flag == "--max-size") maxSize = strtoull(value.c_str(), nullptr, 10);
		else if(flag == "--grammar")  grammarPath = value;
		else if(flag == "--timeout")  timeoutSeconds = (unsigned)atoi(value.c_str());
		else if(flag == "--replay")   replayPath = value;
		else { usage(stderr); return 2; }
	}

	if(replayPath.empty() && (corpusDir.empty() || outDir.empty()))
	{
		usage(stderr);
		return 2;
	}

	std::vector<std::string> corpus;
	if(!replayPath.empty())
	{
		std::string content = replayFileContent(replayPath);
		if(!content.empty())
			corpus.push_back(content);
		if(corpus.empty())
		{
			fprintf(stderr, "tm_fuzz: could not read ‘%s’\n", replayPath.c_str());
			return 2;
		}
		outDir  = "/tmp";
		seconds = 0;
	}
	else
	{
		corpus = read_corpus(corpusDir, maxSize);
	}
	if(corpus.empty())
	{
		fprintf(stderr, "tm_fuzz: no corpus entries under %zu bytes in ‘%s’\n", maxSize, corpusDir.c_str());
		return 2;
	}

	// The ascii target wants ASCII property lists; the corpus on a real machine
	// is mostly binary and XML ones (installed bundles), so convert those.
	if(target == "ascii")
	{
		for(auto& entry : corpus)
		{
			if(entry.compare(0, 6, "bplist") == 0 || entry.compare(0, 5, "<?xml") == 0)
			{
				plist::any_t plist = plist::parse(entry);
				std::string ascii = to_s(plist, plist::kStandard);
				if(!ascii.empty())
					entry = ascii;
			}
		}
	}

	parse::grammar_ptr grammar;
	plist::dictionary_t grammarPlist;
	std::string grammarAscii;
	if(target == "grammar" || target == "grammar-plist")
	{
		if(grammarPath.empty())
		{
			fprintf(stderr, "tm_fuzz: %s needs --grammar FILE\n", target.c_str());
			return 2;
		}
		grammarPlist = load_grammar_plist(grammarPath);
		grammar      = grammar_from_plist(grammarPlist);
		grammarAscii = to_s(plist::any_t(grammarPlist), plist::kStandard);
		if(!grammar)
		{
			fprintf(stderr, "tm_fuzz: grammar did not compile\n");
			return 2;
		}
	}

	mkdir(outDir.c_str(), 0755);
	current_path = outDir + "/current." + target;
	signal(SIGALRM, on_alarm);

	rng_t rng(seed);
	fprintf(stderr, "tm_fuzz %s: %zu corpus entries, %.0f s, seed %llu, max %zu bytes, timeout %u s; a finding leaves %s\n",
		target.c_str(), corpus.size(), seconds, (unsigned long long)seed, maxSize, timeoutSeconds, current_path.c_str());

	// Every corpus entry once, unmutated, first: a crash there is a crash on a
	// real file, which is the most important kind.
	size_t runs = 0;
	auto const start = std::chrono::steady_clock::now();
	auto elapsed = [&]{ return std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count(); };

	auto run_one = [&](std::string const& input){
		write_file(current_path, input);
		alarm(timeoutSeconds);
		if(target == "ascii")               run_ascii(input);
		else if(target == "encoding")       run_encoding(input);
		else if(target == "settings")       run_settings(input);
		else if(target == "grammar")        parse_text(grammar, input);
		else if(target == "grammar-plist")
		{
			bool success = false;
			plist::any_t plist = plist::parse_ascii(input, &success);
			if(success)
			{
				if(plist::dictionary_t const* dict = boost::get<plist::dictionary_t>(&plist))
				{
					if(parse::grammar_ptr g = grammar_from_plist(*dict))
						parse_text(g, corpus.front());
				}
			}
		}
		alarm(0);
		++runs;
	};

	if(target == "grammar-plist" && !replayPath.empty())
	{
		// The replayed file is a grammar; run it over the loaded grammar's own
		// ASCII text as the sample, which is as good a C-like input as any.
		std::string const sample = grammarAscii;
		corpus.assign(1, sample);
		run_one(replayFileContent(replayPath));
	}
	else if(target == "grammar-plist")
	{
		// The thing mutated is the grammar; the corpus supplies the text it runs over.
		std::vector<std::string> grammarCorpus = { grammarAscii };
		run_one(grammarAscii);
		while(elapsed() < seconds)
			run_one(mutate(grammarAscii, grammarCorpus, rng, std::max(maxSize, grammarAscii.size() + 4096)));
	}
	else
	{
		for(auto const& entry : corpus)
			run_one(entry);
		while(elapsed() < seconds)
			run_one(mutate(corpus[rng.below(corpus.size())], corpus, rng, maxSize));
	}

	unlink(current_path.c_str());
	fprintf(stderr, "tm_fuzz %s: %zu runs in %.0f s (%.0f/s), no findings\n", target.c_str(), runs, elapsed(), runs / std::max(elapsed(), 0.001));
	return 0;
}
