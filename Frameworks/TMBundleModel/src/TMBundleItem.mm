#import "TMBundleModelCxx.h"
#import <OakFoundation/NSString Additions.h>
#import <text/ctype.h>
#import <ns/ns.h>

NSNotificationName const TMBundleItemsDidChangeNotification = @"TMBundleItemsDidChangeNotification";

// The header's raw values are load-bearing — they cross into Swift as a
// TMBundleItemKind enum and are compared against items coming back out of the
// C++ index. A divergence would compile clean and mis-route every menu item,
// so it is pinned here rather than trusted.
static_assert((NSUInteger)bundles::kItemTypeCommand           == TMBundleItemKindCommand,           "TMBundleItemKind out of sync with bundles::kind_t");
static_assert((NSUInteger)bundles::kItemTypeDragCommand       == TMBundleItemKindDragCommand,       "TMBundleItemKind out of sync with bundles::kind_t");
static_assert((NSUInteger)bundles::kItemTypeGrammar           == TMBundleItemKindGrammar,           "TMBundleItemKind out of sync with bundles::kind_t");
static_assert((NSUInteger)bundles::kItemTypeMacro             == TMBundleItemKindMacro,             "TMBundleItemKind out of sync with bundles::kind_t");
static_assert((NSUInteger)bundles::kItemTypeSettings          == TMBundleItemKindSettings,          "TMBundleItemKind out of sync with bundles::kind_t");
static_assert((NSUInteger)bundles::kItemTypeSnippet           == TMBundleItemKindSnippet,           "TMBundleItemKind out of sync with bundles::kind_t");
static_assert((NSUInteger)bundles::kItemTypeProxy             == TMBundleItemKindProxy,             "TMBundleItemKind out of sync with bundles::kind_t");
static_assert((NSUInteger)bundles::kItemTypeTheme             == TMBundleItemKindTheme,             "TMBundleItemKind out of sync with bundles::kind_t");
static_assert((NSUInteger)bundles::kItemTypeBundle            == TMBundleItemKindBundle,            "TMBundleItemKind out of sync with bundles::kind_t");
static_assert((NSUInteger)bundles::kItemTypeMenu              == TMBundleItemKindMenu,              "TMBundleItemKind out of sync with bundles::kind_t");
static_assert((NSUInteger)bundles::kItemTypeMenuItemSeparator == TMBundleItemKindMenuItemSeparator, "TMBundleItemKind out of sync with bundles::kind_t");
static_assert((NSUInteger)bundles::kItemTypeUnknown           == TMBundleItemKindUnknown,           "TMBundleItemKind out of sync with bundles::kind_t");

// -init is NS_UNAVAILABLE to callers — instances only ever come from the intern
// table — so the table needs a spelling of its own to allocate through.
@interface TMBundleItem ()
- (instancetype)initPrivate;
@end

@implementation TMBundleItem
{
	bundles::item_ptr _item;
}

// bundles::callback_t is a C++ struct with virtual methods, so no Swift type can
// subclass it. Exactly one subscriber exists for the whole process and it
// re-broadcasts as a notification, which is what lets every consumer stay free
// of C++ rather than each carrying its own ObjC++ shim for this.
//
// ⚠️ This CANNOT be registered directly from +load, though that is where it
// belongs. **dyld runs ObjC +load methods before the C++ static initializers of
// the same image**, and bundles::query.cc's `Callbacks` is a
// oak::callbacks_t — which has a user-provided constructor, so it is
// dynamically initialized, and its std::mutex is still raw memory at +load
// time. Calling add_callback there aborts the process with
// "mutex lock failed: Invalid argument" — not a link error, not a warning, a
// crash at launch. Found by a test; it would have been found by the app.
//
// So registration happens from two places, each covering what the other cannot:
static void RegisterBundleCallback ()
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		struct callback_t : bundles::callback_t
		{
			void bundles_did_change ()
			{
				// The index can be rebuilt off the main thread (BundlesManager
				// reloads in the background); AppKit observers cannot be.
				dispatch_async(dispatch_get_main_queue(), ^{
					[NSNotificationCenter.defaultCenter postNotificationName:TMBundleItemsDidChangeNotification object:nil];
				});
			}
		};

		static callback_t cb;
		bundles::add_callback(&cb);
	});
}

// …the first main-queue turn, by which time every static initializer has run.
// This is what covers a consumer that only ever observes the notification and
// never messages this class — BundleEditor is exactly that.
+ (void)load
{
	dispatch_async(dispatch_get_main_queue(), ^{ RegisterBundleCallback(); });
}

// …and the first message to the class, which covers an index change that
// happens before the run loop has turned at all. +initialize is safe where
// +load is not: it fires on a message send, long after image initialization.
+ (void)initialize
{
	RegisterBundleCallback();
}

- (instancetype)initPrivate
{
	return [super init];
}

