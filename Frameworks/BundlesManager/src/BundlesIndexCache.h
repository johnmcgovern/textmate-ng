// The bundle-index cache and its FSEvents watcher — BundlesManager's C++ model
// layer, behind an ObjC face (rule 25), so that the manager itself can be Swift.
//
// What lives here, verbatim from BundlesManager.mm (rule 6): the plist::cache_t
// and the paths it indexes, the prune filter that decides which keys of a bundle
// item's plist the cache keeps, create_bundle_index → bundles::set_index, the
// capnp load and save, and the fs::event_callback_t subclass that Swift cannot
// express (a C++ class with virtual methods). The callback reports through the
// two blocks below, which BundlesManager sets to what its old callback did:
// reload the path, record the event id.
//
// Threading is the original's: everything here runs on the main thread. The
// watch is registered from -createIndex, which the manager calls on the main
// thread, and fs::watch schedules its stream on the current run loop, so the
// callbacks — and the blocks — arrive there too.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BundlesIndexCache : NSObject
// Reads bundles::locations(), computes the index path under ~/Library/Caches,
// installs the content filter and loads the capnp cache if there is one.
- (instancetype)init;

// fs::event_callback_t::did_change and ::set_replaying_history, forwarded.
@property (nonatomic, copy, nullable) void(^pathDidChange)(NSString* path, NSString* observedPath, uint64_t eventId, BOOL recursive);
@property (nonatomic, copy, nullable) void(^replayingHistoryDidChange)(BOOL flag, NSString* observedPath, uint64_t eventId);

// create_bundle_index over the bundle paths, bundles::set_index with the result,
// and the watch list brought up to date with the cache's heads.
- (void)createIndex;

// cleanup, then save_capnp if anything is dirty.
- (void)save;

// Each answers whether the cache changed, which is what the manager uses to
// decide it needs a new index and a save.
- (BOOL)reloadPath:(NSString*)aPath recursive:(BOOL)flag;
- (BOOL)erasePath:(NSString*)aPath;

- (void)setEventId:(uint64_t)anEventId forPath:(NSString*)aPath;
@end

NS_ASSUME_NONNULL_END
