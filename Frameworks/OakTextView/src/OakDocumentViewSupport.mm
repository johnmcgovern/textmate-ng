#import "OakDocumentViewSupport.h"
#import "OakTextView.h"
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

@end
