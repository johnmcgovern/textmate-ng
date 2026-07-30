#import "TMBundleModelCxx.h"
#import <OakFoundation/NSString Additions.h>
#import <text/ctype.h>
#import <ns/ns.h>

// The header's raw values are load-bearing — they cross into Swift as a
// TMBundleItemKind option set and are compared against items coming back out of
// the C++ index. A divergence would compile clean and mis-route every menu item,
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
