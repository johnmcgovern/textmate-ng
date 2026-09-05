#import "AppController.h"
#import "AppControllerSupport.h"
#import <OakAppKit/NSMenuItem Additions.h>
#import <OakAppKit/OakToolTip.h>
#import <OakTextView/OakTextViewConstants.h>
#import "TextMate-Swift.h"
#import <BundleMenu/BundleMenu.h>
#import <TMBundleModel/TMBundleItem.h>
#import <theme/ThemeUUIDs.h>

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

	// -sortedByName: is stable_sort over text::less_t, which is exactly what the
	// std::multimap keyed on the name gave: equal names keep insertion order.
	NSArray<TMBundleItem*>* ordered = [TMBundleItem itemsSortedByName:[TMBundleItem itemsOfKinds:TMBundleItemKindBundle inScope:nil]];

	for(TMBundleItem* item in ordered)
	{
		if(item.menu.count == 0)
			continue;

		NSMenuItem* menuItem = [aMenu addItemWithTitle:item.name action:NULL keyEquivalent:@""];
		menuItem.submenu = [[NSMenu alloc] initWithTitle:item.uuidString];
		menuItem.submenu.delegate = BundleMenuDelegate.sharedInstance;
	}

	if(ordered.count == 0)
		[aMenu addItemWithTitle:@"No Bundles Loaded" action:@selector(nop:) keyEquivalent:@""];
}

