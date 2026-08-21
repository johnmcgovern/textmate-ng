#import "BundleItemChooserSupport.h"
#import "OakChooserMarkup.h"
#import "OakAbbreviations.h"
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakAppKit/OakKeyEquivalentView.h>
#import <OakAppKit/OakScopeBarView.h>
#import <OakAppKit/NSColor Additions.h>
#import <OakAppKit/NSImage Additions.h>
#import <OakFoundation/OakFoundation.h>
#import <OakFoundation/NSString Additions.h>
#import <OakSystem/application.h>
#import <TMFileReference/TMFileReference.h>
#import <bundles/bundles.h>
#import <settings/settings.h>
#import <text/ranker.h>
#import <text/case.h>
#import <text/ctype.h>
#import <regexp/format_string.h>
#import <ns/ns.h>
#import <ns/event.h>
#import <TMBundleModel/TMBundleModelCxx.h>

// The C++ half of BundleItemChooser, moved from BundleItemChooser.mm (2026-08-21); see
// BundleItemChooserSupport.h for what is here and why.
//
// Everything below came out of the original with `git show` rather than retyping (rule 6)
// and is asserted byte-identical by t_bundle_item_chooser_support.mm. The only edits are
// mechanical: the constants lost `static` because the header exports them now, and
// -unfilteredItems became a class method whose six reads from self
// (scope, hasSelection, searchSource, searchAllScopes, path, directory) are parameters —
// named documentPath/documentDirectory rather than path/directory, because the body
// already has C++ locals called `path` that a parameter of that name would shadow.

NSUInteger const kBundleItemTitleField          = 0;
NSUInteger const kBundleItemKeyEquivalentField  = 1;
NSUInteger const kBundleItemTabTriggerField     = 2;
NSUInteger const kBundleItemSemanticClassField  = 3;
NSUInteger const kBundleItemScopeSelectorField  = 4;

NSUInteger const kSearchSourceActionItems      = (1 << 0);
NSUInteger const kSearchSourceSettingsItems    = (1 << 1);
NSUInteger const kSearchSourceGrammarItems     = (1 << 2);
NSUInteger const kSearchSourceThemeItems       = (1 << 3);
NSUInteger const kSearchSourceDragCommandItems = (1 << 4);
NSUInteger const kSearchSourceMenuItems        = (1 << 5);
NSUInteger const kSearchSourceKeyBindingItems  = (1 << 6);

static NSString* OakMenuItemIdentifier (NSMenuItem* menuItem)
{
	if(!menuItem.action)
		return nil;

	NSString* str = NSStringFromSelector(menuItem.action);
	return menuItem.tag ? [str stringByAppendingFormat:@"%ld", menuItem.tag] : str;
}

// ==============
// = ActionItem =
// ==============

@implementation ActionItem
- (void)reset
{
	_matched = NO;
	_rank    = 0;
	_name    = nil;
	_path    = nil;
}

