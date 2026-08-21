#import "SymbolChooser.h"
#import "SymbolChooserSupport.h"
#import <OakAppKit/OakUIConstructionFunctions.h>

@implementation SymbolChooser
+ (instancetype)sharedInstance
{
	static SymbolChooser* sharedInstance = [self new];
	return sharedInstance;
}

- (id)init
{
	if((self = [super init]))
	{
		self.window.title = @"Jump to Symbol";

		NSDictionary* titlebarViews = @{
			@"searchField": self.searchField,
		};

		NSView* titlebarView = [[NSView alloc] initWithFrame:NSZeroRect];
		OakAddAutoLayoutViewsToSuperview(titlebarViews.allValues, titlebarView);

		[titlebarView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(8)-[searchField]-(8)-|" options:0 metrics:nil views:titlebarViews]];
		[titlebarView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(4)-[searchField]-(8)-|" options:0 metrics:nil views:titlebarViews]];
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

		self.window.initialFirstResponder = self.searchField;
	}
	return self;
}

- (void)windowWillClose:(NSNotification*)aNotification
{
	[self setTMDocument:nil];
}

- (void)setTMDocument:(OakDocument*)aDocument
{
	if(_TMDocument = aDocument)
		[self updateItems:self];
	NSString* title = @"Jump to Symbol";
	self.window.title = _TMDocument ? [title stringByAppendingFormat:@" — %@", _TMDocument.displayName] : title;
}

- (void)setSelectionString:(NSString*)aString
{
	_selectionString = aString;

	NSUInteger row = [SymbolChooserSupport indexOfItemForSelectionString:_selectionString inItems:self.items];
	if(row != NSNotFound)
	{
		[self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
		[self.tableView scrollRowToVisible:row];
	}
}

- (void)updateItems:(id)sender
{
	self.items = [SymbolChooserSupport itemsForDocument:_TMDocument filterString:self.filterString];
}

- (void)updateStatusText:(id)sender
{
	if(self.items.count != 0)
	{
		SymbolChooserItem* item = self.items[self.tableView.selectedRow == -1 ? 0 : self.tableView.selectedRow];
		self.statusTextField.stringValue = item.infoString;
	}
	else
	{
		self.statusTextField.stringValue = @"";
	}
}
@end
