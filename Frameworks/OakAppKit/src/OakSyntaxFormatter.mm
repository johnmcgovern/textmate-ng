#import "OakSyntaxFormatter.h"
#import "OakSyntaxFormatterSupport.h"
#import <OakFoundation/OakFoundation.h>

// What is left after the C++ moved to OakSyntaxFormatterSupport: an NSFormatter
// and one AppKit pass over an attributed string. No std::, no parse::, no
// scope::, and OakTheme is reached only through the styler — which is the whole
// point, because this file is the next one to become Swift.

@interface OakSyntaxFormatter ()
{
	NSString* _grammarName;
	OakSyntaxStyler* _styler;
}
@end

@implementation OakSyntaxFormatter
- (instancetype)initWithGrammarName:(NSString*)grammarName
{
	if(self = [self init])
	{
		_grammarName = grammarName;
	}
	return self;
}

- (NSString*)stringForObjectValue:(id)value
{
	return value;
}

- (BOOL)getObjectValue:(id*)valueRef forString:(NSString*)aString errorDescription:(NSString**)errorRef
{
	// We break NSContinuouslyUpdatesValueBindingOption unless a new instance is returned
	*valueRef = [aString copy];
	return YES;
}

- (NSAttributedString*)attributedStringForObjectValue:(id)value withDefaultAttributes:(NSDictionary*)attributes
{
	NSMutableAttributedString* styled = [[NSMutableAttributedString alloc] initWithString:value attributes:attributes];
	[self addStylesToString:styled];
	return styled;
}

- (void)addStylesToString:(NSMutableAttributedString*)styled
{
	NSString* plain = styled.string;
	if(OakIsEmptyString(plain) || !_grammarName)
		return;

	for(NSString* attr in @[ NSBackgroundColorAttributeName, NSUnderlineStyleAttributeName, NSStrikethroughStyleAttributeName ])
		[styled removeAttribute:attr range:NSMakeRange(0, plain.length)];
	[styled addAttributes:@{ NSForegroundColorAttributeName: NSColor.controlTextColor } range:NSMakeRange(0, plain.length)];
	[styled applyFontTraits:NSUnboldFontMask|NSUnitalicFontMask range:NSMakeRange(0, plain.length)];

	if(_enabled)
	{
		// Built on first use, not in the initializer: loading a grammar is the
		// expensive part and a formatter that is never enabled must never pay it.
		if(!_styler)
			_styler = [[OakSyntaxStyler alloc] initWithGrammarName:_grammarName];

		// nil when the grammar failed to load, and iterating nil is the same
		// nothing the old `_enabled && [self tryLoadGrammarAndTheme]` guard did.
		for(OakSyntaxStyleRun* run in [_styler styleRunsForString:plain])
		{
			if(run.fontTraits)
				[styled applyFontTraits:run.fontTraits range:run.range];

			NSMutableDictionary* attributes = [NSMutableDictionary dictionaryWithObject:run.foregroundColor forKey:NSForegroundColorAttributeName];
			if(run.backgroundColor)
				attributes[NSBackgroundColorAttributeName] = run.backgroundColor;
			if(run.underlined)
				attributes[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
			if(run.strikethrough)
				attributes[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
			[styled addAttributes:attributes range:run.range];
		}
	}

	[styled fixFontAttributeInRange:NSMakeRange(0, plain.length)];
}
@end