- (void)updateRankUsingFilter:(std::string const&)filter bundleItemField:(NSUInteger)bundleItemField searchSource:(NSUInteger)searchSource bindings:(NSArray<NSString*>*)identifiers defaultRank:(double)rank
{
	[self reset];

	std::vector<std::pair<size_t, size_t>> cover_path, cover_name;
	std::string name = to_s(_itemName);
	std::string path = to_s(_location);

	if(filter != NULL_STR && !filter.empty())
	{
		auto OakContainsString = [](NSString* haystack, NSString* needle) -> BOOL {
			return haystack && needle && [haystack rangeOfString:needle].location != NSNotFound;
		};

		if(bundleItemField == kBundleItemTitleField)
		{
			std::vector<std::pair<size_t, size_t>> cover;
			if(searchSource & (kSearchSourceActionItems|kSearchSourceMenuItems|kSearchSourceKeyBindingItems))
			{
				if(rank = oak::rank(filter, name, &cover))
						rank += 1;
				else	rank = oak::rank(filter, path + " " + name, &cover);
			}
			else
			{
				auto is_substr = [&cover](std::string const& needle, std::string const& haystack) -> BOOL {
					NSString* str = to_ns(haystack);
					NSRange r = [str rangeOfString:to_ns(needle) options:NSCaseInsensitiveSearch];
					if(r.location != NSNotFound)
						cover.emplace_back(to_s([str substringToIndex:r.location]).size(), to_s([str substringToIndex:NSMaxRange(r)]).size());
					return r.location != NSNotFound;
				};

				if(is_substr(filter, name))
					rank += 1;
				else if(!is_substr(filter, path + " " + name))
					rank = 0;
			}

			for(auto pair : cover)
			{
				if(rank > 1)
					cover_name.push_back(pair);
				else if(pair.first < path.size())
					cover_path.emplace_back(pair.first, std::min(pair.second, path.size()));
				else if(path.size() + 1 < pair.second)
					cover_name.emplace_back(std::max(pair.first, path.size() + 1) - path.size() - 1, pair.second - path.size() - 1);
			}
		}
		else if(bundleItemField == kBundleItemKeyEquivalentField)
			rank = [_keyEquivalent isEqualToString:to_ns(filter)] ? rank : 0;
		else if(bundleItemField == kBundleItemTabTriggerField)
			rank = OakContainsString(_tabTrigger, to_ns(filter)) ? rank : 0;
		else if(bundleItemField == kBundleItemSemanticClassField)
			rank = OakContainsString(_semanticClass, to_ns(filter)) ? rank : 0;
		else if(bundleItemField == kBundleItemScopeSelectorField)
			rank = OakContainsString(_scopeSelector, to_ns(filter)) ? rank : 0;
	}

	if(_matched = (rank > 0 ? YES : NO))
	{
		if(bundleItemField == kBundleItemTitleField)
		{
			NSUInteger i = [identifiers indexOfObject:(_uuid ?: NSStringFromSelector(_action) ?: OakMenuItemIdentifier(_menuItem))];
			if(i != NSNotFound)
				rank = 2 + (identifiers.count - i) / identifiers.count;
		}

		if(NSString* value = _value)
			name += " = " + to_s(value);

		NSMutableAttributedString* str = CreateAttributedStringWithMarkedUpRanges(name, cover_name, NSLineBreakByTruncatingTail);
		if(_eclipsed)
			[str addAttribute:NSStrikethroughStyleAttributeName value:@(NSUnderlineStyleSingle|NSUnderlinePatternSolid) range:NSMakeRange(0, str.length)];

		self.name = str;
		self.path = CreateAttributedStringWithMarkedUpRanges(path, cover_path, NSLineBreakByTruncatingHead);
		_rank = 3 - rank;
	}
}
@end

static std::string key_equivalent_for_menu_item (NSMenuItem* menuItem)
{
	if(OakIsEmptyString([menuItem keyEquivalent]))
		return NULL_STR;

	static struct { NSUInteger flag; std::string symbol; } const EventFlags[] =
	{
		{ NSEventModifierFlagNumericPad, "#" },
		{ NSEventModifierFlagControl,    "^" },
		{ NSEventModifierFlagOption,     "~" },
		{ NSEventModifierFlagShift,      "$" },
		{ NSEventModifierFlagCommand,    "@" },
	};

	std::string key  = to_s([menuItem keyEquivalent]);
	NSUInteger flags = [menuItem keyEquivalentModifierMask];

	if(flags & NSEventModifierFlagShift)
	{
		std::string const upCased = text::uppercase(key);
		if(key != upCased)
		{
			flags &= ~NSEventModifierFlagShift;
			key = upCased;
		}
	}

	std::string modifiers = "";
	for(auto const& record : EventFlags)
		modifiers += (flags & record.flag) ? record.symbol : "";
	return modifiers + key;
}

namespace
{
	struct menu_item_t
	{
		std::string name;
		std::string path;
		NSMenuItem* menu_item;
	};
}