// Interning table, keyed on the raw item_t* and holding the wrapper weakly.
//
// Both consumers put these objects in identity-keyed containers that used to be
// std::set<item_ptr>/std::map<item_ptr, …>, so two wrappers of one bundle item
// have to be indistinguishable. -isEqual:/-hash below would be enough for that;
// interning additionally makes `===` hold, which is what a Swift caller reaches
// for first, and keeps a menu rebuild from allocating a fresh wrapper per item.
//
// The key is an NSValue over the raw item_t*, not the pointer cast to `id`:
// an opaque-personality table would accept the cast, but ARC retains anything
// it sees as an object across the call, and sending -retain to a C++ object
// is a crash. NSValue hashes and compares by the pointer, so the behaviour is
// the same for the price of one allocation per lookup.
static NSMapTable<NSValue*, TMBundleItem*>* InternTable ()
{
	static NSMapTable* res = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory|NSPointerFunctionsObjectPersonality valueOptions:NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPersonality capacity:0];
	return res;
}

static std::mutex& InternMutex ()
{
	static std::mutex res;
	return res;
}

+ (TMBundleItem*)itemWithCxxItem:(bundles::item_ptr const&)item
{
	if(!item)
		return nil;

	NSValue* key = [NSValue valueWithPointer:item.get()];
	std::lock_guard<std::mutex> lock(InternMutex());

	NSMapTable* table = InternTable();
	if(TMBundleItem* existing = [table objectForKey:key])
		return existing;

	TMBundleItem* res = [[TMBundleItem alloc] initPrivate];
	res->_item = item;
	[table setObject:res forKey:key];
	return res;
}

+ (NSArray<TMBundleItem*>*)itemsWithCxxItems:(std::vector<bundles::item_ptr> const&)items
{
	NSMutableArray<TMBundleItem*>* res = [NSMutableArray arrayWithCapacity:items.size()];
	for(auto const& item : items)
	{
		if(TMBundleItem* wrapped = [self itemWithCxxItem:item])
			[res addObject:wrapped];
	}
	return res;
}

- (bundles::item_ptr)cxxItem
{
	return _item;
}

+ (TMBundleItem*)itemWithUUIDString:(NSString*)uuidString
{
	std::string const str = to_s(uuidString);
	// Guarded rather than handed straight to oak::uuid_t, which logs an error and
	// then CLEARS an unparseable string to all-zeroes. A malformed uuid in an
	// installed bundle's plist clears the same way, so that item sits in the index
	// under the zero UUID — and every non-UUID string would then resolve to it.
	if(!uuidString || !oak::uuid_t::is_valid(str))
		return nil;
	return [self itemWithCxxItem:bundles::lookup(str)];
}

+ (TMBundleItem*)menuItemSeparator
{
	return [self itemWithCxxItem:bundles::item_t::menu_item_separator()];
}

+ (NSArray<TMBundleItem*>*)itemsForProxy:(TMBundleItem*)proxyItem scope:(TMScopeContext*)scope
{
	return [self itemsWithCxxItems:bundles::items_for_proxy(proxyItem.cxxItem, (scope ?: TMScopeContext.wildcardScope).cxxContext)];
}

+ (NSArray<TMBundleItem*>*)itemsSortedByName:(NSArray<TMBundleItem*>*)items
{
	// stable_sort, not sort: the ObjC++ original ordered through a
	// std::multimap keyed on the name, which keeps equally-named items in
	// insertion order. Menu order is user-visible, so that is behaviour.
	std::vector<bundles::item_ptr> cxxItems = TMCxxItemsFromArray(items);
	std::stable_sort(cxxItems.begin(), cxxItems.end(), [](bundles::item_ptr const& lhs, bundles::item_ptr const& rhs){
		return text::less_t()(lhs->name(), rhs->name());
	});
	return [self itemsWithCxxItems:cxxItems];
}

- (TMBundleItemKind)kind
{
	return (TMBundleItemKind)_item->kind();
}

- (NSString*)name
{
	return [NSString stringWithCxxString:_item->name()];
}

- (NSString*)uuidString
{
	return [NSString stringWithCxxString:to_s(_item->uuid())];
}

- (NSString*)tabTrigger
{
	return [NSString stringWithCxxString:_item->value_for_field(bundles::kFieldTabTrigger)];
}

- (NSString*)keyEquivalent
{
	return [NSString stringWithCxxString:bundles::key_equivalent(_item)];
}

- (TMBundleItem*)bundle
{
	return [TMBundleItem itemWithCxxItem:_item->bundle()];
}

- (NSArray<TMBundleItem*>*)menu
{
	return [TMBundleItem itemsWithCxxItems:_item->menu()];
}

- (NSString*)semanticClass
{
	return [NSString stringWithCxxString:_item->value_for_field(bundles::kFieldSemanticClass)];
}

- (NSString*)nameWithBundle
{
	return [NSString stringWithCxxString:_item->name_with_bundle()];
}

- (NSArray<NSString*>*)paths
{
	NSMutableArray<NSString*>* res = [NSMutableArray array];
	for(auto const& path : _item->paths())
	{
		// A path is bytes, not necessarily UTF-8 — go through the file-system
		// representation rather than +stringWithCxxString:, which would drop a
		// path this process can still open.
		if(NSString* str = [NSFileManager.defaultManager stringWithFileSystemRepresentation:path.data() length:path.size()])
			[res addObject:str];
	}
	return res;
}

