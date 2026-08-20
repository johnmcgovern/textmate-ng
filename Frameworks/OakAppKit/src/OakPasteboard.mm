#import "OakPasteboard.h"
#import "OakPasteboardSelector.h"
#import <crash/info.h>
#import <ns/ns.h>
#import <oak/oak.h>
#import <oak/debug.h>
#import "OakPasteboardDatabase.h"
#import "OakPasteboardIdleObserver.h"

static os_log_t const kLogSQLite     = os_log_create("Pasteboard", "sqlite");
static os_log_t const kLogPasteboard = os_log_create("Pasteboard", "history");

// OakPasteboardDidChangeNotification and the five find-option / find-default
// constants moved to OakPasteboardConstants.mm (rule 19). The pasteboard-type and
// clipboard-history names below are used only in this file and stay with it.

NSString* const OakReplacePboard                   = @"OakReplacePboard";
NSString* const OakPasteboardOptionsPboardType     = @"OakPasteboardOptionsPboardType";

NSString* const kUserDefaultsClipboardHistoryKeepAtLeast       = @"clipboardHistoryKeepAtLeast";
NSString* const kUserDefaultsClipboardHistoryKeepAtMost        = @"clipboardHistoryKeepAtMost";
NSString* const kUserDefaultsClipboardHistoryDaysToKeep        = @"clipboardHistoryDaysToKeep";

// ======================
// = OakPasteboardEntry =
// ======================

@implementation OakPasteboardEntry
- (id)initWithStrings:(NSArray<NSString*>*)strings options:(NSDictionary*)options flagged:(BOOL)flagged
{
	if(self = [self init])
	{
		_strings = strings;
		_options = options;
		_flagged = flagged;
	}
	return self;
}

- (NSString*)string
{
	return [_strings componentsJoinedByString:@"\n"];
}

- (NSUInteger)historyId
{
	return [_options[@"historyId"] integerValue];
}

- (BOOL)isEqual:(id)otherEntry
{
	if([otherEntry isKindOfClass:[OakPasteboardEntry class]])
		return self.historyId == ((OakPasteboardEntry*)otherEntry).historyId;
	return NO;
}

- (NSString*)description
{
	return [NSString stringWithFormat:@"<%@: %@ [%@]>", [self class], [_strings componentsJoinedByString:@"|"], [_options.allKeys componentsJoinedByString:@"|"]];
}

- (void)setFlagged:(BOOL)newFlagged
{
	_flagged = newFlagged;
	if(NSUInteger historyId = self.historyId)
	{
		char const* query = nullptr;
		if(_flagged)
				query = "INSERT INTO flags (id) VALUES (:historyId);";
		else	query = "DELETE FROM flags WHERE id = :historyId;";
		[[OakPasteboardDatabase sharedInstance] executeQuery:@(query) variables:@{ @":historyId": @(historyId) }];
	}
}

- (BOOL)fullWordMatch       { return [self.options[OakFindFullWordsOption] boolValue]; };
- (BOOL)ignoreWhitespace    { return [self.options[OakFindIgnoreWhitespaceOption] boolValue]; };
- (BOOL)regularExpression   { return [self.options[OakFindRegularExpressionOption] boolValue]; };
// -findOptions (find::options_t) moved to the OakPasteboardEntryFindOptions category (rule 17).
@end

@interface OakPasteboard () <OakPasteboardIdleObserving>
@property (nonatomic) NSInteger changeCount;
@property (nonatomic, readonly) NSPasteboard* pasteboard;
@property (nonatomic, readonly) BOOL avoidsDuplicates;
- (void)checkForExternalPasteboardChanges;
@end

@implementation OakPasteboard
+ (void)initialize
{
	static dispatch_once_t onceToken = 0;
	dispatch_once(&onceToken, ^{
		[NSUserDefaults.standardUserDefaults registerDefaults:@{
			kUserDefaultsClipboardHistoryKeepAtLeast:  @25,
			kUserDefaultsClipboardHistoryKeepAtMost:  @500,
			kUserDefaultsClipboardHistoryDaysToKeep:   @30,
		}];

		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidBecomeActiveNotification:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidResignActiveNotification:) name:NSApplicationDidResignActiveNotification object:NSApp];
	});
}

