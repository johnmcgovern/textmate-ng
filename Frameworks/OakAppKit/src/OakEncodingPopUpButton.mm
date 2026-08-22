#import "OakEncodingPopUpButton.h"
#import "OakEncodingSupport.h"
#import <OakFoundation/OakFoundation.h>

// What is left after the C++ moved to OakEncodingSupport: two NSPopUpButton
// subclasses' worth of AppKit, and no std::, path::, plist:: or text:: at all.
//
// The one structural change is that +initialize is gone. Swift cannot define it,
// so the work it did now lives in +[OakEncodingSupport registerDefaultEncodings]
// and every initialiser calls it before reading the enabled list. That call is
// not optional bookkeeping — it is what puts the eight defaults in the
// registration domain, and -updateAvailableEncodings reads them on the next line.

static NSMenuItem* PopulateMenuFlat (NSMenu* menu, NSArray<OakCharset*>* items, id target, SEL action, NSString* selected)
{
	NSMenuItem* res = nil;
	for(OakCharset* item in items)
	{
		NSMenuItem* menuItem = [menu addItemWithTitle:[NSString stringWithFormat:@"%@ – %@", item.group, item.title] action:action keyEquivalent:@""];
		[menuItem setRepresentedObject:item.code];
		[menuItem setTarget:target];

		if([item.code isEqualToString:selected])
			res = menuItem;
	}
	return res;
}

static void PopulateMenuHierarchical (NSMenu* containingMenu, NSArray<OakCharset*>* items, id target, SEL action, NSString* selected)
{
	NSString* groupName = nil;
	NSMenu* menu = nil;
	for(OakCharset* item in items)
	{
		// A new submenu per *contiguous run* of a group, as before: the charset
		// list is already grouped, and a group that reappeared later would get a
		// second submenu rather than joining the first.
		if(![groupName isEqualToString:item.group])
		{
			groupName = item.group;

			menu = [NSMenu new];
			[menu setAutoenablesItems:NO];
			[[containingMenu addItemWithTitle:groupName action:NULL keyEquivalent:@""] setSubmenu:menu];
		}

		NSMenuItem* menuItem = [menu addItemWithTitle:item.title action:action keyEquivalent:@""];
		[menuItem setRepresentedObject:item.code];
		[menuItem setTarget:target];
		if([selected isEqualToString:item.code])
			[menuItem setState:NSControlStateValueOn];
	}
}

@interface OakCustomizeEncodingsWindowController : NSWindowController
{
	NSMutableArray* encodings;
}
@property (class, readonly) OakCustomizeEncodingsWindowController* sharedInstance;
@end

@interface OakEncodingPopUpButton () <OakUserDefaultsObserver>
@property (nonatomic) NSArray*    availableEncodings;
@property (nonatomic) NSMenuItem* firstMenuItem;
@end

@implementation OakEncodingPopUpButton
- (void)updateAvailableEncodings
{
	NSMutableArray* encodings = [NSMutableArray array];
	for(NSString* str in [NSUserDefaults.standardUserDefaults stringArrayForKey:OakEncodingSupport.availableEncodingsKey])
		[encodings addObject:str];

	if(self.encoding && ![encodings containsObject:self.encoding])
		[encodings addObject:self.encoding];

	self.availableEncodings = encodings;
}

- (void)updateMenu
{
	NSString* currentEncodingsTitle = self.encoding;

	NSMutableArray<OakCharset*>* items = [NSMutableArray array];
	for(OakCharset* charset in OakEncodingSupport.charsets)
	{
		if([self.availableEncodings containsObject:charset.code])
		{
			// charset.group is nil unless the name split into exactly two parts,
			// which is the filter the C++ applied via text::split's result size.
			if(charset.group)
			{
				[items addObject:charset];
				if([self.encoding isEqualToString:charset.code])
					currentEncodingsTitle = charset.name;
			}
		}
	}

	[self.menu removeAllItems];
	self.firstMenuItem = nil;

	if(items.count < 10)
	{
		if(NSMenuItem* currentItem = PopulateMenuFlat(self.menu, items, self, @selector(selectEncoding:), self.encoding))
			[self selectItem:currentItem];
	}
	else
	{
		if(currentEncodingsTitle)
		{
			self.firstMenuItem = [self.menu addItemWithTitle:currentEncodingsTitle action:NULL keyEquivalent:@""];
			[self.menu addItem:[NSMenuItem separatorItem]];
			[self selectItem:self.firstMenuItem];
		}
		PopulateMenuHierarchical(self.menu, items, self, @selector(selectEncoding:), self.encoding);
	}

	[self.menu addItem:[NSMenuItem separatorItem]];
	[[self.menu addItemWithTitle:@"Customize List…" action:@selector(customizeAvailableEncodings:) keyEquivalent:@""] setTarget:self];
}

