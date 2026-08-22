#import "AppController.h"
#import <oak/oak.h>
#import <text/ctype.h>
#import <text/parse.h>
#import <bundles/bundles.h>
#import <command/parser.h>
#import <cf/cf.h>
#import <ns/ns.h>
#import <OakAppKit/NSMenuItem Additions.h>
#import <OakAppKit/NSMenuItemCxx.h> // -setKeyEquivalentCxxString:
#import <OakAppKit/OakToolTip.h>
#import <MenuBuilder/MenuBuilder.h>
#import <OakFoundation/NSString Additions.h>
#import <OakTextView/OakTextView.h>
#import <oak/debug.h>
#import <BundleMenu/BundleMenu.h>
#import <theme/theme.h>
#import <settings/settings.h>

static NSString* NameForLocaleIdentifier (NSString* languageCode)
{
	NSString* localLanguage = nil;
	if(CFLocaleRef locale = CFLocaleCreate(kCFAllocatorDefault, (__bridge CFStringRef)languageCode))
	{
		localLanguage = [(NSString*)CFBridgingRelease(CFLocaleCopyDisplayNameForPropertyValue(locale, kCFLocaleIdentifier, (__bridge CFStringRef)languageCode)) capitalizedString];
		CFRelease(locale);
	}

	NSString* systemLangauge = [(NSString*)CFBridgingRelease(CFLocaleCopyDisplayNameForPropertyValue(CFLocaleGetSystem(), kCFLocaleIdentifier, (__bridge CFStringRef)languageCode)) capitalizedString];
	return localLanguage ?: systemLangauge ?: languageCode;
}

@implementation AppController (BundlesMenu)
- (BOOL)menuHasKeyEquivalent:(NSMenu*)aMenu forEvent:(NSEvent*)theEvent target:(id*)aTarget action:(SEL*)anAction
{
	return NO;
}

- (void)bundlesMenuNeedsUpdate:(NSMenu*)aMenu
{
	for(NSInteger i = aMenu.numberOfItems; i--; )
	{
		if([[aMenu itemAtIndex:i] isSeparatorItem])
			break;
		[aMenu removeItemAtIndex:i];
	}

	std::multimap<std::string, bundles::item_ptr, text::less_t> ordered;
	for(auto const& item : bundles::query(bundles::kFieldAny, NULL_STR, scope::wildcard, bundles::kItemTypeBundle))
		ordered.emplace(item->name(), item);

	for(auto const& pair : ordered)
	{
		if(pair.second->menu().empty())
			continue;

		NSMenuItem* menuItem = [aMenu addItemWithTitle:[NSString stringWithCxxString:pair.first] action:NULL keyEquivalent:@""];
		menuItem.submenu = [[NSMenu alloc] initWithTitle:[NSString stringWithCxxString:pair.second->uuid()]];
		menuItem.submenu.delegate = BundleMenuDelegate.sharedInstance;
	}

	if(ordered.empty())
		[aMenu addItemWithTitle:@"No Bundles Loaded" action:@selector(nop:) keyEquivalent:@""];
}

