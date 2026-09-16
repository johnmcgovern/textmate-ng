#import <OakAppKit/OakPasteboard.h>
#import <OakAppKit/OakPasteboardDatabase.h>
#import <OakAppKit/OakPasteboardSelector.h>
#import <OakAppKit/OakPasteboardChooser.h>

// Written against the ObjC++ OakPasteboard, before the Swift port, so it judges the
// original and not the translation (the DocumentWindowController lesson, rule 18).
//
// OakPasteboard is the SQLite-backed clipboard/find history; its whole public
// contract is selectors, consumed from DocumentWindowController, Find, the two
// pasteboard chooser/selector panels and the app, none through a protocol — so a
// rename or a mis-imported Swift spelling in the port would be invisible to the
// compiler and to a green build. These assertions are pure -respondsToSelector:
// checks: they trigger +initialize (which only registers defaults and notification
// observers) but never open the database or touch the system pasteboard, so they are
// safe to run in a bare test process.
//
// Two selectors here are the ones the port has to get exactly right:
//   - `isFlagged` / `setFlagged:` — the property has getter=isFlagged (rule 4), so a
//     Swift `@objc var flagged` would export as -flagged and break every caller
//     unless it carries the accessor annotations.
//   - `findOptions` — returns a C++ `find::options_t` (rule 17), so it cannot be a
//     plain Swift method; whatever boundary the port gives it, the selector must
//     survive for the ObjC++ consumers that read it.

void setup ()
{
	NSApplicationLoad();
	// Open the store in memory, before it is first touched, so these tests neither
	// read nor write the real PasteboardHistory.db.
	[NSUserDefaults.standardUserDefaults setBool:YES forKey:@"disablePersistentClipboardHistory"];
}

// These judge OakPasteboardDatabase — the SQLite store the port extracted out of
// OakPasteboard.mm — directly, so the extraction is covered before OakPasteboard.mm
// becomes Swift. There was no pasteboard test at all before; the store is the
// riskiest piece to move, and the whole point of extracting it while OakPasteboard
// is still ObjC++ is that a test can judge the shim (the two-commit shape).

void test_pasteboard_database_round_trips_a_text_row ()
{
	// prepare → bind_text(:name) → step → ColumnsAsDictionary(SQLITE_TEXT), the core
	// path the extraction moved. Schema is created on first access.
	OakPasteboardDatabase* db = OakPasteboardDatabase.sharedInstance;
	[db executeQuery:@"INSERT INTO clipboards ('name') VALUES (:name);" variables:@{ @":name": @"t_pasteboard_TestBoard" }];

	NSArray* rows = [db executeQuery:@"SELECT name FROM clipboards WHERE name = :name;" variables:@{ @":name": @"t_pasteboard_TestBoard" }];
	OAK_ASSERT_EQ(rows.count, 1);
	OAK_ASSERT([rows.firstObject[@"name"] isEqualToString:@"t_pasteboard_TestBoard"]);
}

void test_pasteboard_database_binds_and_reads_a_number ()
{
	// Exercises the @encode → sqlite3_bind_int64 dispatch table (an NSNumber :n) and
	// SQLITE_INTEGER read-back, without needing a table.
	OakPasteboardDatabase* db = OakPasteboardDatabase.sharedInstance;
	NSArray* rows = [db executeQuery:@"SELECT :n + 1 AS result;" variables:@{ @":n": @(41) }];
	OAK_ASSERT_EQ(rows.count, 1);
	OAK_ASSERT_EQ([rows.firstObject[@"result"] integerValue], 42);
}

void test_pasteboard_database_absent_binding_is_not_a_crash ()
{
	// A query naming a variable the dictionary does not supply logs "no variable" and
	// binds nothing — it must not crash (the std::map find/end path the port replaced
	// with an NSDictionary lookup, rule 33).
	OakPasteboardDatabase* db = OakPasteboardDatabase.sharedInstance;
	NSArray* rows = [db executeQuery:@"SELECT :missing AS result;" variables:@{}];
	OAK_ASSERT_EQ(rows.count, 1);
}

// Added 2026-09-15 ahead of porting the store itself to Swift: the bind dispatch
// and the column read-back are the two places a translation can quietly change a
// value's type or lose NULL, and the three tests above only reach text and one
// integer. Each of these names one branch.

void test_pasteboard_database_null_binds_null_and_reads_back_absent ()
{
	// NSNull in the variables binds NULL (the std::map used to carry a nil id for
	// this); a NULL column is *absent* from the row dictionary, not NSNull.
	OakPasteboardDatabase* db = OakPasteboardDatabase.sharedInstance;
	NSArray* rows = [db executeQuery:@"SELECT :v AS result, 1 AS one;" variables:@{ @":v": NSNull.null }];
	OAK_ASSERT_EQ(rows.count, 1);
	OAK_ASSERT((bool)(rows.firstObject[@"result"] == nil));
	OAK_ASSERT_EQ([rows.firstObject[@"one"] integerValue], 1);
}

