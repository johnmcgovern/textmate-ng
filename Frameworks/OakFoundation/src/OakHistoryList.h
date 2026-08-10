/*
This class controls a stack of _stackSize_ objects, which will be stored in the app’s defaults with _name_.

If an object that is already in the list is added, it will be moved to the top of the list instead.
If the list grows beyond _stackSize_ objects, the last object will be removed before the new item is added.
*/

@interface OakHistoryList<ObjectType> : NSObject
@property (nonatomic, readonly) NSUInteger stackSize;
@property (nonatomic) ObjectType head;

- (id)initWithName:(NSString*)defaultsName stackSize:(NSUInteger)size;
- (id)initWithName:(NSString*)defaultsName stackSize:(NSUInteger)size fallbackUserDefaultsKey:(NSString*)fallbackDefaultsName;
- (id)initWithName:(NSString*)defaultsName stackSize:(NSUInteger)size defaultItems:(id)firstItem, ...;

// The array spelling of the nil-terminated variadic above, for Swift callers: a
// C variadic ObjC method is not merely awkward from Swift, it is uncallable. The
// variadic one funnels into this, so there is one implementation rather than two.
- (id)initWithName:(NSString*)defaultsName stackSize:(NSUInteger)size defaultItemsArray:(NSArray*)items;
- (void)addObject:(ObjectType)newItem;
- (NSEnumerator<ObjectType>*)objectEnumerator;
- (ObjectType)objectAtIndex:(NSUInteger)index;
- (NSUInteger)count;
@end
