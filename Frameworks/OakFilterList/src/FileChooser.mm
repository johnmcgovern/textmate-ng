#import "FileChooser.h"
#import "OakChooserMarkup.h"
#import "OakFileTableCellView.h"
#import "FileChooserItem.h"
#import "FileChooserSupport.h"
#import "OakAbbreviations.h"
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakAppKit/OakScopeBarView.h>
#import <OakAppKit/NSImage Additions.h>
#import <OakFoundation/NSString Additions.h>
#import <OakFoundation/OakFoundation.h>
#import <document/OakDocument.h>
#import <document/OakDocumentController.h>

@interface NSObject (FileBrowserDelegate)
- (void)fileBrowser:(id)aFileBrowser closeURL:(NSURL*)anURL;
@end

static NSString* const kUserDefaultsFileChooserSourceIndexKey = @"fileChooserSourceIndex";

NSUInteger const kFileChooserAllSourceIndex                = 0;
NSUInteger const kFileChooserOpenDocumentsSourceIndex      = 1;
NSUInteger const kFileChooserUncommittedChangesSourceIndex = 2;

@interface FileChooser ()
{
	FileChooserSCMInfo*               _scmInfo;
	NSMutableArray<FileChooserItem*>* _records;

	FileChooserFilter* _filter;

	BOOL _searching;
	NSString* _searchPath;
	NSUInteger _lastSearchToken;
	NSMutableArray<OakDocument*>* _searchResults;
}
@property (nonatomic) OakScopeBarViewController* scopeBar;
@property (nonatomic) NSArray* sourceListLabels;
@property (nonatomic) NSProgressIndicator* progressIndicator;

@property (nonatomic) NSTimer* pollTimer;
@property (nonatomic) CGFloat  pollInterval;
@end

@implementation FileChooser
+ (instancetype)sharedInstance
{
	static FileChooser* sharedInstance = [self new];
	return sharedInstance;
}

