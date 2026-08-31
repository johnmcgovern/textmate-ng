#import "FavoritesSupport.h"
#import <OakFilterList/OakChooserMarkup.h>
#import <OakFoundation/NSString Additions.h>
#import <OakSystem/application.h>   // oak::application_t::support
#import <io/entries.h>              // path::entries
#import <io/path.h>                 // path::join / resolve / name
#import <text/ranker.h>             // oak::rank
#import <ns/ns.h>

@implementation FavoritesItem
- (instancetype)initWithPath:(NSString*)path isLink:(BOOL)isLink isRemovable:(BOOL)isRemovable
{
	if(self = [super init])
	{
		// Initialised: Cocoa writes an error out-parameter only on failure, so an
		// uninitialised one leaves `if(error)` reading whatever was on the stack.
		NSError* error = nil;

		_path = isLink ? [NSFileManager.defaultManager destinationOfSymbolicLinkAtPath:path error:&error] : path;
		_link = isLink ? path : nil;

		if(error)
			os_log_error(OS_LOG_DEFAULT, "Failed to read link: %{public}@", error.localizedDescription);

		if(isLink && ![path.lastPathComponent isEqualToString:_path.lastPathComponent])
				_displayName = path.lastPathComponent;
		else	_displayName = [NSFileManager.defaultManager displayNameAtPath:_path];

		_icon = [NSWorkspace.sharedWorkspace iconForFile:_path];
		_icon.size = NSMakeSize(32, 32);

		_removable = isRemovable;
	}
	return self;
}
@end

@implementation FavoritesSupport
+ (NSArray<FavoritesItem*>*)favoritesFolderItems
{
	NSMutableArray<FavoritesItem*>* items = [NSMutableArray array];

		std::string const favoritesPath = oak::application_t::support("Favorites");
		for(auto const& entry : path::entries(favoritesPath))
		{
			if(entry->d_type == DT_LNK)
			{
				if(strncmp("[DIR] ", entry->d_name, 6) == 0)
				{
					std::string const path = path::resolve(path::join(favoritesPath, entry->d_name));
					bool includeSymlinkName = path::name(path) != std::string(entry->d_name + 6);
					for(auto const& subentry : path::entries(path))
					{
						if(subentry->d_type == DT_DIR)
						{
							FavoritesItem* item = [[FavoritesItem alloc] initWithPath:to_ns(path::join(path, subentry->d_name)) isLink:NO isRemovable:NO];
							item.displayNameSuffix = includeSymlinkName ? [NSString stringWithFormat:@" — %s", entry->d_name + 6] : nil;
							[items addObject:item];
						}
					}
				}
				else
				{
					[items addObject:[[FavoritesItem alloc] initWithPath:to_ns(path::join(favoritesPath, entry->d_name)) isLink:YES isRemovable:YES]];
				}
			}
		}

	return [items sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"displayName" ascending:YES selector:@selector(localizedCompare:)] ]];
}

+ (NSArray<FavoritesItem*>*)rankItems:(NSArray<FavoritesItem*>*)originalItems filterString:(NSString*)filterString bindings:(NSArray<NSString*>*)bindings
{

	std::string const filter = to_s([filterString decomposedStringWithCanonicalMapping]);

	std::multimap<double, FavoritesItem*> ranked;
	for(FavoritesItem* item in originalItems)
	{
		NSString* name = item.displayName;

		double rank = ranked.size();
		std::vector<std::pair<size_t, size_t>> ranges;
		if(filter != NULL_STR && filter != "")
		{
			rank = oak::rank(filter, to_s(name), &ranges);
			if(rank <= 0)
				continue;

			NSUInteger bindingIndex = [bindings indexOfObject:item.path];
			if(bindingIndex != NSNotFound)
					rank = -1.0 * (bindings.count - bindingIndex);
			else	rank = -rank;
		}

		item.name   = CreateAttributedStringWithMarkedUpRanges(to_s(item.displayNameSuffix ? [name stringByAppendingString:item.displayNameSuffix] : name), ranges, NSLineBreakByTruncatingTail);
		item.folder = CreateAttributedStringWithMarkedUpRanges(to_s(item.path.stringByDeletingLastPathComponent.stringByAbbreviatingWithTildeInPath), { }, NSLineBreakByTruncatingHead);
		ranked.emplace(rank, item);
	}

	NSMutableArray<FavoritesItem*>* res = [NSMutableArray array];
	for(auto const& pair : ranked)
		[res addObject:pair.second];
	return res;
}
@end
