// What the user answered to "would you like to install this bundle?".
//
// Split out of SelectGrammarViewController.h for the reason Find.h was split
// into FindTypes.h: the controller is now Swift, so a bridging header cannot
// import the header that declares it — but the Swift needs this enum, since it
// is the first parameter of the completion handler. Anything else living beside
// a ported class declaration has to move the same way.
//
// The values are ordinals with no persistence behind them: they are menu-item
// tags on three buttons built in code, read back in the same process. Nothing
// stores them, so renumbering would be safe — which is worth saying because the
// two enums Find split *were* persisted, and the difference is why this one
// needs no static_assert and no runtime table.
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SelectGrammarResponse) {
	SelectGrammarResponseInstall = 0,
	SelectGrammarResponseNotNow,
	SelectGrammarResponseNever,
	SelectGrammarResponseCount
};