// Was +initialize, converted to explicit registration (rule 24).
//
// A Swift class cannot provide +initialize, so this had to move before the class
// could be ported — and it is a behaviour-preserving step on its own, which is
// why it is its own commit.
//
// Timing is the whole risk in the move. +initialize ran when MainMenu.xib
// instantiated AppController; this runs at the top of
// -applicationWillFinishLaunching:, the first of the app's own code after the
// nib is loaded. Nothing reads these defaults in between — the only in-process
// reader is -[OakTextView effectiveThemeUUID], and the earliest an OakTextView
// exists is session restore, at the *end* of that same method. The three
// observers still register before NSApplicationDidFinishLaunchingNotification
// is posted, which is what they wait for.
//
// dispatch_once because +initialize ran once and these are notification
// registrations: calling it twice would apply the theme appearance twice per
// defaults change, and re-arm a migration that is supposed to happen once.
+ (void)setupThemeDefaultsAndObservers
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		[NSUserDefaults.standardUserDefaults registerDefaults:@{
			@"universalThemeUUID": @(kMacClassicThemeUUID),
			@"darkModeThemeUUID":  @(kTwilightThemeUUID),
		}];

		// MIGRATION from 2.0.12 and earlier
		__weak __block id token = [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidFinishLaunchingNotification object:NSApp queue:nil usingBlock:^(NSNotification* notification){
			[NSNotificationCenter.defaultCenter removeObserver:token];

			NSString* savedThemeUUID = AppControllerSupport.globalThemeSetting;
			if(savedThemeUUID)
			{
				os_log(OS_LOG_DEFAULT, "Remove old theme setting from Global.tmProperties: %{public}@", savedThemeUUID);
				[AppControllerSupport clearGlobalThemeSetting];

				if(TMBundleItem* themeItem = [TMBundleItem itemWithUUIDString:savedThemeUUID])
				{
					// -hasPrefix: on a nil semanticClass is NO, which is what
					// std::string::find(…) == 0 answered for NULL_STR.
					BOOL darkTheme        = [themeItem.semanticClass hasPrefix:@"theme.dark"];
					NSString* mode        = darkTheme ? @"dark"              : @"light";
					NSString* defaultsKey = darkTheme ? @"darkModeThemeUUID" : @"universalThemeUUID";

					os_log(OS_LOG_DEFAULT, "Set preferred appearance to %{public}@", mode);
					[NSUserDefaults.standardUserDefaults setObject:savedThemeUUID forKey:defaultsKey];
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
	});
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
			if(TMBundleItem* themeItem = [TMBundleItem itemWithUUIDString:themeUUID])
				item.title = [NSString stringWithFormat:@"%@ (%@)", label, themeItem.name];
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

	NSMutableDictionary<NSString*, NSMutableArray<TMBundleItem*>*>* ordered = [NSMutableDictionary dictionary];
	for(TMBundleItem* item in [TMBundleItem itemsOfKinds:TMBundleItemKindTheme inScope:nil])
	{
		if(item.isHiddenFromUser)
			continue;

		// A nil semanticClass splits to an empty array, so it falls to
		// "unspecified" — which is what text::split(NULL_STR, ".") did, since the
		// sentinel is one component and the test is `> 2`.
		NSArray<NSString*>* semanticClass = [item.semanticClass componentsSeparatedByString:@"."];
		NSString* themeClass = semanticClass.count > 2 && [semanticClass.firstObject isEqualToString:@"theme"] ? semanticClass[1] : @"unspecified";

		NSMutableArray* group = ordered[themeClass];
		if(!group)
			ordered[themeClass] = group = [NSMutableArray array];
		[group addObject:item];
	}

	if(ordered.count == 0)
	{
		[aMenu addItemWithTitle:@"No Themes Loaded" action:@selector(nop:) keyEquivalent:@""];
		return;
	}

	TMThemeMenuRefs* refs = [TMMenus buildThemeMenuInto:aMenu target:self];
	NSMenu* lightMenu = refs.lightMenu;
	NSMenu* darkMenu  = refs.darkMenu;

	// std::map iterated its keys in byte order; -compare: is the same ordering for
	// these ("dark", "light", "unspecified"), and the group order is what puts the
	// separators in the right places.
	NSArray<NSString*>* themeClasses = [ordered.allKeys sortedArrayUsingSelector:@selector(compare:)];

	// A C++ initializer_list tolerated a nil menu and messaging nil is a no-op; an
	// NSArray literal would throw instead, so build the list rather than assume
	// both submenus came back.
	NSMutableArray<NSMenu*>* submenus = [NSMutableArray array];
	if(lightMenu)
		[submenus addObject:lightMenu];
	if(darkMenu)
		[submenus addObject:darkMenu];

	for(NSMenu* submenu in submenus)
	{
		NSString* skipThemeClass = submenu == lightMenu ? @"dark" : @"light";
		SEL action = submenu == lightMenu ? @selector(takeUniversalThemeUUIDFrom:) : @selector(takeDarkThemeUUIDFrom:);

		for(NSString* themeClass in themeClasses)
		{
			if([themeClass isEqualToString:skipThemeClass])
				continue;

			if(submenu.numberOfItems)
				[submenu addItem:[NSMenuItem separatorItem]];

			for(TMBundleItem* item in [TMBundleItem itemsSortedByName:ordered[themeClass]])
			{
				NSMenuItem* menuItem = [submenu addItemWithTitle:item.name action:action keyEquivalent:@""];
				[menuItem setKeyEquivalentString:item.keyEquivalent];
				[menuItem setRepresentedObject:item.uuidString];
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

	NSSpellChecker* spellChecker = NSSpellChecker.sharedSpellChecker;

	// The display name is computed once per language, as the multimap key was —
	// NameForLocaleIdentifier builds a CFLocale each call, and a comparator would
	// invoke it O(n log n) times.
	NSMutableDictionary<NSString*, NSString*>* displayNames = [NSMutableDictionary dictionary];
	for(NSString* lang in [spellChecker availableLanguages])
		displayNames[lang] = NameForLocaleIdentifier(lang);

	// Sorting -availableLanguages rather than the dictionary's keys: NSSortStable
	// keeps equal display names in *that* order, which is the insertion order the
	// std::multimap preserved. allKeys has no defined order to be stable about.
	NSArray<NSString*>* ordered = [[spellChecker availableLanguages] sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSString* lhs, NSString* rhs){
		return [AppControllerSupport compareForMenuOrder:displayNames[lhs] to:displayNames[rhs]];
	}];

	NSString* systemSpellingLanguage = [spellChecker automaticallyIdentifiesLanguages] ? @"Automatic by Language" : NameForLocaleIdentifier([spellChecker language]);
	NSMenuItem* menuItem = [aMenu addItemWithTitle:[NSString stringWithFormat:@"System (%@)", systemSpellingLanguage] action:@selector(takeSpellingLanguageFrom:) keyEquivalent:@""];
	menuItem.representedObject = @"";

	for(NSString* lang in ordered)
	{
		NSMenuItem* menuItem = [aMenu addItemWithTitle:displayNames[lang] action:@selector(takeSpellingLanguageFrom:) keyEquivalent:@""];
		menuItem.representedObject = lang;
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
