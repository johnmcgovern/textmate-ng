#import "BESupport.h"
#import <OakFoundation/NSString Additions.h>
#import <text/decode.h>

NSString* BERot13 (NSString* string)
{
	return [NSString stringWithCxxString:decode::rot13(string.UTF8String ?: "")];
}
