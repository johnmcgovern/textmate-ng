#import "OakPasteboardDatabase.h"
#import <crash/info.h>
#import <ns/ns.h>
#import <oak/oak.h>
#import <oak/debug.h>
#import <sqlite3.h>

// Moved out of OakPasteboard.mm (rule 6): the SQLite C API, the @encode→bind
// std::function dispatch table and ColumnsAsDictionary are byte-for-byte the same;
// only RunSQLStatement's `variables` parameter changed from a
// std::map<std::string, id> to an NSDictionary so the class's public API is
// C++-free, and +[OakPasteboard SQLDatabase]/+databaseURL became the -database /
// -databaseURL of this shared object.

static os_log_t const kLogSQLite     = os_log_create("Pasteboard", "sqlite");
static os_log_t const kLogPasteboard = os_log_create("Pasteboard", "history");

// Used only here now (the persistent-history toggle is a database concern).
static NSString* const kUserDefaultsDisablePersistentClipboardHistory = @"disablePersistentClipboardHistory";

static NSDictionary* ColumnsAsDictionary (sqlite3_stmt* stmt)
{
	NSMutableDictionary* item = [NSMutableDictionary dictionary];
	for(int i = 0; i < sqlite3_data_count(stmt); ++i)
	{
		id value;
		switch(sqlite3_column_type(stmt, i))
		{
			case SQLITE_INTEGER: value = [NSNumber numberWithInt:sqlite3_column_int(stmt, i)]; break;
			case SQLITE_FLOAT:   value = [NSNumber numberWithDouble:sqlite3_column_double(stmt, i)]; break;
			case SQLITE_TEXT:    value = [NSString stringWithUTF8String:(char const*)sqlite3_column_text(stmt, i)]; break;
			case SQLITE_BLOB:    value = [NSData dataWithBytes:sqlite3_column_blob(stmt, i) length:sqlite3_column_bytes(stmt, i)]; break;
			case SQLITE_NULL:    value = nil; break;
		}

		if(value)
			item[[NSString stringWithUTF8String:sqlite3_column_name(stmt, i)]] = value;
	}
	return item;
}

