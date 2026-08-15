#import "FileBrowserOutlineViewKeyBindings.h"
#import <text/utf8.h>
#import <ns/ns.h>

// The key-equivalent table and match, moved verbatim from
// FileBrowserOutlineView.mm's -performKeyEquivalent:. The only change is the
// hit branch: it returns the action selector instead of sending it, so the
// Swift override keeps the send / fall-through-to-super control flow.
SEL FileBrowserOutlineViewActionForEvent (NSEvent* anEvent)
{
	static struct key_action_t { std::string key; SEL action; } const KeyActions[] =
	{
		{ "@" + utf8::to_s(NSLeftArrowFunctionKey),  @selector(goBack:)                   },
		{ "@" + utf8::to_s(NSRightArrowFunctionKey), @selector(goForward:)                },
		{ "@" + utf8::to_s(NSDownArrowFunctionKey),  @selector(performDoubleClick:)       },
		{ "~" + utf8::to_s(NSF2FunctionKey),         @selector(showContextMenu:)          },
		{ "@o",                                      @selector(performDoubleClick:)       },
		{ "~@c",                                     @selector(copyAsPathname:)           },
		{ "@d",                                      @selector(duplicateSelectedEntries:) },
		{ "@G",                                      @selector(orderFrontGoToFolder:)     },
		{ " ",                                       @selector(toggleQuickLookPreview:)   },
	};

	std::string const key = to_s(anEvent);
	for(auto const& keyAction : KeyActions)
	{
		if(key == keyAction.key)
			return keyAction.action;
	}
	return nullptr;
}