void test_pasteboard_database_round_trips_a_blob ()
{
	// NSData binds as a BLOB and comes back as NSData, bytes intact — the `options`
	// column is a binary plist stored this way.
	OakPasteboardDatabase* db = OakPasteboardDatabase.sharedInstance;
	char const bytes[] = { 0, 1, 2, (char)0xFF, 'x' };
	NSData* data = [NSData dataWithBytes:bytes length:sizeof(bytes)];
	NSArray* rows = [db executeQuery:@"SELECT :d AS result, length(:d) AS len;" variables:@{ @":d": data }];
	OAK_ASSERT_EQ(rows.count, 1);
	OAK_ASSERT([rows.firstObject[@"result"] isKindOfClass:[NSData class]]);
	OAK_ASSERT([rows.firstObject[@"result"] isEqualToData:data]);
	OAK_ASSERT_EQ([rows.firstObject[@"len"] integerValue], 5);
}

void test_pasteboard_database_binds_a_boxed_bool_as_text_and_double_as_real ()
{
	// Measured against the ObjC++, and not what it meant to do. The dispatch table
	// is keyed by @encode, and the frameworks compile with GCC_CHAR_IS_UNSIGNED_CHAR
	// (ide/seed_xcodeproj.rb), so @encode(char) is "C" — the same as unsigned
	// char — and no entry for "c" ever exists. Foundation boxes @YES with objCType "c" (it is built with a signed
	// char), so a boxed BOOL misses the table and takes the fallback: bound as the
	// text "1". SQLite's arithmetic coerces it, which is why nothing noticed; no
	// caller binds a boolean. The port keys its table by the letters themselves and
	// binds "c" as an integer; that assertion changes with it.
	OakPasteboardDatabase* db = OakPasteboardDatabase.sharedInstance;
	NSArray* rows = [db executeQuery:@"SELECT :b AS flag, typeof(:b) AS flagType, :r * 2 AS twice, typeof(:r) AS realType;" variables:@{ @":b": @YES, @":r": @(2.5) }];
	OAK_ASSERT_EQ(rows.count, 1);
	OAK_ASSERT_EQ([rows.firstObject[@"flag"] integerValue], 1);
	OAK_ASSERT_EQ(std::string([[rows.firstObject[@"flagType"] description] UTF8String]), std::string("text"));
	OAK_ASSERT_EQ([rows.firstObject[@"twice"] doubleValue], 5.0);
	OAK_ASSERT_EQ(std::string([[rows.firstObject[@"realType"] description] UTF8String]), std::string("real"));
}

void test_pasteboard_database_binds_an_int_as_integer ()
{
	// The existing arithmetic pin above cannot tell an integer binding from the
	// text "41", because SQLite adds either. typeof() can.
	OakPasteboardDatabase* db = OakPasteboardDatabase.sharedInstance;
	NSArray* rows = [db executeQuery:@"SELECT typeof(:n) AS t, typeof(:big) AS bigType, :big AS big;" variables:@{ @":n": @(41), @":big": @(1234567890123LL) }];
	OAK_ASSERT_EQ(std::string([[rows.firstObject[@"t"] description] UTF8String]), std::string("integer"));
	OAK_ASSERT_EQ(std::string([[rows.firstObject[@"bigType"] description] UTF8String]), std::string("integer"));
	// Read back through sqlite3_column_int, which is 32-bit: the value truncates.
	// Nothing stored is that large; the pin records the read-back path, not a wish.
	OAK_ASSERT_EQ([rows.firstObject[@"big"] longLongValue], (long long)(int)1234567890123LL);
}

void test_pasteboard_database_text_binding_survives_the_step ()
{
	// The text is bound with a pointer into the NSString's UTF-8 buffer; it must
	// still be intact when the statement runs — and non-ASCII must round-trip.
	OakPasteboardDatabase* db = OakPasteboardDatabase.sharedInstance;
	NSString* text = @"héllo — wörld ✓";
	NSArray* rows = [db executeQuery:@"SELECT :t AS result, length(:t) AS len;" variables:@{ @":t": text }];
	OAK_ASSERT_EQ(rows.count, 1);
	OAK_ASSERT([rows.firstObject[@"result"] isEqualToString:text]);
	OAK_ASSERT_EQ([rows.firstObject[@"len"] integerValue], (NSInteger)text.length);
}

void test_pasteboard_database_several_statements_return_one_array_per_row_set ()
{
	// The rule-6 shape: two row-returning statements give an array of two row
	// arrays; statements that return no rows contribute nothing.
	OakPasteboardDatabase* db = OakPasteboardDatabase.sharedInstance;
	NSArray* sets = [db executeQuery:@"SELECT 1 AS a; CREATE TABLE IF NOT EXISTS t_pasteboard_scratch (x INTEGER); SELECT 2 AS b, 3 AS c;"];
	OAK_ASSERT_EQ(sets.count, 2);
	OAK_ASSERT_EQ([[sets[0] firstObject][@"a"] integerValue], 1);
	OAK_ASSERT_EQ([[sets[1] firstObject][@"c"] integerValue], 3);

	// One row-returning statement: its rows, not an array of one row array.
	NSArray* rows = [db executeQuery:@"SELECT 4 AS d;"];
	OAK_ASSERT_EQ(rows.count, 1);
	OAK_ASSERT([rows.firstObject isKindOfClass:[NSDictionary class]]);
}