- (id)initWithCoder:(NSCoder*)aCoder
{
	if(self = [super initWithCoder:aCoder])
	{
		[OakEncodingSupport registerDefaultEncodings];
		self.encoding = @"UTF-8";
		[self updateAvailableEncodings];
		[self updateMenu];
		OakObserveUserDefaults(self);
	}
	return self;
}

- (id)initWithFrame:(NSRect)aRect pullsDown:(BOOL)flag
{
	if(self = [super initWithFrame:aRect pullsDown:flag])
	{
		[OakEncodingSupport registerDefaultEncodings];
		self.encoding = @"UTF-8";
		[self updateAvailableEncodings];
		[self updateMenu];
		OakObserveUserDefaults(self);
	}
	return self;
}

- (id)init
{
	if(self = [self initWithFrame:NSZeroRect pullsDown:NO])
	{
		[self sizeToFit];
		if(NSWidth([self frame]) > 200)
			[self setFrameSize:NSMakeSize(200, NSHeight([self frame]))];
	}
	return self;
}

- (void)dealloc
{
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)selectEncoding:(NSMenuItem*)sender
{
	self.encoding = [sender representedObject];
}

- (void)setEncoding:(NSString*)newEncoding
{
	if(_encoding == newEncoding || [_encoding isEqualToString:newEncoding])
		return;

	_encoding = newEncoding;
	if(_encoding && ![self.availableEncodings containsObject:_encoding])
		[self updateAvailableEncodings];
	[self updateMenu];

	if(NSDictionary* info = [self infoForBinding:@"encoding"])
	{
		id controller     = info[NSObservedObjectKey];
		NSString* keyPath = info[NSObservedKeyPathKey];
		if(controller && controller != [NSNull null] && keyPath && (id)keyPath != [NSNull null])
		{
			NSString* newValue = _encoding;

			NSString* oldValue = [controller valueForKeyPath:keyPath];
			if(!oldValue || ![oldValue isEqualToString:newValue])
				[controller setValue:newValue forKeyPath:keyPath];
		}
	}
}

- (void)setAvailableEncodings:(NSArray*)newEncodings
{
	if(_availableEncodings == newEncodings || [_availableEncodings isEqualToArray:newEncodings])
		return;

	_availableEncodings = newEncodings;
	[self updateMenu];
}

- (void)customizeAvailableEncodings:(id)sender
{
	[OakCustomizeEncodingsWindowController.sharedInstance showWindow:self];
	[self updateMenu];
}

- (void)userDefaultsDidChange:(NSNotification*)aNotification
{
	[self updateAvailableEncodings];
}
@end

// =========================================
// = Customize Encodings Window Controller =
// =========================================

@implementation OakCustomizeEncodingsWindowController
+ (instancetype)sharedInstance
{
	static OakCustomizeEncodingsWindowController* sharedInstance = [self new];
	return sharedInstance;
}

- (id)init
{
	if(self = [super initWithWindowNibName:@"CustomizeEncodings"])
	{
		[OakEncodingSupport registerDefaultEncodings];

		NSSet* enabledEncodings = [NSSet setWithArray:[NSUserDefaults.standardUserDefaults stringArrayForKey:OakEncodingSupport.availableEncodingsKey] ?: @[]];

		encodings = [NSMutableArray new];
		// Every charset, including the ones whose name does not split — the
		// customize list is not filtered the way the menu is.
		for(OakCharset* charset in OakEncodingSupport.charsets)
		{
			id item = [NSMutableDictionary dictionaryWithObjectsAndKeys:
				@([enabledEncodings containsObject:charset.code]), @"enabled",
				charset.name, @"name",
				charset.code, @"charset",
				nil];
			[encodings addObject:item];
		}
	}
	return self;
}

// ========================
// = NSTableView Delegate =
// ========================

- (BOOL)tableView:(NSTableView*)aTableView shouldEditTableColumn:(NSTableColumn*)aTableColumn row:(NSInteger)rowIndex
{
	return [[aTableColumn identifier] isEqualToString:@"enabled"];
}

// ==========================
// = NSTableView DataSource =
// ==========================

- (NSInteger)numberOfRowsInTableView:(NSTableView*)aTableView
{
	return [encodings count];
}

- (id)tableView:(NSTableView*)aTableView objectValueForTableColumn:(NSTableColumn*)aTableColumn row:(NSInteger)rowIndex
{
	return [[encodings objectAtIndex:rowIndex] objectForKey:[aTableColumn identifier]];
}

- (void)tableView:(NSTableView*)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn*)aTableColumn row:(NSInteger)rowIndex
{
	[[encodings objectAtIndex:rowIndex] setObject:anObject forKey:[aTableColumn identifier]];

	NSMutableArray* newEncodings = [NSMutableArray array];
	for(NSDictionary* encoding in encodings)
	{
		if([[encoding objectForKey:@"enabled"] boolValue])
			[newEncodings addObject:[encoding objectForKey:@"charset"]];
	}

	[NSUserDefaults.standardUserDefaults setObject:newEncodings forKey:OakEncodingSupport.availableEncodingsKey];
}
@end