template <typename _OutputIter>
_OutputIter copy_menu_items (NSMenu* menu, _OutputIter out, NSArray* parentNames = @[ ])
{
	for(NSMenuItem* item in [menu itemArray])
	{
		std::set<SEL> excludeItemsWithActions = {
			@selector(performBundleItemWithUUIDStringFrom:),
			@selector(takeThemeAppearanceFrom:),
			@selector(takeUniversalThemeUUIDFrom:),
			@selector(takeDarkThemeUUIDFrom:),
		};

		if(excludeItemsWithActions.find(item.action) != excludeItemsWithActions.end())
			continue;

		if(id target = [NSApp targetForAction:[item action]])
		{
			if(![target respondsToSelector:@selector(validateMenuItem:)] || [target validateMenuItem:item])
			{
				NSString* title = [item title];
				if([item state] == NSControlStateValueOn)
				{
					if([[[item onStateImage] name] isEqualToString:@"NSMenuItemBullet"])
							title = [title stringByAppendingString:@" (•)"];
					else	title = [title stringByAppendingString:@" (✓)"];
				}
				*out++ = { to_s(title), to_s([parentNames componentsJoinedByString:@" ‣ "]), item };
			}
		}

		if(NSMenu* submenu = [item submenu])
		{
			if(submenu.delegate && [submenu.delegate respondsToSelector:@selector(menuNeedsUpdate:)])
			{
				if([@[ @"Spelling" ] containsObject:submenu.title])
					[submenu.delegate menuNeedsUpdate:submenu];
			}
			out = copy_menu_items(submenu, out, [parentNames arrayByAddingObject:[item title]]);
		}
	}
	return out;
}

static std::vector<bundles::item_ptr> relevant_items_in_scope (scope::context_t const& scope, bool hasSelection, NSUInteger sourceMask)
{
	int mask = 0;
	if(sourceMask & kSearchSourceActionItems)
		mask |= bundles::kItemTypeCommand|bundles::kItemTypeMacro|bundles::kItemTypeSnippet;
	if(sourceMask & kSearchSourceSettingsItems)
		mask |= bundles::kItemTypeSettings;
	if(sourceMask & kSearchSourceGrammarItems)
		mask |= bundles::kItemTypeGrammar;
	if(sourceMask & kSearchSourceThemeItems)
		mask |= bundles::kItemTypeTheme;
	if(sourceMask & kSearchSourceDragCommandItems)
		mask |= bundles::kItemTypeDragCommand;
	return bundles::query(bundles::kFieldAny, NULL_STR, scope, mask, oak::uuid_t(), false);
}

