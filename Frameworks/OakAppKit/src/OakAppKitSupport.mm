#import "OakAppKitSupport.h"
#import <ns/ns.h>
#import <io/path.h>
#import <ns/event.h>
#import <OakFoundation/NSString Additions.h>
#import <Carbon/Carbon.h>

NSString* OakGlyphsForEventString (NSString* eventString)
{
	return [NSString stringWithCxxString:ns::glyphs_for_event_string(to_s(eventString))];
}

NSString* OakGlyphsForModifierFlags (NSUInteger flags)
{
	return [NSString stringWithCxxString:ns::glyphs_for_flags(flags)];
}

NSString* OakEventString (NSEvent* anEvent)
{
	return [NSString stringWithCxxString:to_s(anEvent)];
}

void* OakPushSymbolicHotKeyModeAllDisabled (void)
{
	return PushSymbolicHotKeyMode(kHIHotKeyModeAllDisabled);
}

void OakPopSymbolicHotKeyMode (void* token)
{
	PopSymbolicHotKeyMode(token);
}

NSData* OakUserTagsAttributeForURL (NSURL* url)
{
	if(!url.filePathURL)
		return nil;

	std::string const bplist = path::get_attr(url.fileSystemRepresentation, "com.apple.metadata:_kMDItemUserTags");
	if(bplist == NULL_STR)
		return nil;

	return [NSData dataWithBytes:(void*)bplist.data() length:bplist.size()];
}