// Verbatim from OakPasteboard.mm apart from the variables container: an NSDictionary
// of `:name` → value, where a missing key is "no binding" and NSNull binds NULL (the
// std::map used to carry a nil id for the same NULL case; call sites now pass NSNull).
static NSArray* RunSQLStatement (sqlite3* db, char const* query, NSDictionary* variables = @{})
{
	NSMutableArray<NSMutableArray<NSDictionary*>*>* resultSet = [NSMutableArray array];

	BOOL res = YES;
	while(*query && res)
	{
		sqlite3_stmt* stmt = nullptr;
		char const* nextQuery = nullptr;
		if(sqlite3_prepare_v2(db, query, -1, &stmt, &nextQuery) == SQLITE_OK)
		{
			NSMutableArray<NSDictionary*>* rows;

			for(int i = 0; i < sqlite3_bind_parameter_count(stmt); ++i)
			{
				id value = variables[@(sqlite3_bind_parameter_name(stmt, i+1))];
				if(value)
				{
					if([value isKindOfClass:[NSNull class]])
					{
						sqlite3_bind_null(stmt, i+1);
					}
					else if([value isKindOfClass:[NSString class]])
					{
						sqlite3_bind_text(stmt, i+1, [value UTF8String], -1, SQLITE_STATIC);
					}
					else if([value isKindOfClass:[NSData class]])
					{
						sqlite3_bind_blob(stmt, i+1, [value bytes], [value length], SQLITE_STATIC);
					}
					else if([value isKindOfClass:[NSNumber class]])
					{
						static std::map<std::string, std::function<int(sqlite3_stmt*, int, id)>> const typeMapping = {
							{ @encode(BOOL),               [](sqlite3_stmt* stmt, int i, NSNumber* value) -> int { return sqlite3_bind_int(stmt, i, value.boolValue ? 1 : 0);       } },
							{ @encode(char),               [](sqlite3_stmt* stmt, int i, NSNumber* value) -> int { return sqlite3_bind_int(stmt, i, value.charValue);               } },
							{ @encode(unsigned char),      [](sqlite3_stmt* stmt, int i, NSNumber* value) -> int { return sqlite3_bind_int(stmt, i, value.unsignedCharValue);       } },
							{ @encode(short),              [](sqlite3_stmt* stmt, int i, NSNumber* value) -> int { return sqlite3_bind_int(stmt, i, value.shortValue);              } },
							{ @encode(unsigned short),     [](sqlite3_stmt* stmt, int i, NSNumber* value) -> int { return sqlite3_bind_int(stmt, i, value.unsignedShortValue);      } },
							{ @encode(int),                [](sqlite3_stmt* stmt, int i, NSNumber* value) -> int { return sqlite3_bind_int64(stmt, i, value.intValue);              } },
							{ @encode(unsigned int),       [](sqlite3_stmt* stmt, int i, NSNumber* value) -> int { return sqlite3_bind_int64(stmt, i, value.unsignedIntValue);      } },
							{ @encode(long),               [](sqlite3_stmt* stmt, int i, NSNumber* value) -> int { return sqlite3_bind_int64(stmt, i, value.longValue);             } },
							{ @encode(unsigned long),      [](sqlite3_stmt* stmt, int i, NSNumber* value) -> int { return sqlite3_bind_int64(stmt, i, value.unsignedLongValue);     } },
							{ @encode(long long),          [](sqlite3_stmt* stmt, int i, NSNumber* value) -> int { return sqlite3_bind_int64(stmt, i, value.longLongValue);         } },
							{ @encode(unsigned long long), [](sqlite3_stmt* stmt, int i, NSNumber* value) -> int { return sqlite3_bind_int64(stmt, i, value.unsignedLongLongValue); } },
							{ @encode(float),              [](sqlite3_stmt* stmt, int i, NSNumber* value) -> int { return sqlite3_bind_double(stmt, i, value.floatValue);           } },
							{ @encode(double),             [](sqlite3_stmt* stmt, int i, NSNumber* value) -> int { return sqlite3_bind_double(stmt, i, value.doubleValue);          } },
						};

						auto pair = [value objCType] ? typeMapping.find([value objCType]) : typeMapping.end();
						if(pair != typeMapping.end())
								pair->second(stmt, i+1, value);
						else	sqlite3_bind_text(stmt, i+1, [[value stringValue] UTF8String], -1, nullptr);
					}
				}
				else
				{
					os_log_error(kLogSQLite, "sqlite3: no variable for binding: ‘%{public}s’", sqlite3_bind_parameter_name(stmt, i+1));
				}
			}

			int status;
			while((status = sqlite3_step(stmt)) == SQLITE_ROW)
			{
				if(!rows)
					rows = [NSMutableArray array];
				[rows addObject:ColumnsAsDictionary(stmt)];
			}

			if(status != SQLITE_DONE)
			{
				os_log_error(kLogSQLite, "sqlite3_step: %{public}s executing %{public}s", sqlite3_errmsg(db), query);
				res = NO;
			}

			if(sqlite3_finalize(stmt) != SQLITE_OK)
			{
				os_log_error(kLogSQLite, "sqlite3_finalize: %{public}s", sqlite3_errmsg(db));
				res = NO;
			}

			if(res && rows)
				[resultSet addObject:rows];
		}
		else
		{
			os_log_error(kLogSQLite, "sqlite3_prepare_v2(%{public}s): %{public}s", query, sqlite3_errmsg(db));
			res = NO;
		}
		query = nextQuery;

		if(!res)
			resultSet = nil;
	}

	if(resultSet.count > 1)
			return resultSet;
	else	return resultSet.lastObject;
}

@implementation OakPasteboardDatabase
+ (instancetype)sharedInstance
{
	static OakPasteboardDatabase* instance = [self new];
	return instance;
}

- (NSURL*)databaseURL
{
	NSError* error;
	if(NSURL* appSupport = [[NSFileManager.defaultManager URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error] URLByAppendingPathComponent:@"TextMate"])
	{
		if([NSFileManager.defaultManager createDirectoryAtURL:appSupport withIntermediateDirectories:YES attributes:nil error:&error])
			return [appSupport URLByAppendingPathComponent:@"PasteboardHistory.db"];
	}
	[NSApp presentError:error];
	return nil;
}

