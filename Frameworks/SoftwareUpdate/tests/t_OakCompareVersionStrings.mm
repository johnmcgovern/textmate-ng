#import <SoftwareUpdate/SoftwareUpdate.h>

std::string to_s (NSComparisonResult result)
{
	switch(result)
	{
		case NSOrderedAscending:  return "NSOrderedAscending";
		case NSOrderedSame:       return "NSOrderedSame";
		case NSOrderedDescending: return "NSOrderedDescending";
	}
	return NULL_STR;
}

void test_trailing_zero ()
{
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2-beta",        @"2.0"),          NSOrderedAscending);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2.0-beta",      @"2.0"),          NSOrderedAscending);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2.0.0-beta",    @"2.0"),          NSOrderedAscending);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2",             @"2.0"),          NSOrderedSame);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2",             @"2.0+git.hash"), NSOrderedSame);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2+git.hash",    @"2.0"),          NSOrderedSame);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2.0.1-beta",    @"2.0"),          NSOrderedDescending);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2.1-beta",      @"2.0"),          NSOrderedDescending);
}

void test_null_string ()
{
	OAK_ASSERT_EQ(OakCompareVersionStrings(nil, @"2.0"), NSOrderedAscending);
	OAK_ASSERT_NE(OakCompareVersionStrings(nil, @"2.0"), NSOrderedSame);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2.0", nil), NSOrderedDescending);
}

// TextMate-NG's own scheme: calendar year.month with a running -alpha counter,
// claimed in the alpha.1 release notes to "order correctly" against upstream and
// against itself. Written on the day the fork first crossed a month boundary
// (2026.8 -> 2026.9), because that is the first time the claim was load-bearing.
void test_calendar_versioning ()
{
	// Every version this fork has actually shipped, in release order, plus the
	// rollovers that have not happened yet: month 9 -> 10, where a string sort
	// would put 10 before 9, and December -> January, where the year carries.
	NSArray<NSString*>* released = @[
		@"2026.7-alpha.2",  @"2026.7-alpha.3",  @"2026.7-alpha.4",  @"2026.7-alpha.5",
		@"2026.7-alpha.6",  @"2026.7-alpha.7",  @"2026.7-alpha.8",  @"2026.7-alpha.9",
		@"2026.7-alpha.10", @"2026.7-alpha.11", @"2026.8-alpha.12", @"2026.8-alpha.13",
		@"2026.8-alpha.14", @"2026.8-alpha.15", @"2026.8-alpha.16", @"2026.8-alpha.17",
		@"2026.8-alpha.18", @"2026.8-alpha.19", @"2026.8-alpha.20", @"2026.9-alpha.21",
		@"2026.10-alpha.22", @"2026.12-alpha.23", @"2027.1-alpha.24",
	];

	for(NSUInteger i = 0; i < released.count; ++i)
	{
		for(NSUInteger j = 0; j < released.count; ++j)
		{
			NSString* msg = [NSString stringWithFormat:@"%@ vs %@", released[i], released[j]];
			NSComparisonResult expected = i < j ? NSOrderedAscending : (i == j ? NSOrderedSame : NSOrderedDescending);
			OAK_MASSERT_EQ(msg.UTF8String, OakCompareVersionStrings(released[i], released[j]), expected);
		}
	}

	// A month's final release is newer than every alpha in that month, and a
	// patch release within the month is newer still.
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2026.9-alpha.21", @"2026.9"),   NSOrderedAscending);
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2026.9",          @"2026.9.1"), NSOrderedAscending);

	// And the whole scheme is newer than upstream TextMate, which is the reason
	// software update and bundle requirements were left alone: 2026 > 2.
	OAK_ASSERT_EQ(OakCompareVersionStrings(@"2.0.23", @"2026.9-alpha.21"), NSOrderedAscending);
}

void test_exhaustive ()
{
	NSMutableArray<NSString*>* versions = [NSMutableArray array];
	for(NSString* number in @[ @"1", @"1.01", @"1.1.1", @"1.1.2", @"1.2", @"1.2.1", @"1.10", @"2", @"2.1", @"2.1.1", @"2.2" ])
	{
		for(NSString* suffix in @[ @"-alpha", @"-alpha.1", @"-alpha.2", @"-alpha.3+debug", @"-beta", @"-beta.1", @"-beta.2", @"-rc.1", @"" ])
			[versions addObject:[number stringByAppendingString:suffix]];
	}

	for(NSUInteger i = 0; i < versions.count; ++i)
	{
		for(NSUInteger j = i; j < versions.count; ++j)
		{
			for(NSString* lhs in @[ versions[i], [versions[i] stringByAppendingString:@"+git.c0de"] ])
			{
				for(NSString* rhs in @[ versions[j], [versions[j] stringByAppendingString:@"+git.b337"] ])
				{
					NSString* msg = [NSString stringWithFormat:@"%@ %c %@", lhs, i < j ? '<' : (i == j ? '=' : '>'), rhs];
					if(i < j)  { OAK_MASSERT_EQ(msg.UTF8String, OakCompareVersionStrings(lhs, rhs), NSOrderedAscending);  }
					if(i == j) { OAK_MASSERT_EQ(msg.UTF8String, OakCompareVersionStrings(lhs, rhs), NSOrderedSame);       }
					if(i > j)  { OAK_MASSERT_EQ(msg.UTF8String, OakCompareVersionStrings(lhs, rhs), NSOrderedDescending); }
				}
			}
		}
	}
}
