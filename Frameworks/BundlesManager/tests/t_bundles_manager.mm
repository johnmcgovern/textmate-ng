#import "BundlesManagerTesting.h"
#import <Cocoa/Cocoa.h>
#import <sys/xattr.h>

// Pins for BundlesManager, written against the ObjC++ and before its port
// (rule 18, rule 40).
//
// The framework had no test. Its 751-line manager is two things wearing one
// class: a bundle-index cache with an FSEvents watcher (C++ throughout — the
// boundary the port extracts first) and a Foundation model over three plist
// files (the remote index, the local index, the Bundles directory), which is
// what these tests pin. BundlesFromIndex is the piece that can be pinned
// exactly: pure over its three paths, with one xattr read and one directory
// listing, both against a fixture written here.
//
// Deliberately not pinned: -installBundles: (a download), -loadBundlesIndex
// (builds the real bundle index and watches the real directories),
// -findBundleForInstall: (a modal alert), and anything on the shared instance
// — its paths are the user's real Application Support directory.

void setup ()
{
	NSApplicationLoad();
}

// Set from a constructor and restored from the destructor, so a failed
// assertion — which throws — still restores it (rule 53). Off means no
// NSBackgroundActivityScheduler is created for the instance under test, which
// otherwise would schedule a real index fetch.
struct disable_bundle_updates_t
{
	disable_bundle_updates_t ()
	{
		_previous = [NSUserDefaults.standardUserDefaults objectForKey:kUserDefaultsDisableBundleUpdatesKey];
		[NSUserDefaults.standardUserDefaults setBool:YES forKey:kUserDefaultsDisableBundleUpdatesKey];
	}

	~disable_bundle_updates_t ()
	{
		if(_previous)
				[NSUserDefaults.standardUserDefaults setObject:_previous forKey:kUserDefaultsDisableBundleUpdatesKey];
		else	[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsDisableBundleUpdatesKey];
	}

private:
	id _previous;
};

// MARK: - Selector surface (rule 18)

void test_bundles_manager_answers_its_public_selectors ()
{
	OAK_ASSERT([BundlesManager respondsToSelector:@selector(sharedInstance)]);

	NSArray<NSString*>* const required = @[
		@"bundles",
		@"installBundles:completionHandler:",
		@"uninstallBundle:",
		@"loadBundlesIndex",
		@"installBundleItemsAtPaths:",
		@"findBundleForInstall:",
		@"reloadPath:",
		@"userDefaultsDidChange:",
	];

	NSMutableArray* missing = [NSMutableArray array];
	for(NSString* name in required)
	{
		if(![BundlesManager instancesRespondToSelector:NSSelectorFromString(name)])
			[missing addObject:name];
	}
	OAK_ASSERT_EQ(std::string([missing componentsJoinedByString:@", "].UTF8String), std::string(""));
}

// The Preferences pane binds a checkbox to "values.disableBundleUpdates" and
// reads the last-check date by the other key. The strings are the contract.
void test_user_defaults_keys_are_the_ones_preferences_binds_to ()
{
	OAK_ASSERT_EQ(std::string(kUserDefaultsDisableBundleUpdatesKey.UTF8String), std::string("disableBundleUpdates"));
	OAK_ASSERT_EQ(std::string(kUserDefaultsLastBundleUpdateCheckKey.UTF8String), std::string("lastBundleUpdateCheck"));
}

// MARK: - The bundles list is observable

// BundlesPreferences does
//
//     arrayController.bind(.content, to: BundlesManager.sharedInstance, withKeyPath: "bundles", …)
//
// so a port that leaves `bundles` without the `@objc dynamic` KVO needs compiles
// and leaves the table empty after every index update. Pinned through the same
// binding, on a fresh instance so nothing here touches the real index.
void test_bundles_list_is_kvo_observable_through_a_binding ()
{
	disable_bundle_updates_t guard;
	BundlesManager* manager = [BundlesManager new];

	Bundle* first = [[Bundle alloc] initWithIdentifier:[NSUUID UUID]];
	first.name = @"First";
	manager.bundles = @[ first ];

	NSArrayController* controller = [[NSArrayController alloc] init];
	[controller bind:NSContentBinding toObject:manager withKeyPath:@"bundles" options:nil];
	OAK_ASSERT_EQ((size_t)[controller.arrangedObjects count], (size_t)1);

	Bundle* second = [[Bundle alloc] initWithIdentifier:[NSUUID UUID]];
	second.name = @"Second";
	manager.bundles = @[ first, second ];
	OAK_ASSERT_EQ((size_t)[controller.arrangedObjects count], (size_t)2);

	[controller unbind:NSContentBinding];
}

