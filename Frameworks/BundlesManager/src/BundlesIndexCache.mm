#import "BundlesIndexCache.h"
#import <bundles/load.h>
#import <bundles/locations.h>
#import <bundles/query.h> // set_index
#import <OakFoundation/NSString Additions.h>
#import <ns/ns.h>
#import <io/path.h>
#import <io/events.h>
#import <oak/debug.h>

namespace
{
	static std::string const kFieldChangedItems = "changed";
	static std::string const kFieldDeletedItems = "deleted";
	static std::string const kFieldMainMenu     = "mainMenu";

	static plist::dictionary_t prune_dictionary (plist::dictionary_t const& plist)
	{
		static auto const DesiredKeys = new std::set<std::string>{ bundles::kFieldName, bundles::kFieldKeyEquivalent, bundles::kFieldTabTrigger, bundles::kFieldScopeSelector, bundles::kFieldSemanticClass, bundles::kFieldContentMatch, bundles::kFieldGrammarFirstLineMatch, bundles::kFieldGrammarScope, bundles::kFieldGrammarInjectionSelector, bundles::kFieldDropExtension, bundles::kFieldGrammarExtension, bundles::kFieldSettingName, bundles::kFieldHideFromUser, bundles::kFieldIsDeleted, bundles::kFieldIsDisabled, bundles::kFieldRequiredItems, bundles::kFieldUUID, bundles::kFieldIsDelta, kFieldMainMenu, kFieldDeletedItems, kFieldChangedItems };

		plist::dictionary_t res;
		for(auto pair : plist)
		{
			if(DesiredKeys->find(pair.first) == DesiredKeys->end() && pair.first.find(bundles::kFieldSettingName) != 0)
				continue;

			if(pair.first == bundles::kFieldSettingName)
			{
				if(plist::dictionary_t const* dictionary = boost::get<plist::dictionary_t>(&pair.second))
				{
					plist::array_t settings;
					for(auto const& settingsPair : *dictionary)
						settings.push_back(settingsPair.first);
					res.emplace(pair.first, settings);
				}
			}
			else if(pair.first == kFieldChangedItems)
			{
				if(plist::dictionary_t const* dictionary = boost::get<plist::dictionary_t>(&pair.second))
					res.emplace(pair.first, prune_dictionary(*dictionary));
			}
			else
			{
				res.insert(pair);
			}
		}
		return res;
	}

	// The original was a function-local static that messaged
	// BundlesManager.sharedInstance. It is an ivar now, pointing back at the cache
	// that registered it; the cache lives as long as the manager does, and
	// -dealloc unwatches before the pointer can dangle.
	struct callback_t : fs::event_callback_t
	{
		__unsafe_unretained BundlesIndexCache* owner = nil;

		void set_replaying_history (bool flag, std::string const& observedPath, uint64_t eventId)
		{
			if(owner.replayingHistoryDidChange)
				owner.replayingHistoryDidChange(flag, [NSString stringWithCxxString:observedPath], eventId);
		}

		void did_change (std::string const& path, std::string const& observedPath, uint64_t eventId, bool recursive)
		{
			if(owner.pathDidChange)
				owner.pathDidChange([NSString stringWithCxxString:path], [NSString stringWithCxxString:observedPath], eventId, recursive);
		}
	};
}

@interface BundlesIndexCache ()
{
	std::vector<std::string> bundlesPaths;
	std::string bundlesIndexPath;
	std::set<std::string> watchList;
	plist::cache_t cache;
	callback_t callback;
}
@end

@implementation BundlesIndexCache
- (instancetype)init
{
	if(self = [super init])
	{
		callback.owner = self;

		for(auto path : bundles::locations())
			bundlesPaths.push_back(path::join(path, "Bundles"));
		bundlesIndexPath = path::join(path::home(), "Library/Caches/com.j23software.TextMate-NG/BundlesIndex.binary");
		cache.set_content_filter(&prune_dictionary);

		// The migration that used to live here — reading the pre-2.0-alpha.9467 plist
		// bundle index and rewriting it as capnp — was dropped with the 2026-07-26 move
		// to com.j23software.*. It only ever fired on a file written by an old MacroMates
		// build under the *old* caches dir, and nothing in this app writes a .plist index,
		// so at the new path it was unreachable. No loss: this index is a pure cache and
		// -createIndex rebuilds it.
		cache.load_capnp(bundlesIndexPath);
	}
	return self;
}

- (void)dealloc
{
	for(auto path : watchList)
		fs::unwatch(path, &callback);
}

- (void)createIndex
{
	auto pair = create_bundle_index(bundlesPaths, cache);
	bundles::set_index(pair.first, pair.second);

	std::set<std::string> newWatchList;
	for(auto path : bundlesPaths)
		cache.copy_heads_for_path(path, std::inserter(newWatchList, newWatchList.end()));
	[self updateWatchList:newWatchList];
}

- (void)save
{
	cache.cleanup(bundlesPaths);
	if(cache.dirty())
	{
		cache.save_capnp(bundlesIndexPath);
		cache.set_dirty(false);
	}
}

- (void)setEventId:(uint64_t)anEventId forPath:(NSString*)aPath
{
	cache.set_event_id_for_path(anEventId, to_s(aPath));
}

- (void)updateWatchList:(std::set<std::string> const&)newWatchList
{
	std::vector<std::string> pathsAdded, pathsRemoved;
	std::set_difference(watchList.begin(), watchList.end(), newWatchList.begin(), newWatchList.end(), back_inserter(pathsRemoved));
	std::set_difference(newWatchList.begin(), newWatchList.end(), watchList.begin(), watchList.end(), back_inserter(pathsAdded));

	watchList = newWatchList;

	for(auto path : pathsRemoved)
	{
		fs::unwatch(path, &callback);
	}

	for(auto path : pathsAdded)
	{
		fs::watch(path, &callback, cache.event_id_for_path(path) ?: FSEventsGetCurrentEventId(), 1);
	}
}

- (BOOL)erasePath:(NSString*)aPath
{
	return cache.erase(to_s(aPath));
}

- (BOOL)reloadPath:(NSString*)aPath recursive:(BOOL)flag
{
	return cache.reload(to_s(aPath), flag);
}
@end
