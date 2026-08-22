// The C++ half of OakSyntaxFormatter, so the formatter itself can be Swift.
//
// Three things kept the formatter unportable and all three are here: a
// `parse::grammar_ptr` ivar (rule 20), `parse::parse` over a std::string, and
// -[OakTheme stylesForScope:], whose parameter is a `scope::scope_t const&`
// (rule 17). None of them can cross into Swift, and none of them needs to — what
// the formatter actually wants is a list of ranges and the attributes to put on
// them.
//
// The UTF-8/UTF-16 conversion lives on this side too, deliberately. The parser
// counts bytes and NSAttributedString counts UTF-16 units, so every range that
// leaves this header is already in the units its caller uses; see
// t_syntax_formatter.mm's test_syntax_formatter_ranges_are_utf16_not_bytes for
// why that boundary is drawn here and not one layer up.
#import <Cocoa/Cocoa.h>

// One run of styled text, in UTF-16 units, with the attributes the theme
// resolved for the scope covering it.
@interface OakSyntaxStyleRun : NSObject
@property (nonatomic, readonly) NSRange range;
@property (nonatomic, readonly) NSFontTraitMask fontTraits;
@property (nonatomic, readonly) NSColor* foregroundColor;
// nil when the theme's colour for this scope is the theme's own background — the
// formatter leaves the attribute off entirely in that case rather than painting
// the background onto itself.
@property (nonatomic, readonly) NSColor* backgroundColor;
@property (nonatomic, readonly) BOOL underlined;
@property (nonatomic, readonly) BOOL strikethrough;
@end

@interface OakSyntaxStyler : NSObject
- (instancetype)initWithGrammarName:(NSString*)grammarName;
// nil when the grammar could not be loaded, which is not the same as an empty
// array: the caller skips styling entirely rather than clearing what is there.
// The grammar and theme are loaded once, on the first call, and the failure is
// logged once.
- (NSArray<OakSyntaxStyleRun*>*)styleRunsForString:(NSString*)plain;
@end