// MARK: - BundlesFromIndex

// The fixture, one of everything the parser branches on:
//
//   remote index   Ruby (recommended, one grammar, versions), Rails (depends on
//                  Ruby by grammar scope, and on a UUID nobody provides), Alpha
//                  (depends on Ruby by UUID) — names chosen so the sort has to
//                  reorder them
//   local index    Ruby installed at Bundles/Ruby.tmbundle, a dependency; Gone,
//                  which the remote index no longer lists and which is not on
//                  disk either
//   on disk        Ruby.tmbundle; Orphan.tmbundle with an info.plist and the
//                  org.textmate.bundle.updated xattr, in no index at all
struct fixture_t
{
	NSString* installDir;
	NSString* remoteIndexPath;
	NSString* localIndexPath;

	NSUUID* ruby   = [[NSUUID alloc] initWithUUIDString:@"11111111-1111-1111-1111-111111111111"];
	NSUUID* rails  = [[NSUUID alloc] initWithUUIDString:@"22222222-2222-2222-2222-222222222222"];
	NSUUID* alpha  = [[NSUUID alloc] initWithUUIDString:@"33333333-3333-3333-3333-333333333333"];
	NSUUID* gone   = [[NSUUID alloc] initWithUUIDString:@"44444444-4444-4444-4444-444444444444"];
	NSUUID* orphan = [[NSUUID alloc] initWithUUIDString:@"55555555-5555-5555-5555-555555555555"];
	NSUUID* nobody = [[NSUUID alloc] initWithUUIDString:@"66666666-6666-6666-6666-666666666666"];
	NSUUID* rubyGrammar = [[NSUUID alloc] initWithUUIDString:@"77777777-7777-7777-7777-777777777777"];

	NSDate* rubyUpdated  = [NSDate dateWithTimeIntervalSince1970:1700000000];
	NSDate* railsUpdated = [NSDate dateWithTimeIntervalSince1970:1700000001];
	NSDate* goneUpdated  = [NSDate dateWithTimeIntervalSince1970:1600000000];