+ (void)applicationDidBecomeActiveNotification:(id)sender
{
	[OakPasteboardIdleObserver.sharedInstance start];
}

+ (void)applicationDidResignActiveNotification:(id)sender
{
	[OakPasteboardIdleObserver.sharedInstance stop];
}

+ (OakPasteboard*)pasteboardWithName:(NSString*)aName systemPasteboard:(NSPasteboard*)pboard avoidsDuplicates:(BOOL)flag
{
	static NSMutableDictionary<NSString*, OakPasteboard*>* sharedInstances = [NSMutableDictionary dictionary];
	if(!sharedInstances[aName])
	{
		OakPasteboard* res = [[OakPasteboard alloc] initWithName:aName systemPasteboard:pboard avoidsDuplicates:flag];
		sharedInstances[aName] = res;
		[OakPasteboardIdleObserver.sharedInstance addObject:res];
	}
	return sharedInstances[aName];
}

+ (OakPasteboard*)generalPasteboard  { return [OakPasteboard pasteboardWithName:@"General" systemPasteboard:[NSPasteboard pasteboardWithName:NSGeneralPboard]  avoidsDuplicates:NO];  }
+ (OakPasteboard*)findPasteboard     { return [OakPasteboard pasteboardWithName:@"Find"    systemPasteboard:[NSPasteboard pasteboardWithName:NSFindPboard]     avoidsDuplicates:YES]; }
+ (OakPasteboard*)replacePasteboard  { return [OakPasteboard pasteboardWithName:@"Replace" systemPasteboard:[NSPasteboard pasteboardWithName:OakReplacePboard] avoidsDuplicates:YES]; }

- (instancetype)initWithName:(NSString*)aName systemPasteboard:(NSPasteboard*)pboard avoidsDuplicates:(BOOL)flag
{
	if(self = [self init])
	{
		_name             = aName;
		_pasteboard       = pboard;
		_avoidsDuplicates = flag;
	}
	return self;
}

- (void)ensurePasteboardItemIsInDatabase
{
	if([self.pasteboard availableTypeFromArray:@[ OakPasteboardOptionsPboardType ]])
	{
		// Already in database, but check that historyId is valid
		NSDictionary* options = [self.pasteboard propertyListForType:OakPasteboardOptionsPboardType];
		if(NSNumber* historyId = options[@"historyId"])
		{
			char const* query = "SELECT id FROM history WHERE id = :history_id";
			if(NSDictionary* row = [[[OakPasteboardDatabase sharedInstance] executeQuery:@(query) variables:@{ @":history_id": historyId }] firstObject])
				return;
		}
	}

	// Do not add these types to database, see http://nspasteboard.org
	if([self.pasteboard availableTypeFromArray:@[ @"org.nspasteboard.TransientType", @"org.nspasteboard.ConcealedType", @"org.nspasteboard.AutoGeneratedType" ]])
		return;

	NSArray<NSString*>* strings = [self.pasteboard readObjectsForClasses:@[ [NSString class] ] options:nil];
	if(strings.count == 0)
	{
		os_log_info(kLogPasteboard, "No strings on %{public}@ pasteboard. Available types: %{public}@", _name, self.pasteboard.types);
		return;
	}

	OakPasteboardEntry* lastEntry = self.lastEntry;
	if(lastEntry && [lastEntry.strings isEqual:strings])
		return;

	if(self.changeCount == self.pasteboard.changeCount)
		os_log_error(kLogPasteboard, "New content on %{public}@ pasteboard with stale change count (%lu): %{public}@", _name, self.pasteboard.changeCount, [strings componentsJoinedByString:@""]);

	[self addEntryWithStrings:strings options:nil];
}

- (void)updatePasteboardWithEntry:(OakPasteboardEntry*)pasteboardEntry
{
	self.changeCount = [self.pasteboard clearContents];

	if(pasteboardEntry)
	{
		[self.pasteboard writeObjects:pasteboardEntry.strings];
		[self.pasteboard setPropertyList:pasteboardEntry.options forType:OakPasteboardOptionsPboardType];
	}

	[NSNotificationCenter.defaultCenter postNotificationName:OakPasteboardDidChangeNotification object:self];
}