+ (void)initialize
{
	[NSUserDefaults.standardUserDefaults registerDefaults:@{
		@"universalThemeUUID": @(kMacClassicThemeUUID),
		@"darkModeThemeUUID":  @(kTwilightThemeUUID),
	}];

	// MIGRATION from 2.0.12 and earlier
	__weak __block id token = [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidFinishLaunchingNotification object:NSApp queue:nil usingBlock:^(NSNotification* notification){
		[NSNotificationCenter.defaultCenter removeObserver:token];

		std::string const savedThemeUUID = settings_for_path().get(kSettingsThemeKey);
		if(savedThemeUUID != NULL_STR)
		{
			os_log(OS_LOG_DEFAULT, "Remove old theme setting from Global.tmProperties: %{public}@", to_ns(savedThemeUUID));
			settings_t::set(kSettingsThemeKey, NULL_STR);

			if(bundles::item_ptr themeItem = bundles::lookup(savedThemeUUID))
			{
				bool darkTheme = themeItem->value_for_field(bundles::kFieldSemanticClass).find("theme.dark") == 0;
				NSString* mode        = darkTheme ? @"dark"              : @"light";
				NSString* defaultsKey = darkTheme ? @"darkModeThemeUUID" : @"universalThemeUUID";

				os_log(OS_LOG_DEFAULT, "Set preferred appearance to %{public}@", mode);
				[NSUserDefaults.standardUserDefaults setObject:to_ns(savedThemeUUID) forKey:defaultsKey];
				[NSUserDefaults.standardUserDefaults setObject:mode forKey:@"themeAppearance"];
			}
		}

		[NSUserDefaults.standardUserDefaults removeObjectForKey:@"changeThemeBasedOnAppearance"];
	}];

	// Apply the theme appearance to the *application*, not just the editor. See
	// +applyThemeAppearance. Both on the main queue deliberately: user-defaults
	// change notifications are delivered on whichever thread made the change —
	// including another process — and NSApp.appearance is main-thread-only. That
	// is the same hazard that shipped as the alpha.13 Software Update crash.
	[NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidFinishLaunchingNotification object:NSApp queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* notification){
		[self applyThemeAppearance];
	}];

	[NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:NSUserDefaults.standardUserDefaults queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* notification){
		[self applyThemeAppearance];
	}];
}

// Make the window chrome follow the chosen theme appearance.
//
// **This diverges from upstream on purpose.** Upstream treats `themeAppearance`
// as picking an editor *theme* and lets AppKit chrome follow the system, so on a
// light-appearance Mac choosing Dark gives a black editor inside a white window
// with a white file browser. Nothing in this project's history ever set
// NSApp.appearance — checked with `git log -S` across all branches — so this is
// new behaviour rather than a restored regression. Reported 2026-08-18 as
// "the sidebar stays light in dark mode", which is a fair reading of it.
//
// `nil` is the important case: Auto must leave NSApp.appearance unset so the app
// follows the system, which is what makes -viewDidChangeEffectiveAppearance fire
// and OakTextView re-resolve its theme. Setting an explicit appearance instead
// would pin it and break Auto.
//
// No feedback loop, and the reason is worth stating: -effectiveThemeUUID only
// consults -effectiveAppearance when the setting is Auto, and Auto is exactly
// the case where this sets nothing. An explicit Light/Dark never round-trips
// through the appearance it just set.
//
// The guard is not an optimisation. Assigning NSApp.appearance re-broadcasts
// -viewDidChangeEffectiveAppearance to every view in the app, and this runs on
// every user-defaults change — which is frequent.
+ (void)applyThemeAppearance
{
	NSString* setting = [NSUserDefaults.standardUserDefaults stringForKey:@"themeAppearance"];

	NSAppearanceName name = nil;
	if([setting isEqualToString:@"dark"])
		name = NSAppearanceNameDarkAqua;
	else if([setting isEqualToString:@"light"])
		name = NSAppearanceNameAqua;

	NSAppearanceName currentName = NSApp.appearance.name; // nil when never set
	if(currentName == name || [currentName isEqualToString:name])
		return;

	NSApp.appearance = name ? [NSAppearance appearanceNamed:name] : nil;
}

- (void)takeThemeAppearanceFrom:(id)sender
{
	[NSUserDefaults.standardUserDefaults setObject:[sender representedObject] forKey:@"themeAppearance"];
	// The defaults notification would reach +applyThemeAppearance anyway; calling
	// it here makes the menu feel synchronous. Idempotent, so the later
	// notification is a no-op.
	[AppController applyThemeAppearance];
}

- (void)takeUniversalThemeUUIDFrom:(id)sender
{
	[NSUserDefaults.standardUserDefaults setObject:[sender representedObject] forKey:@"universalThemeUUID"];
}