	fixture_t ()
	{
		NSString* base = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"tm-bundles-manager-%d", getpid()]];
		[NSFileManager.defaultManager removeItemAtPath:base error:nil];

		installDir      = [base stringByAppendingPathComponent:@"Managed"];
		remoteIndexPath = [installDir stringByAppendingPathComponent:@"Cache/org.textmate.updates.default"];
		localIndexPath  = [installDir stringByAppendingPathComponent:@"LocalIndex.plist"];

		NSFileManager* fm = NSFileManager.defaultManager;
		[fm createDirectoryAtPath:[installDir stringByAppendingPathComponent:@"Cache"] withIntermediateDirectories:YES attributes:nil error:nil];
		[fm createDirectoryAtPath:[installDir stringByAppendingPathComponent:@"Bundles/Ruby.tmbundle"] withIntermediateDirectories:YES attributes:nil error:nil];
		[fm createDirectoryAtPath:[installDir stringByAppendingPathComponent:@"Bundles/Orphan.tmbundle"] withIntermediateDirectories:YES attributes:nil error:nil];
		[fm createDirectoryAtPath:[installDir stringByAppendingPathComponent:@"Bundles/notes.txt"] withIntermediateDirectories:YES attributes:nil error:nil];

		NSDictionary* remote = @{ @"bundles": @[
			@{
				@"uuid": ruby.UUIDString, @"name": @"Ruby", @"requires": @"2.0", @"category": @"Languages",
				@"html_url": @"https://example.com/ruby", @"contactName": @"Alice", @"contactEmailRot13": @"nyvpr@rknzcyr.pbz",
				@"description": @"<p>Ruby &amp; <b>Rails</b> support.</p>", @"isDefault": @YES, @"isMandatory": @NO,
				@"versions": @[ @{ @"url": @"https://example.com/ruby.tbz", @"updated": rubyUpdated, @"size": @12345 } ],
				@"grammars": @[ @{ @"name": @"Ruby", @"uuid": rubyGrammar.UUIDString, @"scope": @"source.ruby", @"firstLineMatch": @"^#!/.*\\bruby", @"fileTypes": @[ @"rb", @"Rakefile" ] } ],
				@"dependencies": @[],
			},
			@{
				@"uuid": rails.UUIDString, @"name": @"Rails", @"category": @"Frameworks", @"isDefault": @NO, @"isMandatory": @YES,
				@"versions": @[ @{ @"url": @"https://example.com/rails.tbz", @"updated": railsUpdated, @"size": @1 } ],
				@"grammars": @[],
				@"dependencies": @[ @{ @"grammar": @"source.ruby" }, @{ @"uuid": nobody.UUIDString, @"name": @"Nobody" } ],
			},
			@{
				@"uuid": alpha.UUIDString, @"name": @"Alpha", @"isDefault": @NO,
				@"versions": @[ @{ @"url": @"https://example.com/alpha.tbz", @"updated": railsUpdated, @"size": @2 } ],
				@"dependencies": @[ @{ @"uuid": ruby.UUIDString, @"name": @"Ruby" } ],
			},
		] };
		[remote writeToFile:remoteIndexPath atomically:YES];

		NSDictionary* local = @{ @"bundles": @[
			@{ @"uuid": ruby.UUIDString, @"path": @"Bundles/Ruby.tmbundle", @"updated": rubyUpdated, @"isDependency": @YES, @"category": @"Languages" },
			@{ @"uuid": gone.UUIDString, @"path": @"Bundles/Gone.tmbundle", @"updated": goneUpdated },
		] };
		[local writeToFile:localIndexPath atomically:YES];

		NSString* orphanPath = [installDir stringByAppendingPathComponent:@"Bundles/Orphan.tmbundle"];
		NSDictionary* info = @{ @"uuid": orphan.UUIDString, @"name": @"Orphan", @"contactName": @"Oscar", @"contactEmailRot13": @"bfpne@rknzcyr.pbz", @"description": @"An orphan." };
		[info writeToFile:[orphanPath stringByAppendingPathComponent:@"info.plist"] atomically:YES];

		// A directory that is not a .tmbundle but looks like one inside: only the
		// "*.tm[Bb]undle" glob keeps it out of the list.
		NSDictionary* decoy = @{ @"uuid": @"88888888-8888-8888-8888-888888888888", @"name": @"Decoy" };
		[decoy writeToFile:[installDir stringByAppendingPathComponent:@"Bundles/notes.txt/info.plist"] atomically:YES];

		// What -installBundles: writes: `to_s(bundle.downloadLastUpdated)`, which is
		// -[NSDate description].
		char const* updated = "2026-01-02 03:04:05 +0000";
		setxattr(orphanPath.fileSystemRepresentation, "org.textmate.bundle.updated", updated, strlen(updated), 0, 0);
	}

	NSArray<Bundle*>* parse (NSDictionary<NSUUID*, Bundle*>* previous = nil) const
	{
		return [BundlesManager bundlesFromRemoteIndexAtPath:remoteIndexPath localIndexPath:localIndexPath installDirectory:installDir previousBundles:previous];
	}

	static Bundle* find (NSArray<Bundle*>* bundles, NSUUID* identifier)
	{
		for(Bundle* bundle in bundles)
		{
			if([bundle.identifier isEqual:identifier])
				return bundle;
		}
		return nil;
	}
};

void test_index_yields_every_bundle_from_all_three_sources ()
{
	fixture_t fixture;
	NSArray<Bundle*>* bundles = fixture.parse();

	OAK_ASSERT_EQ((size_t)bundles.count, (size_t)5);
	OAK_ASSERT(fixture_t::find(bundles, fixture.ruby)   != nil);
	OAK_ASSERT(fixture_t::find(bundles, fixture.rails)  != nil);
	OAK_ASSERT(fixture_t::find(bundles, fixture.alpha)  != nil);
	OAK_ASSERT(fixture_t::find(bundles, fixture.gone)   != nil);
	OAK_ASSERT(fixture_t::find(bundles, fixture.orphan) != nil);
	OAK_ASSERT(fixture_t::find(bundles, fixture.nobody) == nil);
}

// Sorted by name with -localizedCompare:, whatever order the index listed them.
void test_index_is_sorted_by_name ()
{
	fixture_t fixture;
	NSMutableArray* named = [NSMutableArray array];
	for(Bundle* bundle in fixture.parse())
	{
		if(bundle.name)
			[named addObject:bundle.name];
	}
	OAK_ASSERT_EQ(std::string([named componentsJoinedByString:@","].UTF8String), std::string("Alpha,Orphan,Rails,Ruby"));
}

