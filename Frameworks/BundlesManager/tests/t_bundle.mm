#import "BundlesManagerTesting.h"
#import <Cocoa/Cocoa.h>

// Pins for Bundle and BundleGrammar, the model objects behind Settings ▸
// Bundles, written against the ObjC++ and before any port of them (rule 18,
// rule 40).
//
// Bundle is 46 lines of properties and five derived values, and what a port
// breaks silently is the KVC/KVO surface rather than the values: the
// Preferences pane binds table columns to `name`, `downloadLastUpdated` and
// `textSummary`, extends the class with an `installedCellState` that depends on
// `installed`, and BundlesManager filters with predicates spelled
// `isInstalled == NO` and `isRecommended == YES`. Five properties carry a
// `getter =` — rule 64 territory, five times over — and three derived values
// declare +keyPathsForValuesAffecting…. Every one of those is a selector or a
// key path that stays reachable or the feature quietly stops updating.

void setup ()
{
	NSApplicationLoad();
}

static Bundle* BundleNamed (NSString* name)
{
	Bundle* bundle = [[Bundle alloc] initWithIdentifier:[NSUUID UUID]];
	bundle.name = name;
	return bundle;
}

static NSDate* Date (NSTimeInterval secondsSince1970)
{
	return [NSDate dateWithTimeIntervalSince1970:secondsSince1970];
}

// MARK: - Selector surface (rule 18, rule 64)

void test_bundle_answers_its_public_selectors ()
{
	NSArray<NSString*>* const required = @[
		@"initWithIdentifier:",
		@"identifier", @"setIdentifier:",
		@"name", @"setName:",
		@"minimumAppVersion", @"setMinimumAppVersion:",
		@"category", @"setCategory:",
		@"htmlURL", @"setHtmlURL:",
		@"summary", @"setSummary:",
		@"contactName", @"setContactName:",
		@"contactEmail", @"setContactEmail:",
		@"downloadURL", @"setDownloadURL:",
		@"downloadLastUpdated", @"setDownloadLastUpdated:",
		@"downloadSize", @"setDownloadSize:",
		@"isMandatory", @"setMandatory:",
		@"isRecommended", @"setRecommended:",
		@"grammars", @"setGrammars:",
		@"dependencies", @"setDependencies:",
		@"isInstalled", @"setInstalled:",
		@"path", @"setPath:",
		@"lastUpdated", @"setLastUpdated:",
		@"isDependency", @"setDependency:",
		@"hasUpdate",
		@"isCompatible",
		@"textSummary",
	];

	NSMutableArray* missing = [NSMutableArray array];
	for(NSString* name in required)
	{
		if(![Bundle instancesRespondToSelector:NSSelectorFromString(name)])
			[missing addObject:name];
	}
	OAK_ASSERT_EQ(std::string([missing componentsJoinedByString:@", "].UTF8String), std::string(""));
}

void test_bundle_grammar_answers_its_public_selectors ()
{
	NSArray<NSString*>* const required = @[
		@"bundle", @"setBundle:",
		@"identifier", @"setIdentifier:",
		@"name", @"setName:",
		@"fileType", @"setFileType:",
		@"filePatterns", @"setFilePatterns:",
		@"firstLineMatch", @"setFirstLineMatch:",
	];

	NSMutableArray* missing = [NSMutableArray array];
	for(NSString* name in required)
	{
		if(![BundleGrammar instancesRespondToSelector:NSSelectorFromString(name)])
			[missing addObject:name];
	}
	OAK_ASSERT_EQ(std::string([missing componentsJoinedByString:@", "].UTF8String), std::string(""));
}