void test_pasteboard_database_a_bad_statement_yields_nil_not_a_partial_result ()
{
	// The first statement succeeds, the second cannot be prepared: the whole
	// result is nil (rule 6), not the first statement's rows.
	OakPasteboardDatabase* db = OakPasteboardDatabase.sharedInstance;
	NSArray* res = [db executeQuery:@"SELECT 1 AS a; SELECT * FROM t_pasteboard_no_such_table;"];
	OAK_ASSERT((bool)(res == nil));

	// And a bare no-row statement is nil as well: nothing to return.
	NSArray* none = [db executeQuery:@"CREATE TABLE IF NOT EXISTS t_pasteboard_scratch2 (x INTEGER);"];
	OAK_ASSERT((bool)(none == nil));
}

void test_pasteboard_database_integer_columns_read_back_as_int ()
{
	// SQLITE_INTEGER is read with sqlite3_column_int — 32-bit — and wrapped as an
	// int NSNumber. The history ids are far below that, but a port reading int64
	// would change objCType, which a dictionary comparison could notice.
	OakPasteboardDatabase* db = OakPasteboardDatabase.sharedInstance;
	NSArray* rows = [db executeQuery:@"SELECT 7 AS n;"];
	OAK_ASSERT_EQ(std::string([rows.firstObject[@"n"] objCType]), std::string(@encode(int)));
}

void test_oak_pasteboard_keeps_its_class_surface ()
{
	SEL const classSelectors[] = {
		@selector(generalPasteboard),
		@selector(findPasteboard),
		@selector(replacePasteboard),
	};
	for(SEL selector : classSelectors)
		OAK_ASSERT([OakPasteboard respondsToSelector:selector]);
}

void test_oak_pasteboard_keeps_its_instance_surface ()
{
	SEL const selectors[] = {
		@selector(addEntryWithString:),
		@selector(addEntryWithString:options:),
		@selector(addEntryWithStrings:options:),
		@selector(removeEntries:),
		@selector(removeAllEntries),
		@selector(entries),
		@selector(updatePasteboardWithEntry:),
		@selector(updatePasteboardWithEntries:),
		@selector(previous),
		@selector(current),
		@selector(next),
		@selector(name),
		@selector(currentEntry),
		@selector(selectItemForControl:),
	};
	for(SEL selector : selectors)
		OAK_ASSERT([OakPasteboard instancesRespondToSelector:selector]);
}

void test_oak_pasteboard_selector_keeps_its_surface ()
{
	// The panel OakPasteboard.selectItemForControl: drives; FFTextFieldViewController
	// also reaches +sharedInstance. Pure -respondsToSelector: (no XIB load). Rule 18.
	OAK_ASSERT([OakPasteboardSelector respondsToSelector:@selector(sharedInstance)]);
	SEL const selectors[] = {
		@selector(setIndex:),
		@selector(setEntries:),
		@selector(showAtLocation:),
		@selector(setWidth:),
		@selector(setPerformsActionOnSingleClick),
		@selector(entries),
	};
	for(SEL selector : selectors)
		OAK_ASSERT([OakPasteboardSelector instancesRespondToSelector:selector]);
}

void test_oak_pasteboard_chooser_keeps_its_surface ()
{
	// The clipboard-history chooser, opened from OakDocumentView. Rule 18.
	OAK_ASSERT([OakPasteboardChooser instancesRespondToSelector:@selector(showWindowRelativeToFrame:)]);
	OAK_ASSERT([OakPasteboardChooser respondsToSelector:@selector(sharedChooserForPasteboard:)]);
	SEL const selectors[] = {
		@selector(filterString),  @selector(setFilterString:),
		@selector(action),        @selector(setAction:),
		@selector(alternateAction), @selector(setAlternateAction:),
		@selector(target),        @selector(setTarget:),
	};
	for(SEL selector : selectors)
		OAK_ASSERT([OakPasteboardChooser instancesRespondToSelector:selector]);
}

void test_oak_pasteboard_entry_keeps_its_surface ()
{
	SEL const selectors[] = {
		@selector(string),
		@selector(strings),
		@selector(options),
		@selector(isFlagged),      // getter=isFlagged, not -flagged (rule 4)
		@selector(setFlagged:),
		@selector(historyId),
		@selector(fullWordMatch),
		@selector(ignoreWhitespace),
		@selector(regularExpression),
		@selector(findOptions),    // returns find::options_t (rule 17)
	};
	for(SEL selector : selectors)
		OAK_ASSERT([OakPasteboardEntry instancesRespondToSelector:selector]);
}
