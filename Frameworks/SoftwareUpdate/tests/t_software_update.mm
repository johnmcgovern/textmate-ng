#import "SoftwareUpdateTesting.h"

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

// A pin for SoftwareUpdate and OakDownloadManager, written against the ObjC++ and
// before any port of them (rule 18, rule 5, rule 40).
//
// Both files are 1,177 lines of ObjC++ with **no C++ in them at all** — the
// framework's only C++ is OakCompareVersionStrings.mm, which stays ObjC++ because
// its export is a free function that ObjC++ callers use (rule 19). So there is no
// extraction step here; what is left is the translation, and what that can break
// silently is what this file pins.
//
// The important one is the binding. `SoftwareUpdatePreferences` (Swift, in the
// Preferences framework) does
//
//     checkNowButton.bind(.enabled, to: softwareUpdateController,
//                         withKeyPath: "checking", …negate)
//
// and declares keyPathsForValuesAffecting… over "softwareUpdateController.checking"
// and ".errorString". If the port leaves those two properties without the
// @objc dynamic that KVO needs, **nothing fails**: the compiler is happy, every
// other test is happy, and the Check Now button simply stops greying out. That is
// rule 18's silent failure in its purest form, so it is pinned here through Cocoa
// Bindings rather than through a hand-rolled observer — the mechanism under test
// is the one the app actually uses.
//
// Bindings rather than -addObserver:forKeyPath: for a second reason, though a
// weaker one than I first wrote here: a test file's *body* cannot declare an ObjC
// class, because ide/gen_xctest.rb wraps it in `namespace <basename>` and an
// @interface may only appear at global scope. It can still declare one in a
// header, which gen_xctest hoists — Find/tests/FFKVORecorder.h does exactly that
// and is the pattern to copy if a pin ever needs a real observer. Here AppKit's
// own observer is still the better choice, because it is the mechanism
// SoftwareUpdatePreferences actually uses.
//
// Not pinned here, deliberately: anything requiring a network round trip.
// -checkForTestBuild: only sets `checking` once a channel URL resolves, and
// pointing it at a file:// URL walks into `((NSHTTPURLResponse*)response)
// .allHeaderFields` on a non-HTTP response. The threading contract that path does
// have is already pinned by t_software_update_threading.mm.

void setup ()
{
	NSApplicationLoad();
}

// MARK: - Selector surface (rule 18)

// Everything a consumer reaches. AppController calls -checkForUpdate:, Preferences
// binds `checking` and reads `errorString`, BundlesManager uses the download
// manager's two entry points, and SoftwareUpdate.mm sets `channels`.
void test_software_update_answers_its_public_selectors ()
{
	NSArray<NSString*>* const required = @[
		@"checkForUpdate:",
		@"checkForTestBuild:completionHandler:",
		@"channels",
		@"setChannels:",
		@"isChecking",
		@"errorString",
	];

	NSMutableArray* missing = [NSMutableArray array];
	for(NSString* name in required)
	{
		if(![SoftwareUpdate instancesRespondToSelector:NSSelectorFromString(name)])
			[missing addObject:name];
	}
	OAK_ASSERT_EQ(std::string([missing componentsJoinedByString:@", "].UTF8String), std::string(""));

	OAK_ASSERT((bool)[SoftwareUpdate respondsToSelector:@selector(sharedInstance)]);
}

void test_download_manager_answers_its_public_selectors ()
{
	NSArray<NSString*>* const required = @[
		@"userAgentString",
		@"setUserAgentString:",
		@"downloadFileAtURL:replacingFileAtURL:publicKeys:completionHandler:",
		@"downloadArchiveAtURL:forReplacingURL:publicKeys:completionHandler:",
	];

	NSMutableArray* missing = [NSMutableArray array];
	for(NSString* name in required)
	{
		if(![OakDownloadManager instancesRespondToSelector:NSSelectorFromString(name)])
			[missing addObject:name];
	}
	OAK_ASSERT_EQ(std::string([missing componentsJoinedByString:@", "].UTF8String), std::string(""));

	OAK_ASSERT((bool)[OakDownloadManager respondsToSelector:@selector(sharedInstance)]);
}

// Both are `static X* sharedInstance = [self new];` today. A port that returns a
// fresh instance would give Preferences a different object than the one the menu
// action drives, and the binding would observe something nothing ever updates.
void test_shared_instances_are_singletons ()
{
	OAK_ASSERT(SoftwareUpdate.sharedInstance == SoftwareUpdate.sharedInstance);
	OAK_ASSERT(OakDownloadManager.sharedInstance == OakDownloadManager.sharedInstance);
	OAK_ASSERT(SoftwareUpdate.sharedInstance != nil);
	OAK_ASSERT(OakDownloadManager.sharedInstance != nil);
}