- (sqlite3*)database
{
	// Process-wide, as +[OakPasteboard SQLDatabase]'s static was; there is one
	// shared instance, and the terminate block below captures this static directly.
	static sqlite3* db = nullptr;
	if(!db)
	{
		// =========================
		// = Delete CoreData files =
		// =========================

		for(NSURL* appSupport in [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask])
		{
			for(NSString* file in @[ @"ClipboardHistory.db", @"ClipboardHistory.db-shm", @"ClipboardHistory.db-wal" ])
			{
				NSURL* url = [[appSupport URLByAppendingPathComponent:@"TextMate"] URLByAppendingPathComponent:file];
				if([NSFileManager.defaultManager fileExistsAtPath:url.path])
				{
					NSURL* res;
					if([NSFileManager.defaultManager trashItemAtURL:url resultingItemURL:&res error:nil])
						os_log_info(kLogPasteboard, "Moved CoreData file to trash: %{public}@ → %{public}@", url.path.stringByAbbreviatingWithTildeInPath, res.path.stringByAbbreviatingWithTildeInPath);
				}
			}
		}

		// =========================

		BOOL memoryDatabase = [NSUserDefaults.standardUserDefaults boolForKey:kUserDefaultsDisablePersistentClipboardHistory];
		if(sqlite3_open(memoryDatabase ? ":memory:" : self.databaseURL.fileSystemRepresentation, &db) == SQLITE_OK)
		{
			if(os_log_info_enabled(kLogSQLite))
				os_log_info(kLogSQLite, "Opening sqlite3 database: %{public}@", memoryDatabase ? @":memory:" : self.databaseURL.path.stringByAbbreviatingWithTildeInPath);

			[NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillTerminateNotification object:NSApp queue:nil usingBlock:^(NSNotification*){
				if(!db)
					return;

				if(!memoryDatabase)
				{
					char const* query =
						"SELECT COUNT(*) AS count FROM strings LEFT JOIN groups ON string_id = strings.id WHERE string_id IS NULL;"
						"DELETE FROM strings WHERE id IN (SELECT strings.id FROM strings LEFT JOIN groups ON string_id = strings.id WHERE string_id IS NULL);";

					if(NSDictionary* row = RunSQLStatement(db, query).firstObject)
					{
						if(NSUInteger count = [row[@"count"] integerValue])
							os_log_info(kLogSQLite, "Garbage collected %lu string(s) from database", count);
					}
				}

				os_log_info(kLogSQLite, "Closing sqlite3 database");
				if(sqlite3_close(db) != SQLITE_OK)
					os_log_error(kLogSQLite, "sqlite3_close: %{public}s", sqlite3_errmsg(db));
				db = nullptr;
			}];

			char const* query =
				"PRAGMA foreign_keys = on;"
				"CREATE TABLE IF NOT EXISTS 'clipboards' ("
				"   'id'               INTEGER PRIMARY KEY,"
				"   'name'             TEXT NOT NULL,"
				"   UNIQUE (name) ON CONFLICT IGNORE"
				");"
				"CREATE TABLE IF NOT EXISTS 'strings' ("
				"   'id'               INTEGER PRIMARY KEY,"
				"   'string'           TEXT NOT NULL,"
				"   UNIQUE (string) ON CONFLICT IGNORE"
				");"
				"CREATE TABLE IF NOT EXISTS 'history' ("
				"   'id'               INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,"
				"   'clipboard_id'     INTEGER NOT NULL,"
				"   'options'          BLOB DEFAULT NULL,"
				"   'date'             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,"
				"   CONSTRAINT fk_clipboard FOREIGN KEY (clipboard_id) REFERENCES clipboards (id) ON DELETE CASCADE"
				");"
				"CREATE TABLE IF NOT EXISTS 'flags' ("
				"   'id'               INTEGER NOT NULL,"
				"   CONSTRAINT fk_id FOREIGN KEY (id) REFERENCES history (id) ON DELETE CASCADE"
				");"
				"CREATE TABLE IF NOT EXISTS 'groups' ("
				"   'id'               INTEGER NOT NULL PRIMARY KEY,"
				"   'history_id'       INTEGER NOT NULL,"
				"   'string_id'        INTEGER NOT NULL,"
				"   CONSTRAINT fk_history FOREIGN KEY (history_id) REFERENCES history (id) ON DELETE CASCADE,"
				"   CONSTRAINT fk_string  FOREIGN KEY (string_id)  REFERENCES strings (id) ON DELETE CASCADE"
				");"
				"CREATE TABLE IF NOT EXISTS 'meta' ("
				"   'key'              TEXT NOT NULL,"
				"   'value'            TEXT NOT NULL,"
				"   UNIQUE (key)"
				");"
				"INSERT OR IGNORE INTO meta ('key', 'value') VALUES ('version', '1'),('uuid', :uuid)";

			// Remove superfluous whitespace to improve output of sqlite3’s ‘.schema’ command
			NSMutableString* pretty = [NSMutableString stringWithUTF8String:query];
			NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:@"(\\(| ) +" options:0 error:nil];
			[regex replaceMatchesInString:pretty options:0 range:NSMakeRange(0, pretty.length) withTemplate:@"$1"];

			RunSQLStatement(db, pretty.UTF8String, @{ @":uuid": [NSUUID UUID].UUIDString });
		}
	}
	return db;
}

- (NSArray*)executeQuery:(NSString*)query
{
	return [self executeQuery:query variables:@{}];
}

- (NSArray*)executeQuery:(NSString*)query variables:(NSDictionary<NSString*, id>*)variables
{
	return RunSQLStatement(self.database, query.UTF8String, variables ?: @{});
}
@end
