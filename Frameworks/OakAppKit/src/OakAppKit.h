#include "IOAlertPanel.h"
extern NSNotificationName const OakCursorDidHideNotification;

// **No default arguments, and specifically not `anEvent = [NSApp currentEvent]`,
// which is what this used to have.** A C++ default argument whose expression is an
// ObjC message send gets the wrong ownership when Swift supplies it: it
// over-releases the returned object. For this function that meant over-releasing
// NSApp's current event, and since -[SoftwareUpdate checkForUpdate:] called it
// twice in a row, the second call retained a corpse — a crash in the shipped
// alpha.22 on Settings ▸ Software Update ▸ Check Now. See rule 65.
//
// The defaults went rather than just the one bad call site, because nothing was
// using them: every caller is Swift now and all eight already passed both
// arguments. Removing them makes the hazard a compile error instead of a memory
// bug that reproduces two runs in three. C++ needs defaults to be trailing, so
// `flags` lost its default too.
BOOL OakIsAlternateKeyOrMouseEvent (NSUInteger flags, NSEvent* anEvent);

typedef NS_ENUM(NSUInteger, OakPerformTableViewActionResult) {
	OakMoveMoveReturn,
	OakMoveAcceptReturn,
	OakMoveCancelReturn,
	OakMoveNoActionReturn,
};

NSUInteger OakPerformTableViewActionFromKeyEvent (NSTableView* tableView, NSEvent* event);
NSUInteger OakPerformTableViewActionFromSelector (NSTableView* tableView, SEL selector);