// MARK: - The constants

// These are user-defaults keys and on-the-wire channel names. Renaming one does
// not fail to compile — it silently reads a different preference, so a user's
// configured channel reverts and "disable polling" turns itself back on.
void test_defaults_keys_are_unchanged ()
{
	OAK_ASSERT_EQ(std::string(kUserDefaultsLastSoftwareUpdateCheckKey.UTF8String), std::string("SoftwareUpdateLastPoll"));
	OAK_ASSERT_EQ(std::string(kUserDefaultsDisableSoftwareUpdateKey.UTF8String),   std::string("SoftwareUpdateDisablePolling"));
	OAK_ASSERT_EQ(std::string(kUserDefaultsAskBeforeUpdatingKey.UTF8String),       std::string("SoftwareUpdateAskBeforeUpdating"));
	OAK_ASSERT_EQ(std::string(kUserDefaultsSoftwareUpdateChannelKey.UTF8String),   std::string("SoftwareUpdateChannel"));
}

void test_channel_names_are_unchanged ()
{
	OAK_ASSERT_EQ(std::string(kSoftwareUpdateChannelRelease.UTF8String),    std::string("release"));
	OAK_ASSERT_EQ(std::string(kSoftwareUpdateChannelPrerelease.UTF8String), std::string("beta"));
	OAK_ASSERT_EQ(std::string(kSoftwareUpdateChannelCanary.UTF8String),     std::string("nightly"));
}

// MARK: - What +initialize does (rule 24)

// SoftwareUpdate still has a +initialize, and a Swift class cannot provide one, so
// it has to become explicit registration before the port — the same move
// AppController's theme defaults made.
//
// This asserts the *effect* rather than the mechanism: the registration domain
// carries the default. It reads that domain directly instead of -stringForKey: so
// it cannot be fooled by whatever the running user has actually chosen, and so it
// writes nothing (rule 53).
//
// The conversion has happened: +registerDefaults now does this, from
// +sharedInstance. The assertion is unchanged from when +initialize did it, which
// is the point of writing it against the effect. If it ever fails, the default
// channel is gone and every user without an explicit choice stops receiving
// updates.
void test_release_is_the_registered_default_channel ()
{
	(void)SoftwareUpdate.sharedInstance; // +registerDefaults runs here (rule 24)

	NSDictionary* registered = [NSUserDefaults.standardUserDefaults volatileDomainForName:NSRegistrationDomain];
	NSString* channel = registered[kUserDefaultsSoftwareUpdateChannelKey];

	// Asserted separately, and not for tidiness: -UTF8String on nil is NULL and
	// std::string(NULL) is undefined behaviour, so folding these into one
	// comparison makes the test *crash* rather than fail when the registration is
	// missing — which is the exact regression it exists to catch, reported as zero
	// failures (rule 54). Found by mutating +initialize to register nothing.
	OAK_ASSERT(channel != nil);
	OAK_ASSERT_EQ(std::string(channel.UTF8String), std::string(kSoftwareUpdateChannelRelease.UTF8String));
}

// MARK: - The binding Preferences depends on

// `checking` must stay KVO-compliant. This is the exact binding
// SoftwareUpdatePreferences installs on its Check Now button, negate transformer
// and all.
void test_checking_drives_a_cocoa_binding ()
{
	SoftwareUpdate* softwareUpdate = SoftwareUpdate.sharedInstance;
	id saved = [softwareUpdate valueForKey:@"checking"];

	NSButton* button = [NSButton buttonWithTitle:@"Check Now" target:nil action:NULL];
	[button bind:NSEnabledBinding toObject:softwareUpdate withKeyPath:@"checking" options:@{ NSValueTransformerNameBindingOption: NSNegateBooleanTransformerName }];

	[softwareUpdate setValue:@YES forKey:@"checking"];
	OAK_ASSERT_EQ((bool)button.enabled, false);

	[softwareUpdate setValue:@NO forKey:@"checking"];
	OAK_ASSERT_EQ((bool)button.enabled, true);

	[button unbind:NSEnabledBinding];
	[softwareUpdate setValue:saved forKey:@"checking"];
}

