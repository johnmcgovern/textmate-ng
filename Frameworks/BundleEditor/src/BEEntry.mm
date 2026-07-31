#import "BEEntry.h"
#import "be_entry.h"
#import <TMBundleModel/TMBundleModelCxx.h>
#import <OakFoundation/NSString Additions.h>
#import <ns/ns.h>

@interface BEEntry ()
- (instancetype)initWithEntry:(be::entry_ptr const&)entry;
@end

@implementation BEEntry
{
	be::entry_ptr _entry;
}

- (instancetype)initWithEntry:(be::entry_ptr const&)entry
{
	if(self = [super init])
		_entry = entry;
	return self;
}

// Not interned, unlike TMBundleItem. Entries are a *tree*, rebuilt wholesale
// whenever the bundle index changes, and nothing keys a container on one — the
// Bundle Editor re-finds its selection by -identifier precisely because entry
// objects do not survive a rebuild. Interning here would keep dead subtrees
// alive for no benefit.
+ (nullable BEEntry*)entryWithCxxEntry:(be::entry_ptr const&)entry
{
	return entry ? [[BEEntry alloc] initWithEntry:entry] : nil;
}

+ (BEEntry*)bundlesRoot
{
	return [self entryWithCxxEntry:be::bundle_entries()];
}

- (NSString*)name
{
	return [NSString stringWithCxxString:_entry->name()];
}

- (TMBundleItem*)representedItem
{
	return [TMBundleItem itemWithCxxItem:_entry->represented_item()];
}

- (NSString*)representedPath
{
	std::string const path = _entry->represented_path();
	if(path == NULL_STR)
		return nil;
	// Bytes, not necessarily UTF-8 — a Support directory holds whatever the
	// bundle author put there.
	return [NSFileManager.defaultManager stringWithFileSystemRepresentation:path.data() length:path.size()];
}

- (BOOL)isDisabled
{
	return _entry->disabled();
}

- (BOOL)hasChildren
{
	return _entry->has_children();
}

- (NSArray<BEEntry*>*)children
{
	auto const& children = _entry->children();
	NSMutableArray<BEEntry*>* res = [NSMutableArray arrayWithCapacity:children.size()];
	for(auto const& child : children)
	{
		if(BEEntry* wrapped = [BEEntry entryWithCxxEntry:child])
			[res addObject:wrapped];
	}
	return res;
}

- (NSString*)identifier
{
	return [NSString stringWithCxxString:_entry->identifier()];
}

- (NSString*)description
{
	return [NSString stringWithFormat:@"<%@: %@>", self.class, self.name];
}

@end
