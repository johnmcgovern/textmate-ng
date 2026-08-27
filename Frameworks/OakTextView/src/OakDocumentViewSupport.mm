#import "OakDocumentViewSupport.h"
#import "OakTextView.h"
#import <document/OakDocument.h>
#import <text/format.h>
#import <text/types.h>
#import <OakFoundation/NSString Additions.h>
#import <bundles/bundles.h>
#import <settings/settings.h>
#import <text/ctype.h>
#import <theme/theme.h>
#import <ns/ns.h>

@implementation OakBundleMenuEntry
- (instancetype)initWithName:(NSString*)name uuidString:(NSString*)uuidString selectedGrammar:(BOOL)selectedGrammar hiddenFromUser:(BOOL)hiddenFromUser hasMenu:(BOOL)hasMenu
{
	if(self = [super init])
	{
		_name            = name;
		_uuidString      = uuidString;
		_selectedGrammar = selectedGrammar;
		_hiddenFromUser  = hiddenFromUser;
		_hasMenu         = hasMenu;
	}
	return self;
}
@end

@implementation OakGutterStyles
- (instancetype)initWithTheme:(theme_ptr const&)theme fileType:(std::string const&)fileType
{
	if(self = [super init])
	{
		_documentBackground = [NSColor colorWithCGColor:theme->background(fileType)];
		_isDark             = theme->is_dark();

		auto const& styles = theme->gutter_styles();

		_divider               = [NSColor colorWithCGColor:styles.divider];
		_foreground            = [NSColor colorWithCGColor:styles.foreground];
		_background            = [NSColor colorWithCGColor:styles.background];
		_icons                 = [NSColor colorWithCGColor:styles.icons];
		_iconsHover            = [NSColor colorWithCGColor:styles.iconsHover];
		_iconsPressed          = [NSColor colorWithCGColor:styles.iconsPressed];
		_selectionForeground   = [NSColor colorWithCGColor:styles.selectionForeground];
		_selectionBackground   = [NSColor colorWithCGColor:styles.selectionBackground];
		_selectionIcons        = [NSColor colorWithCGColor:styles.selectionIcons];
		_selectionIconsHover   = [NSColor colorWithCGColor:styles.selectionIconsHover];
		_selectionIconsPressed = [NSColor colorWithCGColor:styles.selectionIconsPressed];
		_selectionBorder       = [NSColor colorWithCGColor:styles.selectionBorder];
	}
	return self;
}
@end

@implementation OakDocumentSymbolEntry
- (instancetype)initWithSymbol:(NSString*)symbol positionString:(NSString*)positionString atOrBeforeCaret:(BOOL)atOrBeforeCaret
{
	if(self = [super init])
	{
		_symbol          = symbol;
		_positionString  = positionString;
		_atOrBeforeCaret = atOrBeforeCaret;
	}
	return self;
}
@end

@implementation OakDocumentMarkEntry
- (instancetype)initWithType:(NSString*)type payload:(NSString*)payload positionString:(NSString*)positionString
{
	if(self = [super init])
	{
		_type           = type;
		_payload        = payload;
		_positionString = positionString;
	}
	return self;
}
@end

@implementation OakDocumentBookmarkEntry
- (instancetype)initWithExcerpt:(NSString*)excerpt positionString:(NSString*)positionString paddedLinePrefix:(NSString*)paddedLinePrefix
{
	if(self = [super init])
	{
		_excerpt          = excerpt;
		_positionString   = positionString;
		_paddedLinePrefix = paddedLinePrefix;
	}
	return self;
}
@end

@implementation OakDocumentViewSupport

// ============
// = Settings =
// ============

+ (void)setFontName:(NSString*)fontName
{
	settings_t::set(kSettingsFontNameKey, to_s(fontName));
}

+ (void)setFontSize:(CGFloat)fontSize
{
	settings_t::set(kSettingsFontSizeKey, fontSize);
}

+ (void)setTabSize:(NSUInteger)tabSize forFileType:(NSString*)fileType
{
	settings_t::set(kSettingsTabSizeKey, (size_t)tabSize, to_s(fileType));
}

+ (void)setSoftTabs:(BOOL)softTabs forFileType:(NSString*)fileType
{
	settings_t::set(kSettingsSoftTabsKey, (bool)softTabs, to_s(fileType));
}

// ===========
// = Bundles =
// ===========