// `errorString` is the other half — the pane's status line reads it through
// keyPathsForValuesAffectingLastCheckDescription.
void test_error_string_drives_a_cocoa_binding ()
{
	SoftwareUpdate* softwareUpdate = SoftwareUpdate.sharedInstance;
	id saved = [softwareUpdate valueForKey:@"errorString"];

	NSTextField* textField = [NSTextField labelWithString:@""];
	[textField bind:NSValueBinding toObject:softwareUpdate withKeyPath:@"errorString" options:nil];

	[softwareUpdate setValue:@"Error: no such channel" forKey:@"errorString"];
	OAK_ASSERT_EQ(std::string(textField.stringValue.UTF8String), std::string("Error: no such channel"));

	[softwareUpdate setValue:nil forKey:@"errorString"];
	OAK_ASSERT_EQ(std::string(textField.stringValue.UTF8String), std::string(""));

	[textField unbind:NSValueBinding];
	[softwareUpdate setValue:saved forKey:@"errorString"];
}

// MARK: - channels

// AppController deliberately leaves this unset (Phase 2.5), which is why
// -checkForTestBuild: reports "No channel named …" rather than checking against
// MacroMates' server. A port that dropped the setter would be silent about it.
void test_channels_round_trips ()
{
	SoftwareUpdate* softwareUpdate = SoftwareUpdate.sharedInstance;
	NSDictionary* saved = softwareUpdate.channels;

	NSDictionary<NSString*, NSURL*>* channels = @{ kSoftwareUpdateChannelRelease: [NSURL URLWithString:@"https://example.invalid/releases"] };
	softwareUpdate.channels = channels;
	NSURL* url = softwareUpdate.channels[kSoftwareUpdateChannelRelease];
	OAK_ASSERT(url != nil); // same nil-UTF8String hazard as above
	OAK_ASSERT_EQ(std::string(url.absoluteString.UTF8String), std::string("https://example.invalid/releases"));

	softwareUpdate.channels = saved;
	OAK_ASSERT(softwareUpdate.channels == saved);
}

// The user agent is sent on every check and every bundle download; BundlesManager
// relies on the same instance carrying it. Not its exact text — just that the port
// does not leave it empty, which would be invisible until a server rejected it.
void test_user_agent_is_not_empty ()
{
	NSString* userAgent = OakDownloadManager.sharedInstance.userAgentString;
	OAK_ASSERT(userAgent != nil);
	OAK_ASSERT((bool)(userAgent.length > 0));
}

// A Swift class cannot provide +initialize, so having converted it (rule 24) this
// class must not regain one. Checked against SoftwareUpdate's *own* metaclass
// rather than +respondsToSelector:, which answers YES for NSObject's
// implementation and would pass no matter what.
void test_software_update_declares_no_class_initialize ()
{
	unsigned int count = 0;
	Method* methods = class_copyMethodList(object_getClass([SoftwareUpdate class]), &count);

	NSMutableArray<NSString*>* names = [NSMutableArray array];
	for(unsigned int i = 0; i < count; ++i)
		[names addObject:NSStringFromSelector(method_getName(methods[i]))];
	free(methods);

	OAK_ASSERT_EQ((bool)[names containsObject:@"initialize"], false);
	OAK_ASSERT_EQ((bool)[names containsObject:@"registerDefaults"], true);
}

// MARK: - Content-Type parsing

// -checkForTestBuild: chooses its parser from the response's media type, and the
// original compared the entire Content-Type header against "application/json".
// That is wrong for any server sending a charset, which is legal and which every
// GitHub surface does — measured 2026-09-06:
//
//     api.github.com          application/json; charset=utf-8
//     <user>.github.io        application/json; charset=utf-8
//     raw.githubusercontent   text/plain; charset=utf-8
//
// A manifest served from any of those would have gone to the property-list
// parser and been reported as "Malformed server response". See
// ide/SOFTWARE_UPDATE_DESIGN.md.
void test_media_type_ignores_parameters ()
{
	OAK_ASSERT_EQ(std::string([SoftwareUpdate mediaTypeFromContentType:@"application/json; charset=utf-8"].UTF8String), std::string("application/json"));
	OAK_ASSERT_EQ(std::string([SoftwareUpdate mediaTypeFromContentType:@"text/plain; charset=utf-8"].UTF8String),       std::string("text/plain"));
}

void test_media_type_passes_a_bare_type_through ()
{
	// What MacroMates' bucket returns, and the case that must not regress.
	OAK_ASSERT_EQ(std::string([SoftwareUpdate mediaTypeFromContentType:@"application/json"].UTF8String), std::string("application/json"));
}

void test_media_type_is_case_and_whitespace_insensitive ()
{
	OAK_ASSERT_EQ(std::string([SoftwareUpdate mediaTypeFromContentType:@"APPLICATION/JSON"].UTF8String),        std::string("application/json"));
	OAK_ASSERT_EQ(std::string([SoftwareUpdate mediaTypeFromContentType:@"  application/json  ; x=1"].UTF8String), std::string("application/json"));
}

