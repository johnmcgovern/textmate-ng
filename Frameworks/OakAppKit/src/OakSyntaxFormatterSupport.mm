#import "OakSyntaxFormatterSupport.h"
#import <bundles/query.h>
#import <theme/OakTheme.h>
#import <parse/parse.h>
#import <parse/grammar.h>
#import <text/utf16.h>
#import <ns/ns.h>

// Moved out of OakSyntaxFormatter.mm (rule 6): the grammar/theme load and the
// scope walk are unchanged, and the only edit is where the results go — into
// OakSyntaxStyleRun objects instead of straight onto an NSMutableAttributedString.
// The formatter's own reset pass stayed behind, because it is pure AppKit.

static size_t kParseSizeLimit = 1024;

@implementation OakSyntaxStyleRun
- (instancetype)initWithRange:(NSRange)range styles:(OakThemeStyles*)styles backgroundColor:(NSColor*)backgroundColor
{
	if(self = [super init])
	{
		_range           = range;
		_fontTraits      = styles.fontTraits;
		_foregroundColor = styles.foregroundColor;
		_backgroundColor = backgroundColor;
		_underlined      = styles.underlined;
		_strikethrough   = styles.strikethrough;
	}
	return self;
}
@end

@interface OakSyntaxStyler ()
{
	NSString* _grammarName;

	BOOL _didLoadGrammarAndTheme;
	parse::grammar_ptr _grammar;
	OakTheme* _theme;
}
@end

@implementation OakSyntaxStyler
- (instancetype)initWithGrammarName:(NSString*)grammarName
{
	if(self = [super init])
	{
		_grammarName = grammarName;
	}
	return self;
}

- (BOOL)tryLoadGrammarAndTheme
{
	if(_didLoadGrammarAndTheme == NO)
	{
		for(auto const& bundleItem : bundles::query(bundles::kFieldGrammarScope, to_s(_grammarName), scope::wildcard, bundles::kItemTypeGrammar))
		{
			if(_grammar = parse::parse_grammar(bundleItem))
				break;
		}

		_theme = [OakTheme theme];

		if(!_grammar)
			NSLog(@"Failed to load grammar: %@", _grammarName);

		_didLoadGrammarAndTheme = YES;
	}
	return _grammar && _theme;
}

- (NSArray<OakSyntaxStyleRun*>*)styleRunsForString:(NSString*)plain
{
	if(![self tryLoadGrammarAndTheme])
		return nil;

	std::string str = to_s(plain);
	std::map<size_t, scope::scope_t> scopes;
	parse::parse(str.data(), str.data() + std::min(str.size(), kParseSizeLimit), _grammar->seed(), scopes, true);

	NSMutableArray<OakSyntaxStyleRun*>* res = [NSMutableArray array];

	size_t from = 0, pos = 0;
	for(auto pair = scopes.begin(); pair != scopes.end(); )
	{
		OakThemeStyles* styles = [_theme stylesForScope:pair->second];

		// Note the ++ inside the condition: `to` is the *next* scope's offset, and
		// for the last scope it is the end of the whole string — not the parse
		// limit — so text past kParseSizeLimit takes the final scope's style.
		size_t to = ++pair != scopes.end() ? pair->first : str.size();
		size_t len = utf16::distance(str.data() + from, str.data() + to);

		NSColor* backgroundColor = [styles.backgroundColor isEqual:_theme.backgroundColor] ? nil : styles.backgroundColor;
		[res addObject:[[OakSyntaxStyleRun alloc] initWithRange:NSMakeRange(pos, len) styles:styles backgroundColor:backgroundColor]];

		pos += len;
		from = to;
	}

	return res;
}
@end
