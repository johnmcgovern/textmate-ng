#import "NSMenuItemCxx.h"
#import "OakAppKit-Swift.h" // the ObjC-clean half of the category, defined in Swift
#import <OakFoundation/NSString Additions.h>
#import <ns/ns.h>

// Two of these three are pure conversions onto the Swift spellings. The third,
// -setKeyEquivalentCxxString:, keeps its parser here: it works one byte at a time
// over a std::string and has no ObjC-clean caller to justify a second spelling.

@implementation NSMenuItem (Cxx)
- (void)setKeyEquivalentCxxString:(std::string const&)aKeyEquivalent
{
	if(aKeyEquivalent == NULL_STR || aKeyEquivalent.empty())
	{
		[self setKeyEquivalent:@""];
		[self setKeyEquivalentModifierMask:0];
		return;
	}

	NSUInteger modifiers = 0;

	size_t i = 0;
	while(true)
	{
		// `i+1 >= size` and not `i >= size`: the final character is never a
		// modifier, which is what makes "⌘@" expressible as "@@" and "@" on its
		// own the unmodified character.
		if(i+1 >= aKeyEquivalent.size() || !strchr("$^~@#", aKeyEquivalent[i]))
			break;

		switch(aKeyEquivalent[i++])
		{
			case '$': modifiers |= NSEventModifierFlagShift;      break;
			case '^': modifiers |= NSEventModifierFlagControl;    break;
			case '~': modifiers |= NSEventModifierFlagOption;     break;
			case '@': modifiers |= NSEventModifierFlagCommand;    break;
			case '#': modifiers |= NSEventModifierFlagNumericPad; break;
		}
	}

	[self setKeyEquivalent:[NSString stringWithCxxString:aKeyEquivalent.substr(i)]];
	[self setKeyEquivalentModifierMask:modifiers];
}

- (void)setInactiveKeyEquivalentCxxString:(std::string const&)aKeyEquivalent
{
	// NULL_STR becomes nil, which is the same "record it, draw nothing" the
	// Swift side spells with an Optional.
	[self setInactiveKeyEquivalent:[NSString stringWithCxxString:aKeyEquivalent]];
}

- (void)setTabTriggerCxxString:(std::string const&)aTabTrigger
{
	[self setTabTrigger:[NSString stringWithCxxString:aTabTrigger]];
}
@end