- (void)updatePasteboardWithEntries:(NSArray<OakPasteboardEntry*>*)pasteboardEntries
{
	NSArray<NSString*>* historyIds = [pasteboardEntries valueForKeyPath:@"historyId"];
	NSMutableDictionary* options = [NSMutableDictionary dictionary];
	options[@"historyIds"] = historyIds;

	NSArray<NSString*>* strings = [pasteboardEntries valueForKeyPath:@"@unionOfArrays.strings"];
	NSString* string;
	if([self isEqual:OakPasteboard.findPasteboard])
	{
		string = [strings componentsJoinedByString:@"|"];
		options[OakFindRegularExpressionOption] = @YES;
	}
	else
	{
		string = [strings componentsJoinedByString:@"\n"];
	}

	[self.pasteboard declareTypes:@[ NSPasteboardTypeString, OakPasteboardOptionsPboardType, @"org.nspasteboard.AutoGeneratedType" ] owner:nil];
	[self.pasteboard setString:string forType:NSPasteboardTypeString];
	[self.pasteboard setPropertyList:options forType:OakPasteboardOptionsPboardType];
	[self.pasteboard setPropertyList:@YES forType:@"org.nspasteboard.AutoGeneratedType"];

	self.changeCount = self.pasteboard.changeCount;

	[NSNotificationCenter.defaultCenter postNotificationName:OakPasteboardDidChangeNotification object:self];
}

- (OakPasteboardEntry*)currentEntry
{
	[self ensurePasteboardItemIsInDatabase];

	NSArray<NSString*>* strings = [self.pasteboard readObjectsForClasses:@[ [NSString class] ] options:nil];
	NSDictionary* options = [self.pasteboard propertyListForType:OakPasteboardOptionsPboardType];
	if(!options && [self.lastEntry.strings isEqual:strings])
		options = self.lastEntry.options;
	return strings.count ? [[OakPasteboardEntry alloc] initWithStrings:strings options:options flagged:NO] : nil;
}

- (OakPasteboardEntry*)fetchEntryWithHistoryId:(NSUInteger)historyId
{
	if(!historyId)
		return nil;

	char const* query = "SELECT options, flags.id AS flagged, string FROM history LEFT JOIN flags USING (id) LEFT JOIN groups ON history.id = history_id LEFT JOIN strings ON strings.id = string_id WHERE history.id = :history_id AND string IS NOT NULL;";
	NSArray* rows = [[OakPasteboardDatabase sharedInstance] executeQuery:@(query) variables:@{ @":history_id": @(historyId) }];
	NSArray* strings = [rows valueForKeyPath:@"string"];

	NSMutableDictionary* options = [NSMutableDictionary dictionaryWithObject:@(historyId) forKey:@"historyId"];
	if(NSData* optionsData = rows.firstObject[@"options"])
		[options addEntriesFromDictionary:[NSPropertyListSerialization propertyListWithData:optionsData options:NSPropertyListImmutable format:nil error:nil]];

	return [[OakPasteboardEntry alloc] initWithStrings:strings options:options flagged:rows.firstObject[@"flagged"] ? YES : NO];
}

- (NSArray<OakPasteboardEntry*>*)entries
{
	NSMutableArray<OakPasteboardEntry*>* res = [NSMutableArray array];

	NSNumber* lastHistoryId;
	NSMutableArray* strings;

	char const* query = "SELECT history.id AS history_id, options, flags.id AS flagged, string FROM history LEFT JOIN clipboards ON clipboards.id = clipboard_id LEFT JOIN flags USING (id) LEFT JOIN groups ON history.id = history_id LEFT JOIN strings ON strings.id = string_id WHERE name = :name ORDER BY history.id DESC;";
	for(NSDictionary* row in [[OakPasteboardDatabase sharedInstance] executeQuery:@(query) variables:@{ @":name": _name }])
	{
		NSNumber* historyId = row[@"history_id"];
		if([lastHistoryId isEqual:historyId])
		{
			[strings addObject:row[@"string"]];
		}
		else
		{
			NSMutableDictionary* options = [NSMutableDictionary dictionaryWithObject:historyId forKey:@"historyId"];
			if(NSData* optionsData = row[@"options"])
				[options addEntriesFromDictionary:[NSPropertyListSerialization propertyListWithData:optionsData options:NSPropertyListImmutable format:nil error:nil]];
			strings = [NSMutableArray arrayWithObject:row[@"string"]];
			[res addObject:[[OakPasteboardEntry alloc] initWithStrings:strings options:options flagged:row[@"flagged"] ? YES : NO]];
		}
		lastHistoryId = historyId;
	}

	return res;
}

