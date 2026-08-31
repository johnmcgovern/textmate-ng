#import "Favorites.h"
#import "FavoritesSupport.h"
#import <OakFilterList/OakAbbreviations.h>
#import <OakFilterList/OakChooserMarkup.h>
#import <OakFilterList/OakFileTableCellView.h>
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakAppKit/OakScopeBarView.h>
#import <OakAppKit/OakSound.h>
#import <OakFoundation/NSString Additions.h>
#import <OakSystem/application.h>
#import <text/ranker.h>
#import <io/entries.h>
#import <text/case.h>
#import <text/ctype.h>
#import <io/path.h>
#import <ns/ns.h>
#import <kvdb/kvdb.h>

static NSString* const kUserDefaultsOpenProjectSourceIndex = @"openProjectSourceIndex";

static NSUInteger const kOakSourceIndexRecentProjects = 0;
static NSUInteger const kOakSourceIndexFavorites      = 1;


@interface FavoriteChooser ()
{
	NSArray<FavoritesItem*>* _originalItems;
}
@property (nonatomic) OakScopeBarViewController* scopeBar;
@property (nonatomic) NSUInteger sourceIndex;
@property (nonatomic) NSArray* sourceListLabels;
@end

@implementation FavoriteChooser
+ (instancetype)sharedInstance
{
	static FavoriteChooser* sharedInstance = [self new];
	return sharedInstance;
}

+ (void)initialize
{
	[NSUserDefaults.standardUserDefaults registerDefaults:@{
		kUserDefaultsOpenProjectSourceIndex: @0,
	}];
}

- (KVDB*)sharedProjectStateDB
{
	NSString* appSupport = [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"TextMate"];
	return [KVDB sharedDBUsingFile:@"RecentProjects.db" inDirectory:appSupport];
}

