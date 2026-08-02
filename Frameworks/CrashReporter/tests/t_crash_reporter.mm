#import "CRTestingDeclarations.h"
#import <UserNotifications/UserNotifications.h>
#import <test/jail.h>
#import <zlib.h>

// -UTF8String rather than ns::to_s: this framework does not depend on `ns`, and
// without that overload in scope `to_s(NSString*)` silently binds to the
// preamble's GENERIC container template, which range-iterates the string and
// dies with "unrecognized selector countByEnumeratingWithState:" — a runtime
// failure from an overload that should never have matched.
static std::string str (NSString* s) { return s.UTF8String ?: ""; }

// -UTF8String rather than ns::to_s: this framework does not depend on `ns`, and
// without that overload in scope `to_s(NSString*)` silently binds to the
// preamble's GENERIC container template, which range-iterates the string and
// dies with "unrecognized selector countByEnumeratingWithState:". A runtime
// failure from an overload that should not have matched, not a compile error.

// CrashReporter is Swift behind a hand-written ObjC header. Its *upload* half is
// currently unreachable — Phase 2.5 stopped AppController calling
// -postNewCrashReportsToURLString: — so it cannot be exercised end to end, and
// these tests exist because that makes its three pure helpers the only place a
// transliteration mistake would ever be caught.
//
// The first test is the important one: it is the framework's whole documented
// blocker, checked rather than argued about.

// =====================================
// = The blocker, asserted not assumed =
// =====================================

// The framework was deferred for "the UNUserNotificationCenterDelegate overlay
// problem": a Swift delegate method that compiles but is never called. The
// cause was a wrong argument label — `completionHandler:` instead of Swift's
// imported `withCompletionHandler:` — which yields only a "nearly matches
// optional requirement" WARNING and satisfies nothing.
//
// There is no SDK overlay involved: UserNotifications ships no Swift module at
// all (a module map, no .swiftinterface), and the `async` spellings are an
// alternative rather than a competitor for the selector.
//
// So this asks the ObjC runtime what the class actually claims. It is the only
// check that distinguishes a correct implementation from one that compiles with
// a warning and silently never runs.
//
// Asked of the CLASS rather than an instance, deliberately: CrashReporter
// cannot be constructed here at all, because -init installs the
// UNUserNotificationCenter delegate and +currentNotificationCenter raises
// NSInternalInconsistencyException in a non-bundled process. So whether the
// delegate is actually *installed* is not checkable headlessly — but whether
// the class claims the selectors, which is what the blocker was about, is.
void test_notification_delegate_selectors_are_claimed ()
{
	Class reporter = NSClassFromString(@"CrashReporter");
	OAK_ASSERT(reporter);

	NSMutableArray<NSString*>* missing = [NSMutableArray array];
	for(NSString* name in @[
		@"userNotificationCenter:willPresentNotification:withCompletionHandler:",
		@"userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:",
		@"userNotificationCenter:shouldPresentNotification:",
		@"userNotificationCenter:didActivateNotification:",
	])
	{
		if(![reporter instancesRespondToSelector:NSSelectorFromString(name)])
			[missing addObject:name];
	}
	OAK_ASSERT_EQ(str([missing componentsJoinedByString:@", "]), "");
}

// The public header's contract, which nothing else checks against the Swift.
void test_public_surface_from_crash_reporter_h ()
{
	Class klass = NSClassFromString(@"CrashReporter");
	OAK_ASSERT(klass);
	OAK_ASSERT([klass respondsToSelector:@selector(sharedInstance)]);
	OAK_ASSERT([klass instancesRespondToSelector:@selector(applicationDidFinishLaunching:)]);
	OAK_ASSERT([klass instancesRespondToSelector:@selector(postNewCrashReportsToURLString:)]);
}

// ============================
// = Finding crash reports    =
// ============================

// macOS names reports "<Process>_<YYYY-MM-DD>-<HHMMSS>...", and the helper
// parses that back with strptime to decide what is recent enough to send.
void test_reports_are_matched_by_name_and_date ()
{
	test::jail_t jail;
	jail.touch("TextMate_2026-07-30-101500_host.ips");   // recent
	jail.touch("TextMate_2020-01-01-101500_host.ips");   // long ago
	jail.touch("SomeOtherApp_2026-07-30-101500_host.ips"); // another process
	jail.touch("TextMate-not-a-report.txt");             // no parseable date

	NSString* dir = [NSString stringWithUTF8String:jail.path().c_str()];
	NSDate* cutOff = [NSDate dateWithTimeIntervalSince1970:1750000000]; // mid-2025

	NSArray<NSString*>* res = [CrashReporter reportsForProcessName:@"TextMate" notBefore:cutOff in:dir];

	NSMutableSet<NSString*>* names = [NSMutableSet set];
	for(NSString* path in res)
		[names addObject:path.lastPathComponent];

	OAK_ASSERT([names containsObject:@"TextMate_2026-07-30-101500_host.ips"]);
	OAK_ASSERT(![names containsObject:@"TextMate_2020-01-01-101500_host.ips"]); // before the cut-off
	OAK_ASSERT(![names containsObject:@"SomeOtherApp_2026-07-30-101500_host.ips"]);
	OAK_ASSERT(![names containsObject:@"TextMate-not-a-report.txt"]); // strptime rejects it
	OAK_ASSERT_EQ(res.count, 1);
}