@implementation BundleItemChooserSupport
+ (NSArray<ActionItem*>*)unfilteredItemsForScope:(TMScopeContext*)scopeContext hasSelection:(BOOL)hasSelection searchSource:(NSUInteger)searchSource searchAllScopes:(BOOL)searchAllScopes documentPath:(NSString*)documentPath documentDirectory:(NSString*)documentDirectory
{
	{
		auto format = [](plist::any_t const& plist) -> std::string {
			return format_string::replace(to_s(plist, plist::kPreferSingleQuotedStrings|plist::kSingleLine), "\\A\\s+|\\s+\\z|(\\s+)", "${1:+ }");
		};

		NSMutableArray<ActionItem*>* items = [NSMutableArray new];
		std::set<std::string> previousSettings, previousVariables;

		for(auto const& bundleItem : relevant_items_in_scope(searchAllScopes ? scope::wildcard : scopeContext.cxxContext, hasSelection, searchSource))
		{
			std::string const name = name_with_selection(bundleItem, hasSelection);
			std::string const path = menu_path(bundleItem);
			NSString* const uuid   = [NSString stringWithCxxString:bundleItem->uuid()];

			if(bundleItem->kind() != bundles::kItemTypeSettings)
			{
				std::string suffix;
				if(bundleItem->kind() == bundles::kItemTypeGrammar)
					suffix = " ‣ Language Grammars";
				else if(bundleItem->kind() == bundles::kItemTypeTheme)
					suffix = " ‣ Themes";

				ActionItem* item = [[ActionItem alloc] init];
				item.itemName      = to_ns(name);
				item.location      = to_ns(path + suffix);
				item.uuid          = uuid;
				item.scopeSelector = to_ns(to_s(bundleItem->scope_selector()));
				item.keyEquivalent = to_ns(key_equivalent(bundleItem));
				item.tabTrigger    = to_ns(bundleItem->value_for_field(bundles::kFieldTabTrigger));
				item.semanticClass = to_ns(text::join(bundleItem->values_for_field(bundles::kFieldSemanticClass), ", "));
				[items addObject:item];
			}
			else
			{
				plist::dictionary_t settings;
				if(plist::get_key_path(bundleItem->plist(), bundles::kFieldSettingName, settings))
				{
					for(auto const& pair : settings)
					{
						if(pair.first != "shellVariables")
						{
							ActionItem* item = [[ActionItem alloc] init];
							item.itemName      = to_ns(pair.first);
							item.value         = to_ns(format(pair.second));
							item.location      = to_ns(path + " ‣ " + name);
							item.uuid          = uuid;
							item.eclipsed      = !searchAllScopes && !previousSettings.insert(pair.first).second ? YES : NO;
							item.scopeSelector = to_ns(to_s(bundleItem->scope_selector()));
							[items addObject:item];
						}
						else
						{
							auto const shellVariables = shell_variables(bundleItem);

							BOOL eclipsed = NO;
							if(!searchAllScopes)
							{
								for(auto const& pair : shellVariables)
									eclipsed = !previousVariables.insert(pair.first).second || eclipsed;
							}

							for(auto const& pair : shellVariables)
							{
								ActionItem* item = [[ActionItem alloc] init];
								item.itemName      = to_ns(pair.first);
								item.value         = to_ns(format(pair.second));
								item.location      = to_ns(path + " ‣ " + name + " ‣ " + "shellVariables");
								item.uuid          = uuid;
								item.eclipsed      = eclipsed;
								item.scopeSelector = to_ns(to_s(bundleItem->scope_selector()));
								[items addObject:item];
							}
						}
					}
				}
			}
		}

		std::set<std::pair<std::string, std::string>> seen;
		if(searchSource & kSearchSourceMenuItems)
		{
			std::vector<menu_item_t> menuItems;
			copy_menu_items([NSApp mainMenu], back_inserter(menuItems));
			for(auto const& record : menuItems)
			{
				ActionItem* item = [[ActionItem alloc] init];
				item.itemName = to_ns(record.name);
				item.location = to_ns(record.path);
				item.menuItem = record.menu_item;

				std::string const keyEquivalent = key_equivalent_for_menu_item(record.menu_item);
				if(!keyEquivalent.empty())
					seen.emplace(keyEquivalent, sel_getName(record.menu_item.action));

				item.keyEquivalent = to_ns(keyEquivalent);
				[items addObject:item];
			}
		}

		if(searchSource & kSearchSourceKeyBindingItems)
		{
			static std::string const KeyBindingLocations[] =
			{
				oak::application_t::support("KeyBindings.dict"),
				oak::application_t::path("Contents/Resources/KeyBindings.dict"),
				path::join(path::home(), "Library/KeyBindings/DefaultKeyBinding.dict"),
				"/Library/KeyBindings/DefaultKeyBinding.dict",
				"/System/Library/Frameworks/AppKit.framework/Resources/StandardKeyBinding.dict",
			};

			std::set<std::string> keysSeen;
			for(auto const& path : KeyBindingLocations)
			{
				std::string displayPath = path::is_child(path, oak::application_t::path()) ? "TextMate.app ‣ " + path::name(path) : path::with_tilde(path);
				for(auto const& pair : plist::load(path))
				{
					std::string key = ns::normalize_event_string(pair.first);
					std::string name, action;
					if(std::string const* sel = boost::get<std::string>(&pair.second))
					{
						if(*sel == "noop:" || !seen.emplace(key, *sel).second)
							continue;

						action = *sel;
						name = format_string::replace(*sel, "[a-z](?=[A-Z])", "$0 ");
						name = format_string::replace(name, "(.+):\\z", "${1:/capitalize}");
						name = format_string::replace(name, "\\bsub Word\\b", "Sub-word");

						if(![NSApp targetForAction:NSSelectorFromString([NSString stringWithCxxString:*sel])])
							name += " (unknown action)";
					}
					else
					{
						name = format(pair.second);
					}

					ActionItem* item = [[ActionItem alloc] init];
					item.itemName      = to_ns(name);
					item.location      = to_ns(displayPath);
					item.file          = to_ns(path);
					item.keyEquivalent = to_ns(key);
					item.eclipsed      = !keysSeen.insert(key).second ? YES : NO;
					item.action        = NSSelectorFromString(to_ns(action));
					[items addObject:item];
				}
			}
		}

		if(searchSource & kSearchSourceSettingsItems)
		{
			for(auto const& info : settings_info_for_path(to_s(documentPath), searchAllScopes ? scope::wildcard : scopeContext.cxxContext.right, to_s(documentDirectory)))
			{
				std::string const name = info.variable;
				std::string const path = info.path == NULL_STR ? "TextMate.app ‣ Preferences" : (path::is_child(info.path, oak::application_t::path()) ? "TextMate.app ‣ " + path::name(info.path) : path::with_tilde(info.path)) + (info.section == NULL_STR ? "" : " ‣ " + info.section);

				ActionItem* item = [[ActionItem alloc] init];
				item.itemName = to_ns(name);
				item.value    = to_ns(format(info.value));
				item.location = to_ns(path);
				item.file     = to_ns(info.path);
				item.line     = [NSString stringWithFormat:@"%zu", info.line_number];
				[items addObject:item];
			}
		}

		return items;
	}
}

