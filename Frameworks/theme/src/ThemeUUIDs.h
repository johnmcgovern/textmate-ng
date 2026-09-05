// The three built-in theme UUIDs, split out of theme.h (rule 11).
//
// theme.h's first two lines are `#include <bundles/bundles.h>` and
// `#include <scope/scope.h>`, and it goes on to typedef std::shared_ptr over
// CTFontRef — so a consumer that wants nothing but a UUID string had to take all
// of it, and no Swift bridging header can.
//
// AppController registers two of these as user defaults and needs nothing else
// from theme.h. theme.h imports this, so no existing consumer changed.
//
// No includes, deliberately: theme.h is included from pure C++ translation units
// (theme.cc and friends), and pulling <Foundation/Foundation.h> in here broke
// every one of them. `char const*` needs nothing, and a bridging header parses
// this with Foundation already in scope.

extern char const* kMacClassicThemeUUID;
extern char const* kTwilightThemeUUID;
extern char const* kSystemUIThemeUUID;