- (id)init
{
	if((self = [super init]))
	{
		_sourceIndex      = NSNotFound;
		_sourceListLabels = @[ @"Recent Projects", @"Favorites" ];

		self.window.title = @"Open Recent Project";
		self.tableView.allowsTypeSelect = NO;
		self.tableView.allowsMultipleSelection = YES;
		self.tableView.refusesFirstResponder = NO;
		self.tableView.rowHeight = 38;

		_scopeBar = [[OakScopeBarViewController alloc] init];
		_scopeBar.labels = self.sourceListLabels;

		NSDictionary* titlebarViews = @{
			@"searchField": self.searchField,
			@"dividerView": OakCreateNSBoxSeparator(),
			@"scopeBar":    _scopeBar.view,
		};

		NSView* titlebarView = [[NSView alloc] initWithFrame:NSZeroRect];
		OakAddAutoLayoutViewsToSuperview(titlebarViews.allValues, titlebarView);

		[titlebarView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(8)-[searchField]-(8)-|" options:0 metrics:nil views:titlebarViews]];
		[titlebarView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[dividerView]|" options:0 metrics:nil views:titlebarViews]];
		[titlebarView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(8)-[scopeBar]-(>=8)-|" options:0 metrics:nil views:titlebarViews]];

		[titlebarView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(4)-[searchField]-(8)-[dividerView(==1)]-(4)-[scopeBar]-(4)-|" options:0 metrics:nil views:titlebarViews]];
		[self addTitlebarAccessoryView:titlebarView];

		NSDictionary* footerViews = @{
			@"dividerView":        OakCreateNSBoxSeparator(),
			@"statusTextField":    self.statusTextField,
			@"itemCountTextField": self.itemCountTextField,
		};

		NSView* footerView = self.footerView;
		OakAddAutoLayoutViewsToSuperview(footerViews.allValues, footerView);

		[footerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[dividerView]|"                                 options:0 metrics:nil views:footerViews]];
		[footerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[statusTextField]-[itemCountTextField]-|"      options:NSLayoutFormatAlignAllCenterY metrics:nil views:footerViews]];
		[footerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[dividerView(==1)]-(4)-[statusTextField]-(5)-|" options:0 metrics:nil views:footerViews]];

		[self updateScrollViewInsets];

		OakSetupKeyViewLoop(@[ self.tableView, self.searchField, _scopeBar.view ]);
		self.window.initialFirstResponder = self.tableView;

		self.sourceIndex = [NSUserDefaults.standardUserDefaults integerForKey:kUserDefaultsOpenProjectSourceIndex];
		[_scopeBar bind:NSValueBinding toObject:self withKeyPath:@"sourceIndex" options:nil];
	}
	return self;
}

- (IBAction)selectNextTab:(id)sender     { [_scopeBar selectNextButton:sender]; }
- (IBAction)selectPreviousTab:(id)sender { [_scopeBar selectPreviousButton:sender]; }
- (void)updateShowTabMenu:(NSMenu*)aMenu { [_scopeBar updateGoToMenu:aMenu]; }

- (NSView*)tableView:(NSTableView*)aTableView viewForTableColumn:(NSTableColumn*)aTableColumn row:(NSInteger)row
{
	NSTableCellView* res = [aTableView makeViewWithIdentifier:aTableColumn.identifier owner:self];
	if(!res)
	{
		NSImage* removeTemplateImage = [NSImage imageWithSize:NSMakeSize(8, 8) flipped:NO drawingHandler:^BOOL(NSRect dstRect){
			[[NSColor blackColor] set];
			NSRectFill(NSInsetRect(dstRect, 0, floor(NSHeight(dstRect)/2)-1));
			return YES;
		}];
		[removeTemplateImage setTemplate:YES];

		NSButton* removeButton = [NSButton new];
		removeButton.controlSize = NSControlSizeSmall;
		removeButton.refusesFirstResponder = YES;
		removeButton.bezelStyle = NSBezelStyleRoundRect;
		removeButton.buttonType = NSButtonTypeMomentaryPushIn;
		removeButton.image      = removeTemplateImage;
		removeButton.target     = self;
		removeButton.action     = @selector(takeItemToRemoveFrom:);

		res = [[OakFileTableCellView alloc] initWithCloseButton:removeButton];
		res.identifier = aTableColumn.identifier;

		[removeButton bind:NSHiddenBinding toObject:res withKeyPath:@"objectValue.isRemovable" options:@{ NSValueTransformerNameBindingOption: NSNegateBooleanTransformerName }];
	}

	res.objectValue = self.items[row];
	return res;
}

- (void)setSourceIndex:(NSUInteger)newIndex
{
	if(_sourceIndex == newIndex)
		return;

	_sourceIndex = newIndex;
	[self loadItems:self];
	[self updateItems:self];
	[NSUserDefaults.standardUserDefaults setInteger:newIndex forKey:kUserDefaultsOpenProjectSourceIndex];
}

- (void)loadItems:(id)sender
{
	NSMutableArray<FavoritesItem*>* items = [NSMutableArray array];
	if(_sourceIndex == kOakSourceIndexRecentProjects)
	{
		for(id pair in [[[self sharedProjectStateDB] allObjects] sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"value.lastRecentlyUsed" ascending:NO], [NSSortDescriptor sortDescriptorWithKey:@"key.lastPathComponent" ascending:YES selector:@selector(localizedCompare:)] ]])
		{
			if(access([pair[@"key"] fileSystemRepresentation], F_OK) == 0)
				[items addObject:[[FavoritesItem alloc] initWithPath:pair[@"key"] isLink:NO isRemovable:YES]];
		}
	}
	else if(_sourceIndex == kOakSourceIndexFavorites)
	{
		[items addObjectsFromArray:[FavoritesSupport favoritesFolderItems]];
	}

	// Already sorted by display name when it came from the Favorites folder — see
	// +favoritesFolderItems, which does that as part of the walk.
	_originalItems = items;
}

- (void)showWindow:(id)sender
{
	if(![self.window isVisible])
	{
		self.filterString = @"";
		[self loadItems:self];
		[self updateItems:self];
		if([self.tableView numberOfRows])
			[self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	}
	[super showWindow:sender];
}

- (void)updateItems:(id)sender
{
	NSArray* bindings = [[OakAbbreviations abbreviationsForName:@"OakFavoriteChooserBindings"] stringsForAbbreviation:self.filterString];
	self.items = [FavoritesSupport rankItems:_originalItems filterString:self.filterString bindings:bindings];
}

- (void)updateStatusText:(id)sender
{
	if(self.tableView.selectedRow != -1)
	{
		FavoritesItem* item = self.items[self.tableView.selectedRow];
		self.statusTextField.stringValue = item.path.stringByAbbreviatingWithTildeInPath;
	}
	else
	{
		self.statusTextField.stringValue = @"";
	}
}

- (void)accept:(id)sender
{
	if(self.filterString)
	{
		for(FavoritesItem* item in self.selectedItems)
			[[OakAbbreviations abbreviationsForName:@"OakFavoriteChooserBindings"] learnAbbreviation:self.filterString forString:item.path];
	}

	for(FavoritesItem* item in self.selectedItems)
	{
		if(NSMutableDictionary* tmp = [[[self sharedProjectStateDB] valueForKey:item.path] mutableCopy])
		{
			tmp[@"lastRecentlyUsed"] = [NSDate date];
			[[self sharedProjectStateDB] setValue:tmp forKey:item.path];
		}
	}

	[super accept:sender];
}

- (NSUInteger)removeItemsAtIndexes:(NSIndexSet*)anIndexSet
{
	NSMutableArray<FavoritesItem*>* items = [self.items mutableCopy];
	anIndexSet = [anIndexSet indexesPassingTest:^BOOL(NSUInteger idx, BOOL* stop){
		return items[idx].isRemovable;
	}];

	for(FavoritesItem* item in [items objectsAtIndexes:anIndexSet])
	{
		if(NSString* link = item.link)
			[NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:item.link] resultingItemURL:nil error:nil];
		else if(NSString* path = item.path)
			[[self sharedProjectStateDB] removeObjectForKey:path];
	}

	[self loadItems:self]; // update originalItems
	return [super removeItemsAtIndexes:anIndexSet];
}

- (void)takeItemToRemoveFrom:(NSButton*)sender
{
	NSInteger row = [self.tableView rowForView:sender];
	if(row != -1)
		[self removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:row]];
}

- (void)deleteForward:(id)sender
{
	NSUInteger itemsRemoved = [self removeItemsAtIndexes:[self.tableView selectedRowIndexes]];
	if(itemsRemoved == 0)
		NSBeep();
}

- (void)deleteBackward:(id)sender
{
	NSUInteger index = [[self.tableView selectedRowIndexes] firstIndex];
	NSUInteger itemsRemoved = [self removeItemsAtIndexes:[self.tableView selectedRowIndexes]];
	if(itemsRemoved == 0)
		NSBeep();
	else if(index && index != NSNotFound && self.tableView.numberOfRows)
		[self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index-1] byExtendingSelection:NO];
}

- (void)insertText:(id)aString
{
	self.filterString = aString;
	[self.window makeFirstResponder:self.searchField];
	NSText* fieldEditor = (NSText*)[self.window firstResponder];
	if([fieldEditor isKindOfClass:[NSText class]])
		[fieldEditor setSelectedRange:NSMakeRange([[fieldEditor string] length], 0)];
}

- (void)doCommandBySelector:(SEL)aSelector
{
	if([self respondsToSelector:aSelector])
	{
		[super doCommandBySelector:aSelector];
	}
	else
	{
		NSUInteger res = OakPerformTableViewActionFromSelector(self.tableView, aSelector);
		if(res == OakMoveAcceptReturn)
			[self accept:self];
		else if(res == OakMoveCancelReturn)
			[self cancel:self];
	}
}

- (void)keyDown:(NSEvent*)anEvent  { [self interpretKeyEvents:@[ anEvent ]]; }
- (void)insertTab:(id)sender       { [self.window selectNextKeyView:self]; }
- (void)insertBacktab:(id)sender   { [self.window selectPreviousKeyView:self]; }
@end