- (void)takeDarkThemeUUIDFrom:(id)sender
{
	[NSUserDefaults.standardUserDefaults setObject:[sender representedObject] forKey:@"darkModeThemeUUID"];
}

- (BOOL)validateThemeMenuItem:(NSMenuItem*)item
{
	if(item.action == @selector(takeThemeAppearanceFrom:))
	{
		NSString* savedValue = [NSUserDefaults.standardUserDefaults stringForKey:@"themeAppearance"];
		item.state = !item.representedObject && !savedValue || [item.representedObject isEqualToString:savedValue] ? NSControlStateValueOn : NSControlStateValueOff;

		NSString* label;
		NSString* defaultsKey;
		if([item.representedObject isEqualToString:@"light"])
		{
			label = @"Light Theme";
			defaultsKey = @"universalThemeUUID";
		}
		else if([item.representedObject isEqualToString:@"dark"])
		{
			label = @"Dark Theme";
			defaultsKey = @"darkModeThemeUUID";
		}

		if(defaultsKey)
		{
			NSString* themeUUID = [NSUserDefaults.standardUserDefaults stringForKey:defaultsKey];
			if(bundles::item_ptr themeItem = bundles::lookup(to_s(themeUUID)))
				item.title = [NSString stringWithFormat:@"%@ (%@)", label, to_ns(themeItem->name())];
		}
	}
	else if(item.action == @selector(takeUniversalThemeUUIDFrom:))
		item.state = [item.representedObject isEqualToString:[NSUserDefaults.standardUserDefaults stringForKey:@"universalThemeUUID"]] ? NSControlStateValueOn : NSControlStateValueOff;
	else if(item.action == @selector(takeDarkThemeUUIDFrom:))
		item.state = [item.representedObject isEqualToString:[NSUserDefaults.standardUserDefaults stringForKey:@"darkModeThemeUUID"]] ? NSControlStateValueOn : NSControlStateValueOff;
	return YES;
}

- (void)themesMenuNeedsUpdate:(NSMenu*)aMenu
{
	[aMenu removeAllItems];

	std::map<std::string, std::multimap<std::string, bundles::item_ptr, text::less_t>> ordered;
	for(auto const& item : bundles::query(bundles::kFieldAny, NULL_STR, scope::wildcard, bundles::kItemTypeTheme))
	{
		if(item->hidden_from_user())
			continue;

		auto semanticClass = text::split(item->value_for_field(bundles::kFieldSemanticClass), ".");
		std::string themeClass = semanticClass.size() > 2 && semanticClass.front() == "theme" ? semanticClass[1] : "unspecified";
		ordered[themeClass].emplace(item->name(), item);
	}

	if(ordered.empty())
	{
		[aMenu addItemWithTitle:@"No Themes Loaded" action:@selector(nop:) keyEquivalent:@""];
		return;
	}

	NSMenu* lightMenu;
	NSMenu* darkMenu;

	MBMenu const items = {
		{ @"Appearance",       @selector(nop:),                                                                          },
		{ @"Light",            @selector(takeThemeAppearanceFrom:), .indent = 1, .target = self, .representedObject = @"light" },
		{ @"Dark",             @selector(takeThemeAppearanceFrom:), .indent = 1, .target = self, .representedObject = @"dark"  },
		{ @"Auto",             @selector(takeThemeAppearanceFrom:), .indent = 1, .target = self, .representedObject = nil      },
		{ /* -------- */ },
		{ @"Theme for Light Appearance", .submenuRef = &lightMenu },
		{ @"Theme for Dark Appearance",  .submenuRef = &darkMenu  },
	};
	MBCreateMenu(items, aMenu);

	for(NSMenu* submenu : { lightMenu, darkMenu })
	{
		std::string skipThemeClass = submenu == lightMenu ? "dark" : "light";
		SEL action = submenu == lightMenu ? @selector(takeUniversalThemeUUIDFrom:) : @selector(takeDarkThemeUUIDFrom:);

		for(auto const& themeClasses : ordered)
		{
			if(themeClasses.first == skipThemeClass)
				continue;

			if(submenu.numberOfItems)
				[submenu addItem:[NSMenuItem separatorItem]];

			for(auto const& pair : themeClasses.second)
			{
				NSMenuItem* menuItem = [submenu addItemWithTitle:[NSString stringWithCxxString:pair.first] action:action keyEquivalent:@""];
				[menuItem setKeyEquivalentCxxString:key_equivalent(pair.second)];
				[menuItem setRepresentedObject:[NSString stringWithCxxString:pair.second->uuid()]];
			}
		}
	}
}