- (id)init
{
	if((self = [super init]))
	{
		_sourceListLabels = @[ @"All", @"Open Documents", @"Uncommitted Documents" ];
		_searchResults = [NSMutableArray array];

		self.tableView.allowsMultipleSelection = YES;
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

		_progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
		_progressIndicator.style                = NSProgressIndicatorStyleSpinning;
		_progressIndicator.controlSize          = NSControlSizeSmall;
		_progressIndicator.displayedWhenStopped = NO;

		NSDictionary* footerViews = @{
			@"dividerView":        OakCreateNSBoxSeparator(),
			@"statusTextField":    self.statusTextField,
			@"itemCountTextField": self.itemCountTextField,
			@"progressIndicator":  _progressIndicator,
		};

		NSView* footerView = self.footerView;
		OakAddAutoLayoutViewsToSuperview(footerViews.allValues, footerView);

		[footerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[dividerView]|"                                 options:0 metrics:nil views:footerViews]];
		[footerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(24)-[statusTextField]-[itemCountTextField]-(4)-[progressIndicator]-(4)-|" options:NSLayoutFormatAlignAllCenterY metrics:nil views:footerViews]];
		[footerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[dividerView(==1)]-(4)-[statusTextField]-(5)-|" options:0 metrics:nil views:footerViews]];

		[self updateScrollViewInsets];

		OakSetupKeyViewLoop(@[ self.searchField, _scopeBar.view ]);
		self.window.initialFirstResponder = self.searchField;

		self.sourceIndex = [NSUserDefaults.standardUserDefaults integerForKey:kUserDefaultsFileChooserSourceIndexKey];
		[self updateWindowTitle];
		[_scopeBar bind:NSValueBinding toObject:self withKeyPath:@"sourceIndex" options:nil];
	}
	return self;
}

- (IBAction)selectNextTab:(id)sender     { [_scopeBar selectNextButton:sender]; }
- (IBAction)selectPreviousTab:(id)sender { [_scopeBar selectPreviousButton:sender]; }
- (void)updateShowTabMenu:(NSMenu*)aMenu { [_scopeBar updateGoToMenu:aMenu];}

- (void)showWindow:(id)sender
{
	[super showWindow:sender];
}

- (void)windowWillClose:(NSNotification*)aNotification
{
	[self stopSearch];
	_scmInfo = nil;
	_records = nil;

	self.items = @[ ];
}

- (void)updateWindowTitle
{
	NSString* src = nil;
	switch(self.sourceIndex)
	{
		case kFileChooserAllSourceIndex:                src = [self.path stringByAbbreviatingWithTildeInPath]; break;
		case kFileChooserOpenDocumentsSourceIndex:      src = @"Open Documents";                               break;
		case kFileChooserUncommittedChangesSourceIndex: src = @"Uncommitted Documents";                        break;
	}
	self.window.title = src ?: @"Open Quickly";
}

- (void)setCurrentDocument:(NSUUID*)identifier
{
	if(_currentDocument == identifier || [_currentDocument isEqual:identifier])
		return;
	_currentDocument = identifier;
	[self reload];
}

- (void)setSourceIndex:(NSUInteger)newIndex
{
	if(_sourceIndex != newIndex)
	{
		_sourceIndex = newIndex;
		[self updateWindowTitle];
		[self reload];

		if(_sourceIndex == 0)
				[NSUserDefaults.standardUserDefaults removeObjectForKey:kUserDefaultsFileChooserSourceIndexKey];
		else	[NSUserDefaults.standardUserDefaults setObject:@(_sourceIndex) forKey:kUserDefaultsFileChooserSourceIndexKey];
	}
}

- (void)addRecordsForDocuments:(NSArray<OakDocument*>*)documents
{
	NSUInteger firstDirty = _records.count;
	for(OakDocument* doc in documents)
		[_records addObject:[[FileChooserItem alloc] initWithDocument:doc base:_path isCurrent:[doc.identifier isEqual:_currentDocument]]];

	[self updateRecordsFrom:firstDirty];
}

- (void)updateRecordsFrom:(NSUInteger)first
{
	// OakNotEmptyString, matching the batch ranker's own test exactly: the original only
	// looked up abbreviations on the filter branch, and a nil-vs-empty mismatch here would
	// silently drop the user's learned bindings.
	NSArray<NSString*>* bindings = OakNotEmptyString(_filter.globString) ? nil : [[OakAbbreviations abbreviationsForName:@"OakFileChooserBindings"] stringsForAbbreviation:_filter.filterString];
	self.items = [FileChooserItem rankedItemsFromRecords:_records fromIndex:first globString:_filter.globString filterString:_filter.filterString bindings:bindings];
}

// ========
// = Path =
// ========

- (void)setPath:(NSString*)aString
{
	if(_path == aString || [_path isEqualToString:aString])
		return;
	_path = aString;
	_scmInfo = nil;

	if(_sourceIndex == kFileChooserAllSourceIndex)
		[self startSearch:_path];
	else if(_sourceIndex == kFileChooserUncommittedChangesSourceIndex)
		[self reloadSCMStatus];
	[self updateWindowTitle];
}

- (void)reload
{
	[self stopSearch];
	_scmInfo = nil;

	switch(_sourceIndex)
	{
		case kFileChooserAllSourceIndex:
		{
			[self startSearch:_path];
		}
		break;

		case kFileChooserOpenDocumentsSourceIndex:
		{
			_records = [NSMutableArray array];
			[self addRecordsForDocuments:[OakDocumentController.sharedInstance openDocuments]];
		}
		break;

		case kFileChooserUncommittedChangesSourceIndex:
		{
			[self reloadSCMStatus];
		}
		break;
	}
}

- (void)reloadSCMStatus
{
	if(!_scmInfo && (_scmInfo = [FileChooserSCMInfo infoForPath:_path]))
	{
		__weak FileChooser* weakSelf = self;
		[_scmInfo addStatusCallback:^{
			FileChooser* strongSelf = weakSelf;
			if(strongSelf.sourceIndex == kFileChooserUncommittedChangesSourceIndex)
				[strongSelf reloadSCMStatus];
		}];
	}

	_records = [NSMutableArray array];
	if(_scmInfo)
	{
		NSMutableArray<OakDocument*>* scmStatus = [NSMutableArray array];
		for(NSString* path in [_scmInfo uncommittedPaths])
			[scmStatus addObject:[OakDocument documentWithPath:path]];
		[self addRecordsForDocuments:scmStatus];
	}
}

- (void)startSearch:(NSString*)path
{
	if(_searching)
		[self stopSearch];

	self.items = @[ ];
	_records = [NSMutableArray array];

	if(!path)
		return;

	NSDictionary* options = [FileChooserSupport searchOptionsForPath:path];

	size_t searchToken = _lastSearchToken;
	_searching = YES;
	@synchronized(_searchResults) {
		[_searchResults removeAllObjects];
	}

	dispatch_semaphore_t sem = dispatch_semaphore_create(0);

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		__block BOOL didSignal = NO;

		[OakDocumentController.sharedInstance enumerateDocumentsAtPath:path options:options usingBlock:^(OakDocument* document, BOOL* stop){
			@synchronized(_searchResults) {
				if(document.open == NO)
				{
					dispatch_semaphore_signal(sem);
					didSignal = YES;
				}

				if(searchToken == _lastSearchToken)
						[_searchResults addObject:document];
				else	*stop = YES;
			}
		}];

		if(didSignal == NO)
			dispatch_semaphore_signal(sem);

		dispatch_async(dispatch_get_main_queue(), ^{
			if(searchToken == _lastSearchToken)
			{
				_searching = NO;
				[self handleSearchResults:nil];
			}
		});
	});

	dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
	[self handleSearchResults:nil];

	_pollInterval = 0.02;
	_pollTimer = [NSTimer scheduledTimerWithTimeInterval:_pollInterval target:self selector:@selector(handleSearchResults:) userInfo:nil repeats:NO];
	[_progressIndicator performSelector:@selector(startAnimation:) withObject:self afterDelay:0.2];
}

- (void)handleSearchResults:(NSTimer*)aTimer
{
	@synchronized(_searchResults) {
		if(_searchResults.count || !_searching)
			_searchPath = _searching ? [_searchResults.lastObject.path stringByDeletingLastPathComponent] : nil;
		[self addRecordsForDocuments:_searchResults];
		[_searchResults removeAllObjects];
	}

	if(_searching)
	{
		_pollInterval = MIN(_pollInterval * 2, 0.32);
		_pollTimer = [NSTimer scheduledTimerWithTimeInterval:_pollInterval target:self selector:@selector(handleSearchResults:) userInfo:nil repeats:NO];
	}
	else
	{
		[self stopSearch];
		[self updateStatusText:self];
	}
}

- (void)stopSearch
{
	if(_searching)
	{
		_searching = NO;
		++_lastSearchToken;
	}

	[NSObject cancelPreviousPerformRequestsWithTarget:_progressIndicator selector:@selector(startAnimation:) object:self];
	[_progressIndicator stopAnimation:self];
	[_pollTimer invalidate];
	_pollTimer = nil;
}

- (void)updateFilterString:(NSString*)aString
{
	NSString* oldFilter = [_filter.effectiveFilter ?: @"" copy];
	_filter = [FileChooserFilter filterWithString:aString];

	if(![oldFilter isEqualToString:_filter.effectiveFilter])
		[super updateFilterString:aString];
}

- (void)updateItems:(id)sender
{
	[self updateRecordsFrom:0];
}

- (void)updateStatusText:(id)sender
{
	if(_searching)
	{
		NSString* path = [FileChooserSupport path:_searchPath relativeTo:_path];
		[self.statusTextField.cell setLineBreakMode:NSLineBreakByTruncatingMiddle];
		self.statusTextField.stringValue = [NSString stringWithFormat:@"Searching “%@”…", path];
	}
	else if(self.tableView.selectedRow == -1)
	{
		self.statusTextField.stringValue = @"";
	}
	else
	{
		FileChooserItem* record = self.items[self.tableView.selectedRow];

		NSString* path = record.document.path;
		if(path)
		{
			if(self.path && [path hasPrefix:self.path])
					path = [FileChooserSupport path:path relativeTo:self.path];
			else	path = [path stringByAbbreviatingWithTildeInPath];
		}
		else // untitled file
		{
			path = record.document.displayName;
		}

		[self.statusTextField.cell setLineBreakMode:NSLineBreakByTruncatingHead];
		self.statusTextField.stringValue = path;
	}
}

- (NSArray*)selectedItems
{
	NSMutableArray* res = [NSMutableArray array];
	for(FileChooserItem* record in [self.items objectsAtIndexes:self.tableView.selectedRowIndexes])
	{
		NSMutableDictionary* item = [NSMutableDictionary dictionary];
		if(OakNotEmptyString(_filter.selectionString))
			item[@"selectionString"] = _filter.selectionString;
		if(record.document.path)
				item[@"path"] = record.document.path;
		else	item[@"identifier"] = record.document.identifier.UUIDString;
		[res addObject:item];
	}
	return res;
}

// =========================
// = NSTableViewDataSource =
// =========================

- (NSView*)tableView:(NSTableView*)aTableView viewForTableColumn:(NSTableColumn*)aTableColumn row:(NSInteger)row
{
	NSTableCellView* res = [aTableView makeViewWithIdentifier:aTableColumn.identifier owner:self];
	if(!res)
	{
		NSButton* closeButton = OakCreateCloseButton();
		closeButton.target = self;
		closeButton.action = @selector(takeItemToCloseFrom:);

		res = [[OakFileTableCellView alloc] initWithCloseButton:closeButton];
		res.identifier = aTableColumn.identifier;

		[closeButton bind:NSHiddenBinding toObject:res withKeyPath:@"objectValue.closeDisabled" options:nil];
	}

	res.objectValue = self.items[row];
	return res;
}

// =================
// = Action Method =
// =================

- (void)accept:(id)sender
{
	if(OakNotEmptyString(_filter.filterString))
	{
		for(FileChooserItem* item in [self.items objectsAtIndexes:self.tableView.selectedRowIndexes])
		{
			if(!item.isDirectoryMatched && item.document.path)
				[[OakAbbreviations abbreviationsForName:@"OakFileChooserBindings"] learnAbbreviation:_filter.filterString forString:item.document.path];
		}
	}

	[super accept:sender];
}

- (void)takeItemToCloseFrom:(NSButton*)sender
{
	NSInteger row = [self.tableView rowForView:sender];
	if(row != -1)
	{
		FileChooserItem* item = self.items[row];
		if(item.document.path)
		{
			// FIXME We need a proper interface to close documents
			if(id target = [NSApp targetForAction:@selector(fileBrowser:closeURL:)])
				[target fileBrowser:nil closeURL:[NSURL fileURLWithPath:item.document.path]];
		}
	}
}

- (IBAction)goToParentFolder:(id)sender
{
	self.path = [_path stringByDeletingLastPathComponent];
}

- (BOOL)validateMenuItem:(NSMenuItem*)item
{
	BOOL activate = YES;
	if([item action] == @selector(goToParentFolder:))
		activate = _sourceIndex == kFileChooserAllSourceIndex && [FileChooserSupport pathHasParent:_path];
	return activate;
}
@end
