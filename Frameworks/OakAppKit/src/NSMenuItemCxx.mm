#import "NSMenuItemCxx.h"
#import "OakAppKit-Swift.h" // the ObjC-clean half of the category, defined in Swift
#import <OakFoundation/NSString Additions.h>
#import <ns/ns.h>

// All three of these are now pure conversions onto the Swift spellings. The
// modifier-prefix parser that used to live here moved into
// "NSMenuItem Additions.swift" as -setKeyEquivalentString:, because OTVStatusBar
// needs to reach it from Swift once ported.
//
// +stringWithCxxString: maps NULL_STR to nil, which is the same "no value" all
// three Swift spellings take as an Optional. It also returns nil for a string
// that is not valid UTF-8, where the old byte-at-a-time parser would have run
// anyway — unreachable for key equivalents, which come from bundle plists.

@implementation NSMenuItem (Cxx)
- (void)setKeyEquivalentCxxString:(std::string const&)aKeyEquivalent
{
	[self setKeyEquivalentString:[NSString stringWithCxxString:aKeyEquivalent]];
}

- (void)setInactiveKeyEquivalentCxxString:(std::string const&)aKeyEquivalent
{
	[self setInactiveKeyEquivalent:[NSString stringWithCxxString:aKeyEquivalent]];
}

- (void)setTabTriggerCxxString:(std::string const&)aTabTrigger
{
	[self setTabTrigger:[NSString stringWithCxxString:aTabTrigger]];
}
@end
