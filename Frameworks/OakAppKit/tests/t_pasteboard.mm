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