- (OakPasteboardEntry*)firstEntry
{
	char const* query = "SELECT MIN(history.id) AS history_id FROM history LEFT JOIN clipboards ON clipboards.id = clipboard_id WHERE name = :name;";
	if(NSDictionary* row = [[[OakPasteboardDatabase sharedInstance] executeQuery:@(query) variables:@{ @":name": _name }] firstObject])
		return [self fetchEntryWithHistoryId:[row[@"history_id"] integerValue]];
	return nil;
}

- (OakPasteboardEntry*)lastEntry
{
	char const* query = "SELECT MAX(history.id) AS history_id FROM history LEFT JOIN clipboards ON clipboards.id = clipboard_id WHERE name = :name;";
	if(NSDictionary* row = [[[OakPasteboardDatabase sharedInstance] executeQuery:@(query) variables:@{ @":name": _name }] firstObject])
		return [self fetchEntryWithHistoryId:[row[@"history_id"] integerValue]];
	return nil;
}

- (OakPasteboardEntry*)entryBefore:(OakPasteboardEntry*)laterEntry
{
	char const* query = "SELECT MAX(history.id) AS history_id FROM history LEFT JOIN clipboards ON clipboards.id = clipboard_id WHERE history.id < :history_id AND name = :name;";
	if(NSDictionary* row = [[[OakPasteboardDatabase sharedInstance] executeQuery:@(query) variables:@{ @":name": _name, @":history_id": @(laterEntry.historyId) }] firstObject])
		return [self fetchEntryWithHistoryId:[row[@"history_id"] integerValue]];
	return nil;
}

- (OakPasteboardEntry*)entryAfter:(OakPasteboardEntry*)earlierEntry
{
	char const* query = "SELECT MIN(history.id) AS history_id FROM history LEFT JOIN clipboards ON clipboards.id = clipboard_id WHERE history.id > :history_id AND name = :name;";
	if(NSDictionary* row = [[[OakPasteboardDatabase sharedInstance] executeQuery:@(query) variables:@{ @":name": _name, @":history_id": @(earlierEntry.historyId) }] firstObject])
		return [self fetchEntryWithHistoryId:[row[@"history_id"] integerValue]];
	return nil;
}