- (void)spellingMenuNeedsUpdate:(NSMenu*)aMenu
{
	for(NSInteger i = aMenu.numberOfItems; i--; )
	{
		NSMenuItem* item = [aMenu itemAtIndex:i];
		if([item action] == @selector(takeSpellingLanguageFrom:))
			[aMenu removeItemAtIndex:i];
	}

	std::multimap<std::string, NSString*, text::less_t> ordered;

	NSSpellChecker* spellChecker = NSSpellChecker.sharedSpellChecker;
	for(NSString* lang in [spellChecker availableLanguages])
		ordered.emplace(to_s(NameForLocaleIdentifier(lang)), lang);

	NSString* systemSpellingLanguage = [spellChecker automaticallyIdentifiesLanguages] ? @"Automatic by Language" : NameForLocaleIdentifier([spellChecker language]);
	NSMenuItem* menuItem = [aMenu addItemWithTitle:[NSString stringWithFormat:@"System (%@)", systemSpellingLanguage] action:@selector(takeSpellingLanguageFrom:) keyEquivalent:@""];
	menuItem.representedObject = @"";

	for(auto const& it : ordered)
	{
		NSMenuItem* menuItem = [aMenu addItemWithTitle:[NSString stringWithCxxString:it.first] action:@selector(takeSpellingLanguageFrom:) keyEquivalent:@""];
		menuItem.representedObject = it.second;
	}
}

- (void)wrapColumnMenuNeedsUpdate:(NSMenu*)aMenu
{
	[aMenu removeAllItems];

	SEL action = @selector(takeWrapColumnFrom:);
	NSMenuItem* menuItem;

	menuItem = [aMenu addItemWithTitle:@"Use Window Frame" action:action keyEquivalent:@""];
	menuItem.tag = NSWrapColumnWindowWidth;
	[aMenu addItem:[NSMenuItem separatorItem]];

	NSArray* presets = [NSUserDefaults.standardUserDefaults arrayForKey:kUserDefaultsWrapColumnPresetsKey];
	for(NSNumber* preset in [presets sortedArrayUsingSelector:@selector(compare:)])
	{
		menuItem = [aMenu addItemWithTitle:[NSString stringWithFormat:@"%@", preset] action:action keyEquivalent:@""];
		menuItem.tag = [preset integerValue];
	}

	[aMenu addItem:[NSMenuItem separatorItem]];
	menuItem = [aMenu addItemWithTitle:@"Other…" action:action keyEquivalent:@""];
	menuItem.tag = NSWrapColumnAskUser;
}

- (void)menuNeedsUpdate:(NSMenu*)aMenu
{
	if(aMenu == bundlesMenu)
		[self bundlesMenuNeedsUpdate:aMenu];
	else if(aMenu == themesMenu)
		[self themesMenuNeedsUpdate:aMenu];
	else if(aMenu == spellingMenu)
		[self spellingMenuNeedsUpdate:aMenu];
	else if(aMenu == wrapColumnMenu)
		[self wrapColumnMenuNeedsUpdate:aMenu];
}
@end
