#import "HTMLOutputTesting.h"
#import <ns/ns.h>
#import <Cocoa/Cocoa.h>

// Coverage for HOBrowserView's four URL/string helpers, written before the port.
//
// The view itself is 316 lines of WKWebView wiring that needs a real web view and
// a window to say anything about. Its *logic* is these four functions, and all of
// it is the kind that fails quietly: a URL that is rewritten slightly wrong loads
// the wrong page rather than raising.
//
// They were file-static. Reaching them needed a seam, and the seam is class
// methods rather than extern functions on purpose — Swift can call a free
// function but never export one (rule 19), so an extern would have to be renamed
// at port time and take this file with it. See the note beside their definitions.

void setup ()
{
	NSApplicationLoad();
}

static std::string describe (NSURL* url)
{
	return url ? to_s(url.absoluteString) : std::string("«nil»");
}

// ==================================================================
// = IsProtocolRelativeURL                                          =
// ==================================================================

void test_browser_protocol_relative_covers_x_txmt_except_job ()
{
	// Any x-txmt* scheme is protocol-relative...
	OAK_ASSERT_EQ((bool)[HOBrowserView isProtocolRelativeURL:[NSURL URLWithString:@"x-txmt-filehandle://host/path"]], true);
	OAK_ASSERT_EQ((bool)[HOBrowserView isProtocolRelativeURL:[NSURL URLWithString:@"x-txmt://elsewhere/path"]], true);

	// ...except the job host, which is the streaming command output and must be
	// left for the scheme handler to serve.
	OAK_ASSERT_EQ((bool)[HOBrowserView isProtocolRelativeURL:[NSURL URLWithString:@"x-txmt-filehandle://job/1"]], false);

	// An unrelated scheme is not.
	OAK_ASSERT_EQ((bool)[HOBrowserView isProtocolRelativeURL:[NSURL URLWithString:@"https://example.com/"]], false);
}

void test_browser_protocol_relative_treats_a_dotted_missing_host_as_a_domain ()
{
	// `file://example.com/x` almost certainly means `//example.com/x` written by
	// someone who expected the page's own scheme. The test is *has a dot* **and**
	// *does not exist on disk* — both, so a real directory named with a dot at the
	// root still resolves as a file.
	OAK_ASSERT_EQ((bool)[HOBrowserView isProtocolRelativeURL:[NSURL URLWithString:@"file://example.com/index.html"]], true);

	// No dot in the host: not a domain, so not rewritten.
	OAK_ASSERT_EQ((bool)[HOBrowserView isProtocolRelativeURL:[NSURL URLWithString:@"file://localhost/etc/hosts"]], false);

	// No host at all is the ordinary local-file spelling.
	OAK_ASSERT_EQ((bool)[HOBrowserView isProtocolRelativeURL:[NSURL URLWithString:@"file:///etc/hosts"]], false);
}

// ==================================================================
// = RewrittenURL                                                   =
// ==================================================================

void test_browser_rewrites_tm_file_to_a_localhost_file_url ()
{
	NSURL* res = [HOBrowserView rewrittenURL:[NSURL URLWithString:@"tm-file:///etc/hosts"]];
	OAK_ASSERT_EQ(describe(res), std::string("file://localhost/etc/hosts"));
}

void test_browser_rewrite_keeps_the_fragment_and_percent_encodes_the_path ()
{
	// The fragment is carried across explicitly — the replacement URL is rebuilt by
	// string, so the `#` and everything after it survive only because the format
	// puts them back. Dropping that is a one-character mistake that silently loses
	// every anchor link in generated output.
	NSURL* res = [HOBrowserView rewrittenURL:[NSURL URLWithString:@"tm-file:///etc/hosts#anchor"]];
	OAK_ASSERT_EQ(describe(res), std::string("file://localhost/etc/hosts#anchor"));

	// A space in the path has to survive as %20 rather than breaking the URL.
	//
	// The file has to actually exist: a missing one is redirected to the error page
	// *after* the tm-file rewrite, which would hide the encoding this is checking.
	// My first draft of this test used /tmp/two words.html and asserted the
	// unredirected URL — it failed, and the failure was the test, not the code.
	NSString* spacedPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"two words.html"];
	[@"<p>x</p>" writeToFile:spacedPath atomically:YES encoding:NSUTF8StringEncoding error:nullptr];

	NSURL* spaced = [HOBrowserView rewrittenURL:[NSURL URLWithString:[@"tm-file://" stringByAppendingString:[spacedPath stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet]]]];
	std::string const spacedStr = describe(spaced);
	OAK_ASSERT_EQ((bool)(spacedStr.rfind("file://localhost", 0) == 0), true);
	OAK_ASSERT_EQ((bool)(spacedStr.find("two%20words.html") != std::string::npos), true);
	OAK_ASSERT_EQ((bool)(spacedStr.find("error_not_found") != std::string::npos), false);

	[NSFileManager.defaultManager removeItemAtPath:spacedPath error:nullptr];
}

