#import "OakSavePanelCxx.h"
#import <OakFoundation/NSString Additions.h>
#import <OakFoundation/OakStringListTransformer.h>
#import <settings/settings.h>
#import <ns/ns.h>

// Moved out of OakSavePanel.mm (rule 6). -encodingForURL:'s body is unchanged
// apart from where its input and output come from, and +initialize's body is
// unchanged apart from being callable.

@implementation OakEncodingOptions
- (instancetype)initWithNewlines:(NSString*)newlines charset:(NSString*)charset
{
	if(self = [super init])
	{
		_newlines = newlines;
		_charset  = charset;
	}
	return self;
}

+ (instancetype)optionsWithNewlines:(NSString*)newlines charset:(NSString*)charset
{
	return [[self alloc] initWithNewlines:newlines charset:charset];
}
@end

@implementation OakEncodingOptions (Cxx)
+ (instancetype)optionsWithCxxEncoding:(encoding::type const&)encoding
{
	// +stringWithCxxString: maps NULL_STR to nil, and kCharsetNoEncoding is
	// NULL_STR, so "no encoding" and "no value" arrive as the same nil.
	return [self optionsWithNewlines:[NSString stringWithCxxString:encoding.newlines()] charset:[NSString stringWithCxxString:encoding.charset()]];
}

- (encoding::type)cxxEncoding
{
	// The *constructor*, deliberately, not set_charset: it stores the charset
	// verbatim, and anything that needed uppercasing was uppercased on the way in.
	return encoding::type(to_s(self.newlines), to_s(self.charset));
}
@end

@implementation OakSavePanelSupport
+ (OakEncodingOptions*)resolveOptions:(OakEncodingOptions*)options forURL:(NSURL*)url fileType:(NSString*)fileType
{
	encoding::type res = [options cxxEncoding];

	settings_t const& settings = settings_for_path(to_s([[url filePathURL] path]), to_s(fileType));
	if(res.charset() == kCharsetNoEncoding)
		res.set_charset(settings.get(kSettingsEncodingKey, kCharsetUTF8));

	if(res.newlines() == NULL_STR)
		res.set_newlines(settings.get(kSettingsLineEndingsKey, "\n"));

	return [OakEncodingOptions optionsWithCxxEncoding:res];
}

+ (void)registerValueTransformers
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		[OakStringListTransformer createTransformerWithName:@"OakLineEndingsTransformer" andObjectsArray:@[ @"\n", @"\r", @"\r\n" ]];
	});
}
@end