void test_remote_index_fields_are_read ()
{
	fixture_t fixture;
	Bundle* ruby = fixture_t::find(fixture.parse(), fixture.ruby);

	OAK_ASSERT([ruby.name isEqualToString:@"Ruby"]);
	OAK_ASSERT([ruby.minimumAppVersion isEqualToString:@"2.0"]);
	OAK_ASSERT([ruby.category isEqualToString:@"Languages"]);
	OAK_ASSERT([ruby.htmlURL.absoluteString isEqualToString:@"https://example.com/ruby"]);
	OAK_ASSERT([ruby.contactName isEqualToString:@"Alice"]);
	OAK_ASSERT([ruby.contactEmail isEqualToString:@"alice@example.com"]); // rot13 decoded
	OAK_ASSERT([ruby.summary isEqualToString:@"<p>Ruby &amp; <b>Rails</b> support.</p>"]);
	OAK_ASSERT(ruby.isRecommended == YES);
	OAK_ASSERT(ruby.isMandatory == NO);
	OAK_ASSERT([ruby.downloadURL.absoluteString isEqualToString:@"https://example.com/ruby.tbz"]);
	OAK_ASSERT([ruby.downloadLastUpdated isEqualToDate:fixture.rubyUpdated]);
	OAK_ASSERT_EQ((ssize_t)ruby.downloadSize, (ssize_t)12345);

	Bundle* rails = fixture_t::find(fixture.parse(), fixture.rails);
	OAK_ASSERT(rails.isMandatory == YES);
	OAK_ASSERT(rails.isRecommended == NO);
	OAK_ASSERT(rails.minimumAppVersion == nil);
}

void test_grammars_point_back_at_their_bundle ()
{
	fixture_t fixture;
	Bundle* ruby = fixture_t::find(fixture.parse(), fixture.ruby);

	OAK_ASSERT_EQ((size_t)ruby.grammars.count, (size_t)1);
	BundleGrammar* grammar = ruby.grammars.firstObject;
	OAK_ASSERT(grammar.bundle == ruby);
	OAK_ASSERT([grammar.name isEqualToString:@"Ruby"]);
	OAK_ASSERT([grammar.identifier isEqual:fixture.rubyGrammar]);
	OAK_ASSERT([grammar.fileType isEqualToString:@"source.ruby"]);
	OAK_ASSERT([grammar.firstLineMatch isEqualToString:@"^#!/.*\\bruby"]);
	OAK_ASSERT([grammar.filePatterns isEqualToArray:(@[ @"rb", @"Rakefile" ])]);
}

// A dependency is resolved by the grammar scope another bundle provides, or by
// UUID; one nobody provides is dropped (and logged), not kept as nil.
void test_dependencies_resolve_by_grammar_scope_and_by_uuid ()
{
	fixture_t fixture;
	NSArray<Bundle*>* bundles = fixture.parse();
	Bundle* ruby  = fixture_t::find(bundles, fixture.ruby);
	Bundle* rails = fixture_t::find(bundles, fixture.rails);
	Bundle* alpha = fixture_t::find(bundles, fixture.alpha);

	OAK_ASSERT_EQ((size_t)rails.dependencies.count, (size_t)1);
	OAK_ASSERT(rails.dependencies.firstObject == ruby);
	OAK_ASSERT_EQ((size_t)alpha.dependencies.count, (size_t)1);
	OAK_ASSERT(alpha.dependencies.firstObject == ruby);
	OAK_ASSERT_EQ((size_t)ruby.dependencies.count, (size_t)0);
}

// The local index marks what is installed: the path is relative to the install
// directory and the category from the local index wins.
void test_local_index_marks_installed_bundles ()
{
	fixture_t fixture;
	Bundle* ruby = fixture_t::find(fixture.parse(), fixture.ruby);

	OAK_ASSERT(ruby.isInstalled == YES);
	OAK_ASSERT([ruby.path isEqualToString:[fixture.installDir stringByAppendingPathComponent:@"Bundles/Ruby.tmbundle"]]);
	OAK_ASSERT([ruby.lastUpdated isEqualToDate:fixture.rubyUpdated]);
	OAK_ASSERT(ruby.isDependency == YES);
	OAK_ASSERT(ruby.hasUpdate == NO);
}

// A bundle the remote index no longer lists is "Discontinued"; one whose
// directory is gone is not installed, though its path is remembered.
void test_a_bundle_missing_from_the_remote_index_and_from_disk ()
{
	fixture_t fixture;
	Bundle* gone = fixture_t::find(fixture.parse(), fixture.gone);

	OAK_ASSERT([gone.category isEqualToString:@"Discontinued"]);
	OAK_ASSERT(gone.isInstalled == NO);
	OAK_ASSERT([gone.path isEqualToString:[fixture.installDir stringByAppendingPathComponent:@"Bundles/Gone.tmbundle"]]);
	OAK_ASSERT([gone.lastUpdated isEqualToDate:fixture.goneUpdated]);
	OAK_ASSERT(gone.name == nil);
}