- (OakPasteboardEntry*)addEntryWithStrings:(NSArray<NSString*>*)someStrings options:(NSDictionary*)someOptions
{
	if(someStrings.count == 0)
	{
		os_log_error(kLogPasteboard, "Adding empty array in [%{public}@ addEntryWithStrings:options:updatePasteboard:]", [self class]);
		return nil;
	}

	NSArray* keys = [someOptions keysOfEntriesPassingTest:^(id key, id obj, BOOL* stop){ return BOOL(![obj isKindOfClass:[NSNumber class]] || [obj boolValue]); }].allObjects;
	NSMutableDictionary* options = keys.count ? [NSMutableDictionary dictionaryWithObjects:[someOptions objectsForKeys:keys notFoundMarker:@NO] forKeys:keys] : [NSMutableDictionary dictionary];

	NSMutableArray* stringIds = [NSMutableArray array];
	NSMutableArray* values = [NSMutableArray array];
	for(NSString* str in someStrings)
	{
		char const* query = "INSERT INTO strings ('string') VALUES (:string); SELECT id FROM strings WHERE string = :string;";
		if(NSDictionary* row = [[[OakPasteboardDatabase sharedInstance] executeQuery:@(query) variables:@{ @":string": str }] firstObject])
		{
			[stringIds addObject:row[@"id"]];
			[values addObject:[NSString stringWithFormat:@"((SELECT seq FROM sqlite_sequence WHERE name = 'history'), %@)", row[@"id"]]];
		}
	}

	// NSNull binds NULL; the std::map used to carry a nil id for the empty/failed
	// options case, which the store binds the same way (rule 6, kept faithful).
	NSData* optionsData = options.count ? [NSPropertyListSerialization dataWithPropertyList:options format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil] : nil;
	NSDictionary* variables = @{
		@":name":    _name,
		@":options": (optionsData ?: (id)NSNull.null),
	};

	BOOL isFlagged = NO;
	if(self.avoidsDuplicates)
	{
		NSString* query = [NSString stringWithFormat:@"SELECT COUNT(*) AS flagCount FROM (SELECT history_id, COUNT(*) AS count FROM history LEFT JOIN flags USING (id) LEFT JOIN groups ON history_id = history.id LEFT JOIN clipboards ON clipboard_id = clipboards.id LEFT JOIN strings ON strings.id = string_id WHERE name = :name AND string_id IN (%@) AND flags.id IS NOT NULL GROUP BY history_id HAVING count = %lu);", [stringIds componentsJoinedByString:@", "], stringIds.count];
		if(NSDictionary* res = [[[OakPasteboardDatabase sharedInstance] executeQuery:query variables:variables] firstObject])
			isFlagged = [res[@"flagCount"] integerValue] ? YES : NO;
	}

	char const* queryFormat =
		"BEGIN TRANSACTION;"
		"INSERT INTO clipboards ('name') VALUES (:name);"
		"%s"
		"INSERT INTO history ('options', 'clipboard_id') SELECT :options, id FROM clipboards WHERE name = :name;"
		"SELECT LAST_INSERT_ROWID() AS history_id;"
		"%s"
		"INSERT INTO groups ('history_id', 'string_id') VALUES %s;"
		"END TRANSACTION;"
		;

	NSString* deleteQuery = self.avoidsDuplicates ? [NSString stringWithFormat:@"DELETE FROM history WHERE id IN (SELECT history_id FROM (SELECT history_id, COUNT(*) AS count FROM groups LEFT JOIN history ON history_id = history.id LEFT JOIN clipboards ON clipboard_id = clipboards.id LEFT JOIN strings ON string_id = strings.id WHERE name = :name AND string_id IN (%@) GROUP BY history_id HAVING count = %lu));", [stringIds componentsJoinedByString:@", "], stringIds.count] : @"";
	NSString* flagQuery = isFlagged ? @"INSERT INTO flags (id) VALUES (LAST_INSERT_ROWID());" : @"";
	std::string query = text::format(queryFormat, deleteQuery.UTF8String, flagQuery.UTF8String, [values componentsJoinedByString:@","].UTF8String);

	if(NSDictionary* res = [[[OakPasteboardDatabase sharedInstance] executeQuery:@(query.c_str()) variables:variables] firstObject])
		options[@"historyId"] = res[@"history_id"];

	[self pruneHistory:self];

	return [[OakPasteboardEntry alloc] initWithStrings:someStrings options:options flagged:NO];
}

- (void)addEntryWithString:(NSString*)aString options:(NSDictionary*)someOptions
{
	if(OakPasteboardEntry* entry = [self addEntryWithStrings:@[ aString ] options:someOptions])
		[self updatePasteboardWithEntry:entry];
}

- (void)addEntryWithString:(NSString*)aString
{
	[self addEntryWithString:aString options:nil];
}

// ====================
// = Removing Entries =
// ====================

