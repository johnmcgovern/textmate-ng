/*
This class controls a stack of _stackSize_ objects, which will be stored in the app’s defaults with _name_.

If an object that is already in the list is added, it will be moved to the top of the list instead.
If the list grows beyond _stackSize_ objects, the last object will be removed before the new item is added.

Hand-written declaration of the Swift OakHistoryList (OakHistoryList.swift), for
the Swift consumers in Find and DocumentWindow, which see this framework only
through its headers (rule 23), and for t_history_list.mm, which pins the
contract (rule 18). Kept out of the bridging header: Swift defines the class
(rule 43). The generic parameter is a declaration-side convenience the runtime
never sees, which is why a Swift implementation can stand behind it.
*/

@interface OakHistoryList<ObjectType> : NSObject
@property (nonatomic, readonly) NSUInteger stackSize;
@property (nonatomic) ObjectType head;

- (id)initWithName:(NSString*)defaultsName stackSize:(NSUInteger)size;
- (id)initWithName:(NSString*)defaultsName stackSize:(NSUInteger)size fallbackUserDefaultsKey:(NSString*)fallbackDefaultsName;

// Once the array spelling of a nil-terminated variadic; now the only spelling. A
// C variadic ObjC method cannot be called from Swift or written in it, and
// nothing had called the variadic since this one was added.
- (id)initWithName:(NSString*)defaultsName stackSize:(NSUInteger)size defaultItemsArray:(NSArray*)items;
- (void)addObject:(ObjectType)newItem;
- (NSEnumerator<ObjectType>*)objectEnumerator;
- (ObjectType)objectAtIndex:(NSUInteger)index;
- (NSUInteger)count;
@end
