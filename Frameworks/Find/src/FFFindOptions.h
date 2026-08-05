// The find layer's option bits, in a form that crosses the ObjC boundary.
//
// This exists to close an ABI trap rather than for tidiness — the same one
// TMSCMStatus.h closed for scm::status::type. FFDocumentSearch's public
// property used to be typed `find::options_t`, a C++ unscoped enum whose
// underlying type the compiler picks: its largest value is 1<<10, so it is
// **4 bytes**, while any ObjC or Swift declaration of that property uses
// NSUInteger, which is 8. The mismatch is neither an error nor a warning.
//
// Declaring it NS_OPTIONS(NSUInteger, …) removes the trap at its root: both
// sides read the same ObjC declaration. Conversion to the C++ enum happens
// explicitly in FFDocumentSearchSupport.mm, which pins the two together with
// static_assert — a divergence is then a compile error rather than a silently
// wrong search. t_find_options.mm checks the same pairs at runtime, so the
// guarantee survives even if the support file is ever rewritten in a language
// without static_assert.
//
// NS_OPTIONS and not NS_ENUM because it is genuinely a bitmask: callers build it
// with `|` and test it with `&` (Find.mm:881, :1030).
//
// Deliberately free of C++ so a Swift bridging header can import it.
#import <Foundation/Foundation.h>

typedef NS_OPTIONS(NSUInteger, FFFindOptions) {
	FFFindOptionsNone              = 0,
	FFFindOptionsFullWords         = 1 << 0,
	FFFindOptionsIgnoreCase        = 1 << 1,
	FFFindOptionsIgnoreWhitespace  = 1 << 2,
	FFFindOptionsRegularExpression = 1 << 3,
	FFFindOptionsBackwards         = 1 << 4,
	FFFindOptionsNotBOL            = 1 << 5,
	FFFindOptionsNotEOL            = 1 << 6,
	FFFindOptionsWrapAround        = 1 << 7,
	FFFindOptionsAllMatches        = 1 << 8,
	FFFindOptionsExtendSelection   = 1 << 9,
	FFFindOptionsFileSizeLimit     = 1 << 10,
};