- (void)removeEntries:(NSArray<OakPasteboardEntry*>*)pasteboardEntries
{
	if(pasteboardEntries.count)
	{
		NSArray* historyIds = [pasteboardEntries valueForKeyPath:@"historyId"];
		NSString* query = [NSString stringWithFormat:@"DELETE FROM history WHERE id IN (%@);", [historyIds componentsJoinedByString:@", "]];
		[[OakPasteboardDatabase sharedInstance] executeQuery:query];

		if([self.pasteboard availableTypeFromArray:@[ OakPasteboardOptionsPboardType ]])
		{
			NSDictionary* options = [self.pasteboard propertyListForType:OakPasteboardOptionsPboardType];
			if(NSNumber* historyId = options[@"historyId"])
			{
				if([historyIds containsObject:historyId])
				{
					NSArray<NSString*>* strings = [self.pasteboard readObjectsForClasses:@[ [NSString class] ] options:nil];
					NSMutableDictionary* mutableOptions = [options mutableCopy];
					[mutableOptions removeObjectForKey:@"historyId"];

					self.changeCount = [self.pasteboard clearContents];
					[self.pasteboard writeObjects:strings];
					[self.pasteboard setPropertyList:mutableOptions forType:OakPasteboardOptionsPboardType];
				}
			}
		}
	}
}

- (void)removeAllEntries
{
	char const* query = "DELETE FROM history WHERE clipboard_id = (SELECT id FROM clipboards WHERE name = :name) AND id NOT IN (SELECT id FROM flags);";
	[[OakPasteboardDatabase sharedInstance] executeQuery:@(query) variables:@{ @":name": _name }];
}

- (void)checkForExternalPasteboardChanges
{
	// Do not touch clipboard unless we are active as CFPasteboardCopyData can stall
	// See https://lists.macromates.com/textmate/2019-August/041109.html
	if(!NSApp.isActive)
		return;

	if(self.changeCount != self.pasteboard.changeCount)
	{
		[self ensurePasteboardItemIsInDatabase];
		self.changeCount = self.pasteboard.changeCount;
		[NSNotificationCenter.defaultCenter postNotificationName:OakPasteboardDidChangeNotification object:self];
	}
}

- (void)pruneHistory:(id)sender
{
	NSInteger keepAtLeast = [NSUserDefaults.standardUserDefaults integerForKey:kUserDefaultsClipboardHistoryKeepAtLeast];
	NSInteger keepAtMost  = [NSUserDefaults.standardUserDefaults integerForKey:kUserDefaultsClipboardHistoryKeepAtMost];
	CGFloat daysToKeep    = [NSUserDefaults.standardUserDefaults floatForKey:kUserDefaultsClipboardHistoryDaysToKeep];

	if(NSDictionary* row = [[[OakPasteboardDatabase sharedInstance] executeQuery:@"SELECT COUNT(*) AS count FROM history LEFT JOIN flags USING (id) LEFT JOIN clipboards ON clipboards.id = clipboard_id WHERE flags.id IS NULL AND name = :name" variables:@{ @":name": _name }] firstObject])
	{
		NSUInteger count = [row[@"count"] integerValue];

		NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
		dateFormatter.dateFormat = @"YYYY-MM-dd HH:mm:ss";
		dateFormatter.timeZone   = [NSTimeZone timeZoneForSecondsFromGMT:0];
		NSString* keepUntil = [NSString stringWithFormat:@"\"%@\"", [dateFormatter stringFromDate:[NSDate dateWithTimeIntervalSinceNow:-daysToKeep*24*60*60]]];

		if(keepAtLeast && keepAtLeast <= count)
		{
			char const* query = "SELECT date FROM history LEFT JOIN flags USING (id) LEFT JOIN clipboards ON clipboards.id = clipboard_id WHERE flags.id IS NULL AND name = :name ORDER BY history.id LIMIT :offset, 1;";
			if(NSDictionary* row = [[[OakPasteboardDatabase sharedInstance] executeQuery:@(query) variables:@{ @":name": _name, @":offset": @(count - keepAtLeast) }] firstObject])
				keepUntil = [NSString stringWithFormat:@"MIN(\"%@\", %@)", row[@"date"], keepUntil];
		}

		if(keepAtMost && keepAtMost <= count)
		{
			char const* query = "SELECT date FROM history LEFT JOIN flags USING (id) LEFT JOIN clipboards ON clipboards.id = clipboard_id WHERE flags.id IS NULL AND name = :name ORDER BY history.id LIMIT :offset, 1;";
			if(NSDictionary* row = [[[OakPasteboardDatabase sharedInstance] executeQuery:@(query) variables:@{ @":name": _name, @":offset": @(count - keepAtMost) }] firstObject])
				keepUntil = [NSString stringWithFormat:@"MAX(\"%@\", %@)", row[@"date"], keepUntil];
		}

		char const* queryFormat =
			"SELECT COUNT(*) AS count FROM history LEFT JOIN flags USING (id) WHERE date < %1$s AND flags.id IS NULL AND clipboard_id = (SELECT id FROM clipboards WHERE name = :name);"
			"DELETE FROM history WHERE id IN (SELECT history.id FROM history LEFT JOIN flags USING (id) WHERE date < %1$s AND flags.id IS NULL AND clipboard_id = (SELECT id FROM clipboards WHERE name = :name));"
			"SELECT COUNT(*) AS count FROM strings LEFT JOIN groups ON string_id = strings.id WHERE string_id IS NULL;"
			"DELETE FROM strings WHERE id IN (SELECT strings.id FROM strings LEFT JOIN groups ON string_id = strings.id WHERE string_id IS NULL);"
			;

		std::string query = text::format(queryFormat, keepUntil.UTF8String);
		if(NSArray* rows = [[OakPasteboardDatabase sharedInstance] executeQuery:@(query.c_str()) variables:@{ @":name": _name }])
		{
			if(os_log_info_enabled(kLogSQLite))
			{
				NSNumber* deletedItemsCount   = rows[0][0][@"count"];
				NSNumber* deletedStringsCount = rows[1][0][@"count"];
				if(deletedItemsCount.integerValue || deletedStringsCount.integerValue)
				{
					os_log_info(kLogSQLite, "There are a total of %lu %{public}@ pasteboard items, we must keep at least/most %lu/%lu items", count, _name, keepAtLeast, keepAtMost);
					os_log_info(kLogSQLite, "Deleted %{public}@ %{public}@ pasteboard item(s) and garbage collected %{public}@ string(s)", deletedItemsCount, _name, deletedStringsCount);
				}
			}
		}
	}
}