// nil rather than an empty string, so the caller's `== "application/json"` is
// false and the property-list branch runs — which is what a missing or malformed
// header did before.
void test_media_type_of_nothing_is_nil ()
{
	OAK_ASSERT([SoftwareUpdate mediaTypeFromContentType:nil] == nil);
	OAK_ASSERT([SoftwareUpdate mediaTypeFromContentType:@""] == nil);
	OAK_ASSERT([SoftwareUpdate mediaTypeFromContentType:@"  ; charset=utf-8"] == nil);
}

// MARK: - Archive extraction (rule 8 cannot reach this; the pin is the coverage)

// -extractArchiveAtURL:intoDirectory: exists as a separate method so that
// extraction provably happens *after* verification. The ObjC++ this was ported
// from streamed each downloaded chunk straight into tar's stdin and checked the
// signature only when the transfer finished, so tar ran on unverified bytes —
// the signature gated installation, not extraction. See
// ide/SOFTWARE_UPDATE_DESIGN.md.
//
// A real download needs a server, so what is pinned here is the seam: that the
// method unpacks a genuine bzip2 tar the way tar's arguments say it will, and
// that it reports failure rather than half-succeeding.

static NSURL* MakeScratchDirectory ()
{
	NSURL* url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"su-test-%@", NSUUID.UUID.UUIDString]]];
	[NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
	return url;
}

// Builds a .tbz whose single top-level directory is `Payload.app`, containing
// Contents/MacOS/tool — the shape `--strip-components 1` expects.
static NSURL* MakeArchive (NSURL* scratch)
{
	NSURL* stage = [scratch URLByAppendingPathComponent:@"stage"];
	NSURL* inner = [stage URLByAppendingPathComponent:@"Payload.app/Contents/MacOS"];
	[NSFileManager.defaultManager createDirectoryAtURL:inner withIntermediateDirectories:YES attributes:nil error:nil];
	[@"binary" writeToURL:[inner URLByAppendingPathComponent:@"tool"] atomically:YES encoding:NSUTF8StringEncoding error:nil];

	NSURL* archive = [scratch URLByAppendingPathComponent:@"payload.tbz"];

	NSTask* task = [[NSTask alloc] init];
	task.launchPath = @"/usr/bin/tar";
	task.arguments  = @[ @"-cjf", archive.path, @"-C", stage.path, @"Payload.app" ];
	task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
	task.standardError  = NSFileHandle.fileHandleWithNullDevice;
	[task launch];
	[task waitUntilExit];

	return task.terminationStatus == 0 ? archive : nil;
}

void test_extracting_an_archive_strips_the_top_level_component ()
{
	NSURL* scratch = MakeScratchDirectory();
	NSURL* archive = MakeArchive(scratch);
	OAK_ASSERT(archive != nil);

	NSURL* destination = [scratch URLByAppendingPathComponent:@"out"];
	[NSFileManager.defaultManager createDirectoryAtURL:destination withIntermediateDirectories:YES attributes:nil error:nil];

	NSError* error = nil;
	BOOL ok = [OakDownloadManager.sharedInstance extractArchiveAtURL:archive intoDirectory:destination error:&error];
	OAK_ASSERT_EQ((bool)ok, true);

	// --strip-components 1 means the destination *is* the unpacked bundle, which
	// is what -takeURLToInstallFrom: relies on: it appends Contents/MacOS/<name>
	// to whatever URL the download hands back.
	NSString* tool = [destination URLByAppendingPathComponent:@"Contents/MacOS/tool"].path;
	OAK_ASSERT_EQ((bool)[NSFileManager.defaultManager fileExistsAtPath:tool], true);

	[NSFileManager.defaultManager removeItemAtURL:scratch error:nil];
}

// Garbage in, error out — and specifically not a silent success, because the
// caller treats success as "this directory is now an application".
void test_extracting_a_non_archive_fails ()
{
	NSURL* scratch = MakeScratchDirectory();

	NSURL* notAnArchive = [scratch URLByAppendingPathComponent:@"payload.tbz"];
	[@"this is not a bzip2 tar" writeToURL:notAnArchive atomically:YES encoding:NSUTF8StringEncoding error:nil];

	NSURL* destination = [scratch URLByAppendingPathComponent:@"out"];
	[NSFileManager.defaultManager createDirectoryAtURL:destination withIntermediateDirectories:YES attributes:nil error:nil];

	NSError* error = nil;
	BOOL ok = [OakDownloadManager.sharedInstance extractArchiveAtURL:notAnArchive intoDirectory:destination error:&error];
	OAK_ASSERT_EQ((bool)ok, false);
	OAK_ASSERT(error != nil);

	[NSFileManager.defaultManager removeItemAtURL:scratch error:nil];
}