+ (NSArray<ActionItem*>*)rankedItems:(NSArray<ActionItem*>*)items filterString:(NSString*)filterString bundleItemField:(NSUInteger)bundleItemField searchSource:(NSUInteger)searchSource bindings:(NSArray<NSString*>*)bindings
{
	BOOL preserveOrder = (searchSource & kSearchSourceSettingsItems) || (bundleItemField == kBundleItemKeyEquivalentField && OakNotEmptyString(filterString));
	[items enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(ActionItem* item, NSUInteger idx, BOOL* stop){
		double rank = preserveOrder ? (items.count - idx) / (double)items.count : 1;
		[item updateRankUsingFilter:to_s(filterString) bundleItemField:bundleItemField searchSource:searchSource bindings:bindings defaultRank:rank];
	}];

	NSArray* res = [items filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isMatched == YES"]];
	return [res sortedArrayUsingDescriptors:@[
		[NSSortDescriptor sortDescriptorWithKey:@"rank" ascending:YES],
		[NSSortDescriptor sortDescriptorWithKey:@"itemName" ascending:YES selector:@selector(localizedCompare:)],
		[NSSortDescriptor sortDescriptorWithKey:@"location" ascending:YES selector:@selector(localizedCompare:)]
	]];
}

+ (NSImage*)iconForItem:(ActionItem*)item
{
	std::map<bundles::kind_t, NSString*> const map = {
		{ bundles::kItemTypeCommand,     @"Command"      },
		{ bundles::kItemTypeDragCommand, @"Drag Command" },
		{ bundles::kItemTypeSnippet,     @"Snippet"      },
		{ bundles::kItemTypeSettings,    @"Settings"     },
		{ bundles::kItemTypeGrammar,     @"Grammar"      },
		{ bundles::kItemTypeProxy,       @"Proxy"        },
		{ bundles::kItemTypeTheme,       @"Theme"        },
		{ bundles::kItemTypeMacro,       @"Macro"        },
	};

	NSImage* image = nil;
	if(NSString* uuid = item.uuid)
	{
		if(bundles::item_ptr bundleItem = bundles::lookup(to_s(uuid)))
		{
			auto it = map.find(bundleItem->kind());
			if(it != map.end())
				image = [NSImage imageNamed:it->second inSameBundleAsClass:NSClassFromString(@"BundleEditor")];
		}
	}
	else if(item.menuItem)
	{
		image = [NSImage imageNamed:@"MenuItem" inSameBundleAsClass:NSClassFromString(@"BundleEditor")];
	}
	else if(NSString* path = item.file)
	{
		if(path::is_child(to_s(path), oak::application_t::path()))
				image = [NSImage imageNamed:NSImageNameApplicationIcon];
		else	image = [TMFileReference imageForURL:[NSURL fileURLWithPath:path] size:NSMakeSize(16, 16)];
	}
	else
	{
		image = [NSImage imageNamed:@"Variables" inSameBundleAsClass:NSClassFromString(@"VariablesPreferences")];
	}

	image = [image copy];
	[image setSize:NSMakeSize(32, 32)];
	return image;
}

+ (NSAttributedString*)attributedStringForEventString:(NSString*)eventString font:(NSFont*)font
{
	return OakAttributedStringForEventString(eventString, font);
}

+ (BOOL)canAcceptItem:(ActionItem*)item
{
	return item.menuItem || item.action || item.uuid && bundles::lookup(to_s(item.uuid))->kind() != bundles::kItemTypeSettings;
}

+ (NSString*)abbreviationIdentifierForItem:(ActionItem*)item
{
	return item.uuid ?: NSStringFromSelector(item.action) ?: OakMenuItemIdentifier(item.menuItem);
}
@end
