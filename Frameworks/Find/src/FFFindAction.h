// Which of the eight things the Find window can do is being performed.
//
// Lifted out of Find.mm's file scope so the tests can name the constants: the
// option mask -performFindAction: builds depends on the action (backwards for
// FindPrevious, all_matches for the three counting ones), and that assembly is
// the most portable-looking, easiest-to-get-subtly-wrong logic in the file.
// Testing it means passing an action in, which means the tags need a home
// outside the .mm.
//
// Not in Find.h: no consumer outside the framework performs a find action —
// they set searchTarget and show the window, and the buttons do the rest.
//
// NS_ENUM(NSInteger) rather than the bare `enum` this replaced, so it has one
// declared width instead of whatever the compiler picked. Nothing persists these
// values — they are not menu-item tags, unlike the find::options_t values
// -takeFindOptionToToggleFrom: switches on — so the change is free. The numbering
// is preserved exactly anyway, because "free" has been wrong here before.
//
// Deliberately free of C++ so a Swift bridging header can import it.
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, FindActionTag) {
	FindActionFindNext = 1,
	FindActionFindPrevious,
	FindActionCountMatches,
	FindActionFindAll,
	FindActionReplaceAll,
	FindActionReplaceAndFind,
	FindActionReplaceSelected,
	FindActionReplace,
};