void test_reports_is_empty_for_a_missing_directory ()
{
	NSArray<NSString*>* res = [CrashReporter reportsForProcessName:@"TextMate" notBefore:NSDate.distantPast in:@"/nonexistent/directory"];
	OAK_ASSERT_EQ(res.count, 0);
}

// =========================
// = The multipart payload =
// =========================

// The body is what the collector parses, so its structure is the contract. The
// boundary is a fresh UUID each time, so it is read back off the request rather
// than assumed.
void test_multipart_body_carries_plain_values ()
{
	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://example.invalid/"]];
	NSData* body = [CrashReporter dataForURLRequest:request withFormValues:@{ @"contact": @"Anonymous" }];

	OAK_ASSERT_EQ(str(request.HTTPMethod), "POST");

	NSString* contentType = [request valueForHTTPHeaderField:@"Content-Type"];
	OAK_ASSERT([contentType hasPrefix:@"multipart/form-data; boundary=\""]);

	NSString* text = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
	OAK_ASSERT([text containsString:@"Content-Disposition: form-data; name=\"contact\""]);
	OAK_ASSERT([text containsString:@"Anonymous"]);

	// The boundary in the header must be the one used in the body, or the
	// collector sees no parts at all.
	NSRange q = [contentType rangeOfString:@"\""];
	NSString* boundary = [contentType substringWithRange:NSMakeRange(NSMaxRange(q), contentType.length - NSMaxRange(q) - 1)];
	OAK_ASSERT(([text containsString:[NSString stringWithFormat:@"--%@", boundary]]));
	OAK_ASSERT(([text hasSuffix:[NSString stringWithFormat:@"--%@--\r\n", boundary]]));
}

// A value beginning with "@" names a file, which is attached with a filename
// and an octet-stream type rather than inlined.
void test_multipart_body_attaches_a_file_for_an_at_prefixed_value ()
{
	test::jail_t jail;
	jail.set_content("report.gz", "GZIPBYTES");

	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://example.invalid/"]];
	NSString* path = [NSString stringWithUTF8String:jail.path("report.gz").c_str()];
	NSData* body = [CrashReporter dataForURLRequest:request withFormValues:@{ @"report": [@"@" stringByAppendingString:path] }];

	NSString* text = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
	OAK_ASSERT([text containsString:@"name=\"report\"; filename=\"report.gz\""]);
	OAK_ASSERT([text containsString:@"Content-Type: application/octet-stream"]);
	OAK_ASSERT([text containsString:@"GZIPBYTES"]); // the file's contents, not its path
	OAK_ASSERT(![text containsString:@"@/"]);       // and never the "@" marker itself
}

// ===========
// = Gzip    =
// ===========

// zlib is not reachable from Swift, so the compression goes through
// CRWriteGZipFile. Verified by decompressing the result, because "a file exists"
// would pass even if it held raw deflate — which is what Foundation's
// -compressedDataUsingAlgorithm: would have produced, and what the collector
// could not read.
void test_gzip_produces_a_file_that_gunzips_back ()
{
	test::jail_t jail;
	std::string const contents(4096, 'A'); // compressible, and bigger than one chunk
	jail.set_content("crash.ips", contents);

	NSString* source = [NSString stringWithUTF8String:jail.path("crash.ips").c_str()];
	NSString* gzPath = [CrashReporter pathForGZipCompressedFileAtPath:source];

	OAK_ASSERT(gzPath);
	OAK_ASSERT([gzPath hasSuffix:@"crash.ips.gz"]);
	OAK_ASSERT([NSFileManager.defaultManager fileExistsAtPath:gzPath]);

	gzFile fp = gzopen(gzPath.fileSystemRepresentation, "rb");
	OAK_ASSERT(fp != nullptr);

	std::string roundTripped;
	char buf[1024];
	int n;
	while((n = gzread(fp, buf, sizeof(buf))) > 0)
		roundTripped.append(buf, n);
	gzclose(fp);

	OAK_ASSERT_EQ(roundTripped, contents);

	unlink(gzPath.fileSystemRepresentation);
}

void test_gzip_returns_nil_for_a_missing_source ()
{
	OAK_ASSERT(![CrashReporter pathForGZipCompressedFileAtPath:@"/nonexistent/crash.ips"]);
}