- (OakPasteboardEntry*)previous
{
	OakPasteboardEntry* entry = [self entryBefore:self.currentEntry] ?: self.firstEntry ?: self.currentEntry;
	[self updatePasteboardWithEntry:entry];
	return entry;
}

- (OakPasteboardEntry*)current
{
	return self.currentEntry;
}

- (OakPasteboardEntry*)next
{
	OakPasteboardEntry* entry = [self entryAfter:self.currentEntry] ?: self.lastEntry ?: self.currentEntry;
	[self updatePasteboardWithEntry:entry];
	return entry;
}

- (void)selectItemAtPosition:(NSPoint)location withWidth:(CGFloat)width respondToSingleClick:(BOOL)singleClick
{
	NSArray<OakPasteboardEntry*>* entries = self.entries;

	NSUInteger selectedRow = self.currentEntry ? [entries indexOfObject:self.currentEntry] : 0;
	OakPasteboardSelector* pasteboardSelector = OakPasteboardSelector.sharedInstance;
	[pasteboardSelector setEntries:entries];
	[pasteboardSelector setIndex:selectedRow == NSNotFound ? 0 : selectedRow];
	if(width)
		[pasteboardSelector setWidth:width];
	if(singleClick)
		[pasteboardSelector setPerformsActionOnSingleClick];

	NSInteger newSelection = [pasteboardSelector showAtLocation:location];
	NSArray* newEntries = [pasteboardSelector entries];

	NSMutableArray* remove = [NSMutableArray array];
	NSSet* keep = [NSSet setWithArray:newEntries];
	for(OakPasteboardEntry* entry in entries)
	{
		if(![keep containsObject:entry])
			[remove addObject:entry];
	}
	[self removeEntries:remove];

	if(newSelection != -1)
		[self updatePasteboardWithEntry:[newEntries objectAtIndex:newSelection]];
}

- (void)selectItemForControl:(NSView*)controlView
{
	NSPoint origin = [controlView.window convertRectToScreen:[controlView convertRect:controlView.bounds toView:nil]].origin;
	[self selectItemAtPosition:origin withWidth:NSWidth(controlView.frame) respondToSingleClick:YES];
}
@end