+ (NSString*)grammarScopeForBundleItemWithUUIDString:(NSString*)uuidString
{
	if(bundles::item_ptr item = bundles::lookup(to_s(uuidString)))
	{
		std::string const& scope = item->value_for_field(bundles::kFieldGrammarScope);
		if(scope != NULL_STR)
			return [NSString stringWithCxxString:scope];
	}
	return nil;
}

+ (void)performBundleItemWithUUIDString:(NSString*)uuidString inTextView:(OakTextView*)textView
{
	if(bundles::item_ptr item = bundles::lookup(to_s(uuidString)))
		[textView performBundleItem:item];
}

+ (NSArray<OakBundleMenuEntry*>*)bundlesForMenuWithFileType:(NSString*)fileType
{
	std::multimap<std::string, bundles::item_ptr, text::less_t> ordered;
	for(auto item : bundles::query(bundles::kFieldAny, NULL_STR, scope::wildcard, bundles::kItemTypeBundle))
		ordered.emplace(item->name(), item);

	NSMutableArray<OakBundleMenuEntry*>* res = [NSMutableArray array];
	for(auto pair : ordered)
	{
		bool selectedGrammar = false;
		for(auto item : bundles::query(bundles::kFieldGrammarScope, to_s(fileType), scope::wildcard, bundles::kItemTypeGrammar, pair.second->uuid(), true, true))
			selectedGrammar = true;

		[res addObject:[[OakBundleMenuEntry alloc] initWithName:[NSString stringWithCxxString:pair.first]
		                                            uuidString:[NSString stringWithCxxString:pair.second->uuid()]
		                                       selectedGrammar:selectedGrammar
		                                        hiddenFromUser:pair.second->hidden_from_user()
		                                               hasMenu:!pair.second->menu().empty()]];
	}
	return res;
}

// =========
// = Theme =
// =========

+ (OakGutterStyles*)gutterStylesForTextView:(OakTextView*)textView fileType:(NSString*)fileType
{
	if(theme_ptr theme = textView.theme)
		return [[OakGutterStyles alloc] initWithTheme:theme fileType:to_s(fileType)];
	return nil;
}

// =====================
// = Symbols and marks =
// =====================

+ (NSArray<OakDocumentSymbolEntry*>*)symbolsInDocument:(OakDocument*)document relativeToSelection:(NSString*)selectionString
{
	text::selection_t sel(to_s(selectionString));
	text::pos_t caret = sel.last().max();

	NSMutableArray<OakDocumentSymbolEntry*>* res = [NSMutableArray array];
	[document enumerateSymbolsUsingBlock:^(text::pos_t const& pos, NSString* symbol){
		[res addObject:[[OakDocumentSymbolEntry alloc] initWithSymbol:symbol positionString:to_ns(pos) atOrBeforeCaret:pos <= caret]];
	}];
	return res;
}

+ (NSArray<OakDocumentMarkEntry*>*)marksInDocument:(OakDocument*)document atLine:(NSUInteger)line
{
	NSMutableArray<OakDocumentMarkEntry*>* res = [NSMutableArray array];
	[document enumerateBookmarksAtLine:line block:^(text::pos_t const& pos, NSString* type, NSString* payload){
		[res addObject:[[OakDocumentMarkEntry alloc] initWithType:type payload:payload positionString:to_ns(pos)]];
	}];
	return res;
}

+ (NSArray<OakDocumentBookmarkEntry*>*)bookmarksInDocument:(OakDocument*)document
{
	NSMutableArray<OakDocumentBookmarkEntry*>* res = [NSMutableArray array];
	[document enumerateBookmarksUsingBlock:^(text::pos_t const& pos, NSString* excerpt){
		[res addObject:[[OakDocumentBookmarkEntry alloc] initWithExcerpt:excerpt positionString:to_ns(pos) paddedLinePrefix:to_ns(text::pad(pos.line+1, 4) + ": ")]];
	}];
	return res;
}

+ (void)setBookmarkOfType:(NSString*)type inDocument:(OakDocument*)document atLine:(NSUInteger)line
{
	[document setMarkOfType:type atPosition:text::pos_t(line, 0) content:nil];
}

+ (void)removeMarkOfType:(NSString*)type inDocument:(OakDocument*)document atPositionString:(NSString*)positionString
{
	[document removeMarkOfType:type atPosition:text::pos_t(to_s(positionString))];
}

@end