- (NSString*)supportPath
{
	return [NSString stringWithCxxString:_item->support_path()];
}

- (BOOL)isDisabled
{
	return _item->disabled();
}

- (BOOL)isHiddenFromUser
{
	return _item->hidden_from_user();
}

// ==================
// = Property bag   =
// ==================

- (NSDictionary*)properties
{
	return ns::to_mutable_dictionary(_item->plist()) ?: @{};
}

- (void)setProperties:(NSDictionary*)properties
{
	_item->set_plist(plist::convert((__bridge CFPropertyListRef)(properties ?: @{})));
}

- (NSArray<NSString*>*)valuesForField:(NSString*)field
{
	NSMutableArray<NSString*>* res = [NSMutableArray array];
	for(auto const& value : _item->values_for_field(to_s(field)))
	{
		if(NSString* str = [NSString stringWithCxxString:value])
			[res addObject:str];
	}
	return res;
}

- (BOOL)storedPropertiesEqual:(NSDictionary*)properties
{
	return plist::equal(plist::convert((__bridge CFPropertyListRef)(properties ?: @{})), _item->plist());
}

// ================================
// = Persistence and the index    =
// ================================

- (BOOL)save
{
	return _item->save();
}

- (BOOL)saveToDirectory:(NSString*)directory
{
	return _item->save_to(to_s(directory));
}

- (BOOL)moveToTrash
{
	return _item->move_to_trash();
}

+ (TMBundleItem*)createItemOfKind:(TMBundleItemKind)kind inBundle:(TMBundleItem*)bundle properties:(NSDictionary*)properties
{
	auto item = std::make_shared<bundles::item_t>(oak::uuid_t().generate(), bundle.cxxItem, (bundles::kind_t)kind);

	// The generated UUID has to reach the plist too: it is what the item is
	// looked up by once saved, and set_plist would otherwise leave the stored
	// copy without one.
	plist::dictionary_t plist = plist::convert((__bridge CFPropertyListRef)(properties ?: @{}));
	plist[bundles::kFieldUUID] = to_s(item->uuid());
	item->set_plist(plist);

	bundles::add_item(item);
	return [self itemWithCxxItem:item];
}

- (void)removeFromIndex
{
	bundles::remove_item(_item);
}

+ (NSArray<TMBundleItem*>*)itemsInBundle:(TMBundleItem*)bundle ofKinds:(TMBundleItemKind)kinds
{
	// filter:false and includeDisabledItems:true — the Bundle Editor lists what
	// is there, not what would apply in some scope, and a disabled item is
	// precisely the thing a user opens the editor to re-enable.
	//
	// resolveProxyItems:false is the eighth argument and was **missing** until
	// 2026-09-03, so it defaulted to true and this query silently expanded every
	// proxy into the items it stands for — returning the targets and never the
	// proxy. The header has always said "with proxies left unresolved"; the call
	// did not do it. Its one caller is Export Bundle, so exporting a bundle
	// dropped its proxy items.
	oak::uuid_t const bundleUUID = bundle ? bundle.cxxItem->uuid() : oak::uuid_t();
	return [self itemsWithCxxItems:bundles::query(bundles::kFieldAny, NULL_STR, scope::wildcard, (int)kinds, bundleUUID, false, true, false)];
}

+ (NSArray<TMBundleItem*>*)itemsOfKinds:(TMBundleItemKind)kinds inScope:(TMScopeContext*)scope
{
	// Every trailing argument left at its default: bundle = any, filter = true,
	// includeDisabledItems = false, resolveProxyItems = true. That is the exact
	// call the menus in AppController Menus.mm make.
	return [self itemsWithCxxItems:bundles::query(bundles::kFieldAny, NULL_STR, scope ? scope.cxxContext : scope::wildcard, (int)kinds)];
}

// Interning makes these redundant today. They are spelled out anyway because
// the identity contract is what both consumers' containers are built on, and a
// regression in the intern table should degrade to "equal but not identical"
// rather than to two items that compare unequal.
- (BOOL)isEqual:(id)other
{
	if(self == other)
		return YES;
	TMBundleItem* item = [other isKindOfClass:TMBundleItem.class] ? other : nil;
	return item && item->_item == _item;
}

- (NSUInteger)hash
{
	return (NSUInteger)std::hash<bundles::item_t*>()(_item.get());
}

- (id)copyWithZone:(NSZone*)zone
{
	return self; // immutable and interned
}

- (NSString*)description
{
	return [NSString stringWithFormat:@"<%@: %@ (%@)>", self.class, self.name, self.uuidString];
}

@end

std::vector<bundles::item_ptr> TMCxxItemsFromArray (NSArray<TMBundleItem*>* items)
{
	std::vector<bundles::item_ptr> res;
	res.reserve(items.count);
	for(TMBundleItem* item in items)
	{
		if(bundles::item_ptr cxxItem = item.cxxItem)
			res.push_back(cxxItem);
	}
	return res;
}