// A .tmbundle on disk that no index knows is picked up from its info.plist as
// "Orphaned", with its install date read back from the xattr -installBundles:
// wrote. The directory listing is a "*.tm[Bb]undle" glob, so notes.txt is not
// mistaken for one.
void test_a_bundle_on_disk_in_no_index_is_orphaned ()
{
	fixture_t fixture;
	NSArray<Bundle*>* bundles = fixture.parse();
	Bundle* orphan = fixture_t::find(bundles, fixture.orphan);

	OAK_ASSERT([orphan.category isEqualToString:@"Orphaned"]);
	OAK_ASSERT(orphan.isInstalled == YES);
	OAK_ASSERT([orphan.path isEqualToString:[fixture.installDir stringByAppendingPathComponent:@"Bundles/Orphan.tmbundle"]]);
	OAK_ASSERT([orphan.name isEqualToString:@"Orphan"]);
	OAK_ASSERT([orphan.contactName isEqualToString:@"Oscar"]);
	OAK_ASSERT([orphan.contactEmail isEqualToString:@"oscar@example.com"]);
	OAK_ASSERT([orphan.summary isEqualToString:@"An orphan."]);
	OAK_ASSERT(orphan.downloadURL == nil);

	NSDateComponents* parts = [NSDateComponents new];
	parts.year = 2026; parts.month = 1; parts.day = 2; parts.hour = 3; parts.minute = 4; parts.second = 5;
	parts.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	NSDate* expected = [[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian] dateFromComponents:parts];
	OAK_ASSERT([orphan.lastUpdated isEqualToDate:expected]);

	for(Bundle* bundle in bundles)
		OAK_ASSERT(![bundle.name isEqualToString:@"Decoy"]);
}

// Re-parsing hands back the same Bundle objects for identifiers it already has,
// so bindings and selections survive an index update; new identifiers get new
// objects.
void test_previous_bundles_are_reused_by_identifier ()
{
	fixture_t fixture;
	Bundle* existing = [[Bundle alloc] initWithIdentifier:fixture.ruby];
	existing.name = @"stale name";

	NSArray<Bundle*>* bundles = fixture.parse(@{ fixture.ruby: existing });
	Bundle* ruby = fixture_t::find(bundles, fixture.ruby);

	OAK_ASSERT(ruby == existing);
	OAK_ASSERT([ruby.name isEqualToString:@"Ruby"]); // refreshed from the index
	OAK_ASSERT(fixture_t::find(bundles, fixture.rails) != existing);
}

// A binding on a reused bundle follows the parser's refresh of its fields. This
// is the pin the others cannot be: every other test sets a property from ObjC,
// where NSObject's automatic KVO fires whether or not the Swift declared
// `dynamic` — but the parser sets `name` from *Swift*, and only `dynamic`
// makes that set notify. Without it the Preferences table shows last week's
// names after every index update, with the whole suite green.
void test_reparsing_notifies_bindings_on_reused_bundles ()
{
	fixture_t fixture;
	Bundle* existing = [[Bundle alloc] initWithIdentifier:fixture.ruby];
	existing.name = @"stale name";

	NSTextField* field = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[field bind:NSValueBinding toObject:existing withKeyPath:@"name" options:nil];
	OAK_ASSERT_EQ(std::string(field.stringValue.UTF8String), std::string("stale name"));

	fixture.parse(@{ fixture.ruby: existing });
	OAK_ASSERT_EQ(std::string(field.stringValue.UTF8String), std::string("Ruby"));

	[field unbind:NSValueBinding];
}

// No remote index at all — first launch, or offline forever — still yields the
// local and on-disk bundles.
void test_a_missing_remote_index_is_an_empty_one ()
{
	fixture_t fixture;
	[NSFileManager.defaultManager removeItemAtPath:fixture.remoteIndexPath error:nil];
	NSArray<Bundle*>* bundles = fixture.parse();

	OAK_ASSERT_EQ((size_t)bundles.count, (size_t)3);
	OAK_ASSERT(fixture_t::find(bundles, fixture.ruby) != nil);
	OAK_ASSERT([fixture_t::find(bundles, fixture.ruby).category isEqualToString:@"Languages"]);
	OAK_ASSERT(fixture_t::find(bundles, fixture.gone) != nil);
	OAK_ASSERT(fixture_t::find(bundles, fixture.orphan) != nil);
}
