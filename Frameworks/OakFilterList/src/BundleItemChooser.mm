#import "BundleItemChooser.h"
#import "BundleItemChooserSupport.h"
#import <TMBundleModel/TMBundleModelCxx.h>
#import "OakChooserMarkup.h"
#import "OakAbbreviations.h"
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakAppKit/OakKeyEquivalentView.h>
#import <OakAppKit/OakScopeBarView.h>
#import <OakAppKit/NSColor Additions.h>
#import <OakAppKit/NSImage Additions.h>
#import <OakFoundation/OakFoundation.h>
#import <OakFoundation/NSString Additions.h>
#import <OakSystem/application.h>
#import <TMFileReference/TMFileReference.h>
#import <bundles/bundles.h>
#import <settings/settings.h>
#import <text/ranker.h>
#import <text/case.h>
#import <text/ctype.h>
#import <regexp/format_string.h>
#import <ns/ns.h>



// ==============

static void* kRecordingObserverContext = &kRecordingObserverContext;



@interface BundleItemTableCellView : NSTableCellView
@property (nonatomic) NSTextField* contextTextField;
@property (nonatomic) NSTextField* shortcutTextField;
@end

@implementation BundleItemTableCellView
- (id)init
{
	if((self = [super init]))
	{
		NSImageView* imageView = [NSImageView new];
		[imageView setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
		[imageView setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

		NSTextField* textField = OakCreateLabel(@"", [NSFont systemFontOfSize:13]);
		NSTextField* contextTextField = OakCreateLabel(@"", [NSFont controlContentFontOfSize:10]);

		NSTextField* shortcutTextField = OakCreateLabel(@"", [NSFont controlContentFontOfSize:13]);
		[shortcutTextField setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
		[shortcutTextField setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

		NSDictionary* views = @{ @"icon": imageView, @"name": textField, @"context": contextTextField, @"shortcut": shortcutTextField };
		OakAddAutoLayoutViewsToSuperview([views allValues], self);

		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(4)-[icon]-(4)-[name]-(4)-[shortcut]-(8)-|" options:0 metrics:nil views:views]];
		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[context]-(8)-|" options:0 metrics:nil views:views]];
		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[name]-(2)-[context]-(5)-|" options:NSLayoutFormatAlignAllLeading metrics:nil views:views]];

		[imageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
		[shortcutTextField.firstBaselineAnchor constraintEqualToAnchor:textField.firstBaselineAnchor].active = YES;

		self.imageView         = imageView;
		self.textField         = textField;
		self.contextTextField  = contextTextField;
		self.shortcutTextField = shortcutTextField;
	}
	return self;
}

- (void)setObjectValue:(ActionItem*)item
{
	[super setObjectValue:item];

	NSImage* image = [BundleItemChooserSupport iconForItem:item];

	self.imageView.image              = image;
	self.textField.objectValue        = item.name;
	self.contextTextField.objectValue = item.path;

	id str = @"";
	if(NSString* keyEquivalent = item.keyEquivalent)
	{
		self.shortcutTextField.font = [NSFont controlContentFontOfSize:0];
		str = OakAttributedStringForEventString(keyEquivalent, self.shortcutTextField.font);
	}
	else if(NSString* tabTrigger = item.tabTrigger)
	{
		self.shortcutTextField.font = [NSFont controlContentFontOfSize:10];
		str = [tabTrigger stringByAppendingString:@"⇥"];
	}
	self.shortcutTextField.objectValue = str;
}

// FIXME Copy/paste from OakChooser.mm (OakFileTableCellView)
- (NSAttributedString*)selectedStringForString:(id)aString
{
	NSMutableAttributedString* str = [aString isKindOfClass:[NSString class]] ? [[NSMutableAttributedString alloc] initWithString:aString attributes:nil] : [aString mutableCopy];
	[str enumerateAttributesInRange:NSMakeRange(0, str.length) options:NSAttributedStringEnumerationLongestEffectiveRangeNotRequired usingBlock:^(NSDictionary* attrs, NSRange range, BOOL *stop){
		if(attrs[NSBackgroundColorAttributeName] != nil)
			[str addAttribute:NSBackgroundColorAttributeName value:[NSColor tmMatchedTextSelectedBackgroundColor] range:range];
		if(attrs[NSUnderlineColorAttributeName] != nil)
			[str addAttribute:NSUnderlineColorAttributeName value:[NSColor tmMatchedTextSelectedUnderlineColor] range:range];
	}];
	return str;
}

// FIXME Copy/paste from OakChooser.mm (OakFileTableCellView)
- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
	[super setBackgroundStyle:backgroundStyle];
	if(backgroundStyle == NSBackgroundStyleDark)
	{
		self.textField.objectValue        = [self selectedStringForString:[self valueForKeyPath:@"objectValue.name"]];
		self.contextTextField.textColor   = [NSColor colorWithCalibratedWhite:0.9 alpha:1];
		self.contextTextField.objectValue = [self selectedStringForString:[self valueForKeyPath:@"objectValue.path"]];
	}
	else
	{
		self.textField.objectValue        = [self valueForKeyPath:@"objectValue.name"];
		self.contextTextField.textColor   = [NSColor colorWithCalibratedWhite:0.5 alpha:1];
		self.contextTextField.objectValue = [self valueForKeyPath:@"objectValue.path"];
	}
}

- (id)accessibilityAttributeValue:(NSString*)attribute
{
	if([attribute isEqualToString:NSAccessibilityChildrenAttribute])
			return @[ self.textField.cell, self.imageView.cell, self.contextTextField.cell, self.shortcutTextField.cell ];
	else	return [super accessibilityAttributeValue:attribute];
}
@end

@interface BundleItemChooser () <NSToolbarDelegate>
{
	NSArray<ActionItem*>* _unfilteredItems;
}
@property (nonatomic) NSView* titlebarView;
@property (nonatomic) OakKeyEquivalentView* keyEquivalentView;
@property (nonatomic) NSPopUpButton* actionsPopUpButton;
@property (nonatomic) OakScopeBarViewController* scopeBar;
@property (nonatomic) NSView* topDivider;
@property (nonatomic) NSView* bottomDivider;
@property (nonatomic) NSButton* selectButton;
@property (nonatomic) NSButton* editButton;
@property (nonatomic) NSArray* layoutConstraints;
@property (nonatomic) NSArray* sourceListLabels;

@property (nonatomic) NSUInteger sourceIndex;
@property (nonatomic) NSUInteger searchSource;
@property (nonatomic) NSUInteger bundleItemField;

@property (nonatomic) NSString* keyEquivalentString;
@property (nonatomic) BOOL keyEquivalentInput;
@property (nonatomic) BOOL searchAllScopes;
@property (nonatomic) id eventMonitor;
@end

@implementation BundleItemChooser
+ (instancetype)sharedInstance
{
	static BundleItemChooser* sharedInstance = [self new];
	return sharedInstance;
}

- (id)init
{
	if((self = [super init]))
	{
		self.tableView.rowHeight = 38;

		_sourceListLabels = @[ @"Actions", @"Settings", @"Other" ];
		_bundleItemField  = kBundleItemTitleField;
		_searchSource     = kSearchSourceActionItems|kSearchSourceMenuItems|kSearchSourceKeyBindingItems;

		self.window.title = @"Select Bundle Item";

		self.actionsPopUpButton = OakCreateActionPopUpButton(YES /* bordered */);
		NSMenu* actionMenu = self.actionsPopUpButton.menu;
		[actionMenu addItemWithTitle:@"Placeholder" action:NULL keyEquivalent:@""];

		struct { NSString* title; NSUInteger tag; } const fields[] =
		{
			{ @"Title",          kBundleItemTitleField         },
			{ @"Key Equivalent", kBundleItemKeyEquivalentField },
			{ @"Tab Trigger",    kBundleItemTabTriggerField    },
			{ @"Semantic Class", kBundleItemSemanticClassField },
			{ @"Scope Selector", kBundleItemScopeSelectorField },
		};

		char key = 0;

		[actionMenu addItemWithTitle:@"Search" action:@selector(nop:) keyEquivalent:@""];
		for(auto&& info : fields)
		{
			NSMenuItem* item = [actionMenu addItemWithTitle:info.title action:@selector(takeBundleItemFieldFrom:) keyEquivalent:key < 2 ? [NSString stringWithFormat:@"%c", '0' + (++key % 10)] : @""];
			[item setIndentationLevel:1];
			[item setTag:info.tag];
		}

		[actionMenu addItem:[NSMenuItem separatorItem]];
		[actionMenu addItemWithTitle:@"Search All Scopes" action:@selector(toggleSearchAllScopes:) keyEquivalent:key < 9 ? [NSString stringWithFormat:@"%c", '0' + (++key % 10)] : @""];

		self.scopeBar = [[OakScopeBarViewController alloc] init];
		self.scopeBar.labels = _sourceListLabels;

		self.topDivider          = OakCreateNSBoxSeparator();
		self.bottomDivider       = OakCreateNSBoxSeparator();

		self.selectButton             = OakCreateButton(@"Select");
		self.selectButton.font        = [NSFont messageFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]];
		self.selectButton.controlSize = NSControlSizeSmall;
		self.selectButton.target      = self;
		self.selectButton.action      = @selector(accept:);

		self.editButton             = OakCreateButton(@"Edit");
		self.editButton.font        = [NSFont messageFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]];
		self.editButton.controlSize = NSControlSizeSmall;
		self.editButton.target      = self;
		self.editButton.action      = @selector(editItem:);

		NSDictionary* titlebarViews = @{
			@"searchField": self.keyEquivalentInput ? self.keyEquivalentView : self.searchField,
			@"actions":     self.actionsPopUpButton,
			@"dividerView": self.topDivider,
			@"scopeBar":    self.scopeBar.view,
		};

		self.titlebarView = [[NSView alloc] initWithFrame:NSZeroRect];
		OakAddAutoLayoutViewsToSuperview(titlebarViews.allValues, self.titlebarView);
		[self setupLayoutConstraints];

		[self addTitlebarAccessoryView:self.titlebarView];

		NSDictionary* footerViews = @{
			@"dividerView": self.bottomDivider,
			@"status":      self.statusTextField,
			@"edit":        self.editButton,
			@"select":      self.selectButton,
		};

		NSView* footerView = self.footerView;
		OakAddAutoLayoutViewsToSuperview(footerViews.allValues, footerView);

		[footerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[dividerView]|"                         options:0 metrics:nil views:footerViews]];
		[footerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(24)-[status]-(>=0)-[edit]-[select]-|" options:NSLayoutFormatAlignAllCenterY metrics:nil views:footerViews]];
		[footerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[dividerView(==1)]-(4)-[select]-(5)-|"  options:0 metrics:nil views:footerViews]];

		[self updateScrollViewInsets];

		OakSetupKeyViewLoop(@[ self.searchField, self.actionsPopUpButton, self.scopeBar.view, self.editButton, self.selectButton ]);
		self.window.initialFirstResponder = self.searchField;

		[self.scopeBar bind:NSValueBinding toObject:self withKeyPath:@"sourceIndex" options:nil];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowDidChangeKeyStatus:) name:NSWindowDidBecomeKeyNotification object:self.window];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowDidChangeKeyStatus:) name:NSWindowDidResignKeyNotification object:self.window];
	}
	return self;
}

- (void)dealloc
{
	[NSNotificationCenter.defaultCenter removeObserver:self];
	[_keyEquivalentView removeObserver:self forKeyPath:@"recording" context:kRecordingObserverContext];
	[_scopeBar unbind:NSValueBinding];
}

- (void)windowDidChangeKeyStatus:(NSNotification*)aNotification
{
	auto updateDefaultButton = ^NSEvent*(NSEvent* event){
		BOOL isKeyWindow = NSApp.keyWindow == self.window;
		BOOL optionDown  = ([event modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask) == NSEventModifierFlagOption;
		self.window.defaultButtonCell = self.canEdit && (!self.canAccept || (optionDown && isKeyWindow)) ? self.editButton.cell : self.selectButton.cell;
		return event;
	};

	updateDefaultButton([NSApp currentEvent]);
	if(NSApp.keyWindow == self.window)
	{
		_eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskFlagsChanged handler:updateDefaultButton];
	}
	else if(_eventMonitor)
	{
		[NSEvent removeMonitor:_eventMonitor];
		_eventMonitor = nil;
	}
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
	if(context == kRecordingObserverContext)
	{
		NSNumber* isRecording = change[NSKeyValueChangeNewKey];
		self.drawTableViewAsHighlighted = !isRecording.boolValue;
	}
	else
	{
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];

		if(_keyEquivalentView && !_keyEquivalentView.recording && [keyPath isEqualToString:@"firstResponder"])
		{
			BOOL oldIsKeyEquivalentView = change[NSKeyValueChangeOldKey] == _keyEquivalentView;
			BOOL newIsKeyEquivalentView = change[NSKeyValueChangeNewKey] == _keyEquivalentView;
			if(oldIsKeyEquivalentView != newIsKeyEquivalentView)
				self.drawTableViewAsHighlighted = newIsKeyEquivalentView;
		}
	}
}

