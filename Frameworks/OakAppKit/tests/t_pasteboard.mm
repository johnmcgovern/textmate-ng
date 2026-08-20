#import <OakAppKit/OakPasteboard.h>

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