void test_browser_rewrite_redirects_a_missing_file_to_the_error_page ()
{
	// A file URL that does not stat becomes the bundled error page, carrying the
	// path it failed on as a query parameter. Returning it unchanged would show
	// WebKit's own error instead of TextMate's.
	NSURL* res = [HOBrowserView rewrittenURL:[NSURL fileURLWithPath:@"/nonexistent-path-for-tests/page.html"]];
	std::string str = describe(res);
	OAK_ASSERT_EQ((bool)(str.find("error_not_found") != std::string::npos), true);
	OAK_ASSERT_EQ((bool)(str.find("error=1") != std::string::npos), true);
}

void test_browser_rewrite_leaves_an_existing_file_alone ()
{
	// A regular file is loaded as-is: no redirect, same URL back.
	NSURL* url = [NSURL fileURLWithPath:@"/etc/hosts"];
	NSURL* res = [HOBrowserView rewrittenURL:url];
	OAK_ASSERT_EQ(describe(res), describe(url));
}

void test_browser_rewrite_leaves_a_remote_url_alone ()
{
	NSURL* url = [NSURL URLWithString:@"https://example.com/page?q=1#frag"];
	OAK_ASSERT_EQ(describe([HOBrowserView rewrittenURL:url]), describe(url));
}

// ==================================================================
// = IsLoadableScheme                                               =
// ==================================================================

void test_browser_loadable_schemes_are_a_fixed_case_insensitive_set ()
{
	for(NSString* scheme in @[ @"http", @"https", @"file", @"data", @"about", @"blob" ])
		OAK_ASSERT_EQ((bool)[HOBrowserView isLoadableScheme:[NSURL URLWithString:[scheme stringByAppendingString:@"://x/y"]]], true);

	// Compared lowercased, so a shouted scheme still loads.
	OAK_ASSERT_EQ((bool)[HOBrowserView isLoadableScheme:[NSURL URLWithString:@"HTTPS://example.com/"]], true);

	// Anything else is handed off rather than loaded — txmt: opens a document,
	// mailto: goes to the mail client.
	OAK_ASSERT_EQ((bool)[HOBrowserView isLoadableScheme:[NSURL URLWithString:@"txmt://open?url=file:///etc/hosts"]], false);
	OAK_ASSERT_EQ((bool)[HOBrowserView isLoadableScheme:[NSURL URLWithString:@"mailto:someone@example.com"]], false);
}

// ==================================================================
// = EscapeHTML                                                     =
// ==================================================================

void test_browser_escape_html_covers_three_characters_and_not_the_fourth ()
{
	// `&`, `<` and `"` are escaped. **`>` is not** — harmless in text content, and
	// pinned so a port does not "complete" the set and change every error page.
	OAK_ASSERT_EQ(to_s([HOBrowserView escapeHTML:@"a & b"]),   std::string("a &amp; b"));
	OAK_ASSERT_EQ(to_s([HOBrowserView escapeHTML:@"<tag>"]),   std::string("&lt;tag>"));
	OAK_ASSERT_EQ(to_s([HOBrowserView escapeHTML:@"say \"hi\""]), std::string("say &quot;hi&quot;"));
}

void test_browser_escape_html_does_not_double_escape ()
{
	// The ampersand is replaced *first*, which is what stops the `&` of `&lt;`
	// from being escaped again into `&amp;lt;`. Reordering the three replacements
	// is a silent corruption of every error message containing a `<`.
	OAK_ASSERT_EQ(to_s([HOBrowserView escapeHTML:@"<a href=\"x&y\">"]), std::string("&lt;a href=&quot;x&amp;y&quot;>"));
}