- (void)setupLayoutConstraints
{
	NSDictionary* titlebarViews = @{
		@"searchField": self.keyEquivalentInput ? self.keyEquivalentView : self.searchField,
		@"actions":     self.actionsPopUpButton,
		@"dividerView": self.topDivider,
		@"scopeBar":    self.scopeBar.view,
	};

	NSMutableArray* constraints = [NSMutableArray array];
	[constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(8)-[searchField(>=50)]-[actions]-(8)-|"                       options:NSLayoutFormatAlignAllCenterY metrics:nil views:titlebarViews]];
	[constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[dividerView]|"                                                 options:0 metrics:nil views:titlebarViews]];
	[constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(8)-[scopeBar]-(>=8)-|"                                        options:0 metrics:nil views:titlebarViews]];
	[constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(4)-[searchField]-(8)-[dividerView(==1)]-(4)-[scopeBar]-(4)-|" options:0 metrics:nil views:titlebarViews]];
	[self.titlebarView addConstraints:constraints];
	self.layoutConstraints = constraints;
}

- (void)showWindow:(id)sender
{
	self.bundleItemField = kBundleItemTitleField;
	if([self.tableView numberOfRows] > 0)
	{
		[self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
		[self.tableView scrollRowToVisible:0];
	}
	[super showWindow:sender];
}

- (void)windowWillClose:(NSNotification*)aNotification
{
	_unfilteredItems = nil;
	self.items = @[ ];
}

- (void)setSourceIndex:(NSUInteger)newSourceIndex
{
	switch(_sourceIndex = newSourceIndex)
	{
		case 0: self.searchSource = kSearchSourceActionItems|kSearchSourceMenuItems|kSearchSourceKeyBindingItems; break;
		case 1: self.searchSource = kSearchSourceSettingsItems;                                                   break;
		case 2: self.searchSource = kSearchSourceGrammarItems|kSearchSourceThemeItems;                            break;
	}
}

- (void)keyDown:(NSEvent*)anEvent
{
	NSUInteger res = OakPerformTableViewActionFromKeyEvent(self.tableView, anEvent);
	if(res == OakMoveAcceptReturn)
		[self performDefaultButtonClick:self];
	else if(res == OakMoveCancelReturn)
		[self cancel:self];
}

- (OakKeyEquivalentView*)keyEquivalentView
{
	if(!_keyEquivalentView)
	{
		_keyEquivalentView = [[OakKeyEquivalentView alloc] initWithFrame:NSZeroRect];
		[_keyEquivalentView setTranslatesAutoresizingMaskIntoConstraints:NO];
		[_keyEquivalentView bind:NSValueBinding toObject:self withKeyPath:@"keyEquivalentString" options:nil];
		[_keyEquivalentView addObserver:self forKeyPath:@"recording" options:NSKeyValueObservingOptionNew context:kRecordingObserverContext];
		_keyEquivalentView.accessibilitySharedFocusElements = @[ self.tableView ];
	}
	return _keyEquivalentView;
}

- (void)replaceView:(NSView*)oldView withView:(NSView*)newView
{
	NSView* next = oldView.nextKeyView;
	NSView* prev = oldView.previousKeyView;

	NSView* contentView = oldView.superview;
	[oldView removeFromSuperview];

	[contentView addSubview:newView];

	prev.nextKeyView = newView;
	newView.nextKeyView = next;

	newView.window.initialFirstResponder = newView;
	[newView.window makeFirstResponder:newView];
}

- (void)setKeyEquivalentInput:(BOOL)flag
{
	if(_keyEquivalentInput == flag)
		return;

	_keyEquivalentInput = flag;

	NSView* contentView = self.titlebarView;
	[contentView removeConstraints:self.layoutConstraints];
	self.layoutConstraints = nil;

	if(flag)
			[self replaceView:self.searchField withView:self.keyEquivalentView];
	else	[self replaceView:self.keyEquivalentView withView:self.searchField];

	[self setupLayoutConstraints];

	self.keyEquivalentView.eventString = nil;
	self.keyEquivalentView.recording   = self.keyEquivalentInput;

	[self updateItems:self];
}

- (void)toggleSearchAllScopes:(id)sender
{
	self.searchAllScopes = !self.searchAllScopes;
	_unfilteredItems = nil;
	[self updateItems:self];
}

- (void)setScope:(scope::context_t)aScope
{
	_scope = aScope;
	_unfilteredItems = nil;
	[self updateItems:self];
}

- (void)setHasSelection:(BOOL)flag
{
	if(_hasSelection != flag)
	{
		_hasSelection = flag;
		_unfilteredItems = nil;
		[self updateItems:self];
	}
}

- (void)setKeyEquivalentString:(NSString*)aString
{
	if([_keyEquivalentString isEqualToString:aString])
		return;

	_keyEquivalentString = aString;
	[self updateItems:self];
}

- (void)setBundleItemField:(NSUInteger)newBundleItemField
{
	if(_bundleItemField == newBundleItemField)
		return;

	_bundleItemField = newBundleItemField;
	self.keyEquivalentInput = _bundleItemField == kBundleItemKeyEquivalentField;
	self.filterString = nil;
	[self updateItems:self];
}

- (void)setSearchSource:(NSUInteger)newSearchSource
{
	if(_searchSource == newSearchSource)
		return;

	_searchSource = newSearchSource;
	_unfilteredItems = nil;
	[self updateItems:self];
}

- (void)takeBundleItemFieldFrom:(id)sender
{
	if([sender respondsToSelector:@selector(tag)])
		self.bundleItemField = [sender tag];
}

- (NSView*)tableView:(NSTableView*)aTableView viewForTableColumn:(NSTableColumn*)aTableColumn row:(NSInteger)row
{
	NSString* identifier = aTableColumn.identifier;
	NSTableCellView* res = [aTableView makeViewWithIdentifier:identifier owner:self];
	if(!res)
	{
		res = [BundleItemTableCellView new];
		res.identifier = identifier;
	}

	res.objectValue = self.items[row];
	return res;
}


// The gathering itself is in BundleItemChooserSupport; the cache stays here, because what
// invalidates it is this panel's own state — every `_unfilteredItems = nil` above.
- (NSArray<ActionItem*>*)unfilteredItems
{
	if(_unfilteredItems == nil)
		_unfilteredItems = [BundleItemChooserSupport unfilteredItemsForScope:[TMScopeContext scopeContextWithCxxContext:self.scope] hasSelection:self.hasSelection searchSource:self.searchSource searchAllScopes:self.searchAllScopes documentPath:self.path documentDirectory:self.directory];
	return _unfilteredItems;
}

- (void)updateItems:(id)sender
{
	NSArray<NSString*>* identifiers = [[OakAbbreviations abbreviationsForName:@"OakBundleItemChooserBindings"] stringsForAbbreviation:self.filterString];
	NSString* filter = self.keyEquivalentInput ? self.keyEquivalentString : self.filterString;

	self.items = [BundleItemChooserSupport rankedItems:[self unfilteredItems] filterString:filter bundleItemField:_bundleItemField searchSource:_searchSource bindings:identifiers];

	self.window.title = [NSString stringWithFormat:@"Select Bundle Item (%@)", self.itemCountTextField.stringValue];
}

- (void)updateStatusText:(id)sender
{
	NSString* status = nil;
	if(self.tableView.selectedRow != -1)
	{
		if(ActionItem* item = self.items[self.tableView.selectedRow])
			status = item.semanticClass ?: item.scopeSelector ?: NSStringFromSelector(item.action);
	}
	self.statusTextField.stringValue = status ?: @"";

	// Our super class will ask for updated status text each time selection changes
	// so we use this to update enabled state for action buttons
	// FIXME Since ‘canEdit’ depends on ‘editAction’ we must update ‘enabled’ when ‘editAction’ changes.
	self.selectButton.enabled     = self.canAccept;
	self.editButton.enabled       = self.canEdit;
	self.window.defaultButtonCell = !self.canAccept && self.canEdit ? self.editButton.cell : self.selectButton.cell;
	self.tableView.doubleAction   = !self.canAccept && self.canEdit ? @selector(editItem:) : @selector(accept:);
}

- (BOOL)validateMenuItem:(NSMenuItem*)aMenuItem
{
	if(aMenuItem.action == @selector(takeBundleItemFieldFrom:))
		aMenuItem.state = self.bundleItemField == aMenuItem.tag ? NSControlStateValueOn : NSControlStateValueOff;
	else if(aMenuItem.action == @selector(toggleSearchAllScopes:))
		aMenuItem.state = self.searchAllScopes ? NSControlStateValueOn : NSControlStateValueOff;

	return YES;
}

- (BOOL)canAccept
{
	ActionItem* item = self.tableView.selectedRow != -1 ? self.items[self.tableView.selectedRow] : nil;
	return [BundleItemChooserSupport canAcceptItem:item];
}

- (BOOL)canEdit
{
	ActionItem* item = self.tableView.selectedRow != -1 ? self.items[self.tableView.selectedRow] : nil;
	return item.uuid && self.editAction || item.file;
}

- (void)accept:(id)sender
{
	if(_bundleItemField == kBundleItemTitleField && OakNotEmptyString(self.filterString) && (self.tableView.selectedRow > 0 || [self.filterString length] > 1))
	{
		ActionItem* item = self.items[self.tableView.selectedRow];
		if(NSString* identifier = [BundleItemChooserSupport abbreviationIdentifierForItem:item])
			[[OakAbbreviations abbreviationsForName:@"OakBundleItemChooserBindings"] learnAbbreviation:self.filterString forString:identifier];
	}

	if(self.tableView.selectedRow != -1)
	{
		ActionItem* item = self.items[self.tableView.selectedRow];

		SEL action = NULL;
		id target = nil, sender = self;

		if(NSMenuItem* menuItem = item.menuItem)
		{
			target = menuItem.target;
			action = menuItem.action;
			sender = menuItem;
		}
		else
		{
			action = item.action;
		}

		if(action)
		{
			[self.window orderOut:self];
			[NSApp sendAction:action to:target from:sender];
			[self.window close];

			return;
		}
	}

	[super accept:sender];
}

- (IBAction)editItem:(id)sender
{
	if(![self canEdit])
		return NSBeep();

	[self.window orderOut:self];
	[NSApp sendAction:self.editAction to:self.target from:self];
	[self.window close];
}

- (IBAction)selectNextTab:(id)sender     { [_scopeBar selectNextButton:sender]; }
- (IBAction)selectPreviousTab:(id)sender { [_scopeBar selectPreviousButton:sender]; }
@end