// BundlesManager filters its list with NSPredicates that spell the *getter*
// names — `isInstalled == NO`, `isRecommended == YES`, `hasUpdate == YES AND
// isCompatible == YES`. KVC resolves those through the getter selector, so a port
// that keeps `installed` as the KVO key but loses the `isInstalled` selector
// (rule 64) makes every one of those predicates throw. Pinned through a
// predicate, the mechanism actually in use.
void test_getter_names_are_kvc_reachable_for_predicates ()
{
	Bundle* a = BundleNamed(@"A"); a.installed = YES; a.recommended = YES; a.mandatory = NO;  a.dependency = YES;
	Bundle* b = BundleNamed(@"B"); b.installed = NO;  b.recommended = NO;  b.mandatory = YES; b.dependency = NO;
	NSArray* both = @[ a, b ];

	OAK_ASSERT_EQ((size_t)[both filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isInstalled == YES"]].count, (size_t)1);
	OAK_ASSERT_EQ((size_t)[both filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isRecommended == YES"]].count, (size_t)1);
	OAK_ASSERT_EQ((size_t)[both filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isMandatory == YES"]].count, (size_t)1);
	OAK_ASSERT_EQ((size_t)[both filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isDependency == YES"]].count, (size_t)1);
	OAK_ASSERT([[both filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isInstalled == NO"]].firstObject isEqual:b]);

	// And the plain KVO key, which the Preferences extension depends on
	// ("installed" in +keyPathsForValuesAffectingInstalledCellState).
	OAK_ASSERT([[a valueForKey:@"installed"] boolValue] == YES);
	OAK_ASSERT([[b valueForKey:@"installed"] boolValue] == NO);
}

// MARK: - Identity

// -installBundles: collects into an NSMutableSet and filters with `SELF IN %@`,
// so two Bundle objects for the same UUID have to be equal and hash alike.
void test_bundles_are_equal_by_identifier ()
{
	NSUUID* uuid = [NSUUID UUID];
	Bundle* a = [[Bundle alloc] initWithIdentifier:uuid];
	Bundle* b = [[Bundle alloc] initWithIdentifier:uuid];
	Bundle* c = [[Bundle alloc] initWithIdentifier:[NSUUID UUID]];
	a.name = @"first"; b.name = @"second";

	OAK_ASSERT([a isEqual:b]);
	OAK_ASSERT(a.hash == b.hash);
	OAK_ASSERT(![a isEqual:c]);
	OAK_ASSERT(![a isEqual:@"not a bundle"]);
	NSSet* unique = [NSSet setWithArray:@[ a, b, c ]];
	OAK_ASSERT_EQ((size_t)unique.count, (size_t)2);
}

void test_description_names_the_bundle_and_its_path_when_installed ()
{
	Bundle* bundle = BundleNamed(@"Ruby");
	bundle.contactName = @"Someone";
	OAK_ASSERT([bundle.description containsString:@"Ruby by Someone"]);
	OAK_ASSERT(![bundle.description containsString:@"/tmp"]);

	bundle.installed = YES;
	bundle.path = @"/tmp/Ruby.tmbundle";
	OAK_ASSERT([bundle.description containsString:@"Ruby by Someone, /tmp/Ruby.tmbundle"]);
}

// MARK: - Derived values

// An update exists only when both dates are known and the download is strictly
// newer. The spelling in the original is `[download laterDate:local] != local`,
// which for equal dates answers NO because -laterDate: returns the receiver.
void test_has_update_needs_both_dates_and_a_newer_download ()
{
	Bundle* bundle = BundleNamed(@"X");
	OAK_ASSERT(bundle.hasUpdate == NO);

	bundle.downloadLastUpdated = Date(2000);
	OAK_ASSERT(bundle.hasUpdate == NO);

	bundle.lastUpdated = Date(2000);
	OAK_ASSERT(bundle.hasUpdate == NO);

	bundle.lastUpdated = Date(1000);
	OAK_ASSERT(bundle.hasUpdate == YES);

	bundle.lastUpdated = Date(3000);
	OAK_ASSERT(bundle.hasUpdate == NO);

	bundle.downloadLastUpdated = nil;
	OAK_ASSERT(bundle.hasUpdate == NO);
}

// Compatibility is OakCompareVersionStrings(app, minimum) != ascending. The
// test host's own version is whatever xctest's Info.plist says, so only the two
// ends that hold for any host are pinned: no requirement is compatible, and an
// impossible one is not.
void test_compatibility_against_the_minimum_app_version ()
{
	Bundle* bundle = BundleNamed(@"X");
	OAK_ASSERT(bundle.isCompatible == YES);

	bundle.minimumAppVersion = @"9999.0";
	OAK_ASSERT(bundle.isCompatible == NO);
}

// The one-line description shown in the table: tags stripped, entities decoded,
// runs of whitespace collapsed, ends trimmed.
void test_text_summary_strips_markup_and_decodes_entities ()
{
	Bundle* bundle = BundleNamed(@"X");
	bundle.summary = @"  <p>Ruby &amp; <b>Rails</b>\n\tsupport.</p>  ";
	OAK_ASSERT_EQ(std::string(bundle.textSummary.UTF8String), std::string("Ruby & Rails support."));

	bundle.summary = @"plain";
	OAK_ASSERT_EQ(std::string(bundle.textSummary.UTF8String), std::string("plain"));
}

void test_text_summary_of_no_summary_is_empty ()
{
	Bundle* bundle = BundleNamed(@"X");
	OAK_ASSERT_EQ(std::string(bundle.textSummary.UTF8String ?: ""), std::string(""));
}

// MARK: - KVO dependencies

// The three derived values declare what they depend on; the description column
// and the update filter go stale without it.
void test_dependent_key_paths_are_declared ()
{
	NSSet* hasUpdate = [Bundle keyPathsForValuesAffectingValueForKey:@"hasUpdate"];
	OAK_ASSERT([hasUpdate containsObject:@"downloadLastUpdated"]);
	OAK_ASSERT([hasUpdate containsObject:@"lastUpdated"]);

	NSSet* compatible = [Bundle keyPathsForValuesAffectingValueForKey:@"compatible"];
	OAK_ASSERT([compatible containsObject:@"minimumAppVersion"]);

	NSSet* textSummary = [Bundle keyPathsForValuesAffectingValueForKey:@"textSummary"];
	OAK_ASSERT([textSummary containsObject:@"summary"]);
}

// Through Cocoa Bindings, the mechanism the Preferences pane uses: a bound
// control follows `hasUpdate` when only `lastUpdated` changes, and `textSummary`
// when only `summary` does. That takes both the dependency declaration above and
// KVO-compliant setters — a Swift port that drops `dynamic` compiles, and this
// is what notices.
void test_bound_controls_follow_derived_values ()
{
	Bundle* bundle = BundleNamed(@"X");
	bundle.downloadLastUpdated = Date(2000);
	bundle.lastUpdated = Date(2000);
	bundle.summary = @"<i>one</i>";

	NSButton* button = [[NSButton alloc] initWithFrame:NSZeroRect];
	[button bind:NSEnabledBinding toObject:bundle withKeyPath:@"hasUpdate" options:nil];
	NSTextField* field = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[field bind:NSValueBinding toObject:bundle withKeyPath:@"textSummary" options:nil];

	OAK_ASSERT(button.isEnabled == NO);
	OAK_ASSERT_EQ(std::string(field.stringValue.UTF8String), std::string("one"));

	bundle.lastUpdated = Date(1000);
	OAK_ASSERT(button.isEnabled == YES);

	bundle.summary = @"<i>two</i>";
	OAK_ASSERT_EQ(std::string(field.stringValue.UTF8String), std::string("two"));

	[button unbind:NSEnabledBinding];
	[field unbind:NSValueBinding];
}

// The plain stored properties the table binds to.
void test_bound_controls_follow_stored_properties ()
{
	Bundle* bundle = BundleNamed(@"before");

	NSTextField* field = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[field bind:NSValueBinding toObject:bundle withKeyPath:@"name" options:nil];
	OAK_ASSERT_EQ(std::string(field.stringValue.UTF8String), std::string("before"));

	bundle.name = @"after";
	OAK_ASSERT_EQ(std::string(field.stringValue.UTF8String), std::string("after"));

	NSButton* button = [[NSButton alloc] initWithFrame:NSZeroRect];
	[button bind:NSEnabledBinding toObject:bundle withKeyPath:@"installed" options:nil];
	OAK_ASSERT(button.isEnabled == NO);
	bundle.installed = YES;
	OAK_ASSERT(button.isEnabled == YES);

	[field unbind:NSValueBinding];
	[button unbind:NSEnabledBinding];
}

// MARK: - BundleGrammar

void test_grammar_holds_its_bundle_weakly ()
{
	BundleGrammar* grammar = [BundleGrammar new];
	grammar.name = @"Ruby";
	grammar.fileType = @"source.ruby";
	// This test bundle is compiled with ARC off (rule 60), so the +1 from alloc
	// is released by hand — which is what lets the weak reference zero.
	// Reading a weak property hands back an autoreleased reference, so the
	// first read gets its own pool or it would keep the bundle alive.
	Bundle* bundle = [[Bundle alloc] initWithIdentifier:[NSUUID UUID]];
	grammar.bundle = bundle;
	@autoreleasepool {
		OAK_ASSERT(grammar.bundle == bundle);
	}
	[bundle release];
	OAK_ASSERT(grammar.bundle == nil);
	OAK_ASSERT([grammar.description containsString:@"Ruby (source.ruby)"]);
}
