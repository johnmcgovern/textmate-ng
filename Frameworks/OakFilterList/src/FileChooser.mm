#import "FileChooser.h"
#import "OakChooserMarkup.h"
#import "OakFileTableCellView.h"
#import "FileChooserItem.h"
#import "OakAbbreviations.h"
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakAppKit/OakScopeBarView.h>
#import <OakAppKit/NSImage Additions.h>
#import <OakFoundation/NSString Additions.h>
#import <OakFoundation/OakFoundation.h>
#import <document/OakDocument.h>
#import <document/OakDocumentController.h>
#import <scm/scm.h>
#import <ns/ns.h>
#import <regexp/glob.h>
#import <text/format.h>
#import <text/parse.h>
#import <text/ctype.h>
#import <text/ranker.h>
#import <settings/settings.h>
#import <oak/algorithm.h>
#import <oak/duration.h>

@interface NSObject (FileBrowserDelegate)
- (void)fileBrowser:(id)aFileBrowser closeURL:(NSURL*)anURL;
@end

static NSString* const kUserDefaultsFileChooserSourceIndexKey = @"fileChooserSourceIndex";

NSUInteger const kFileChooserAllSourceIndex                = 0;
NSUInteger const kFileChooserOpenDocumentsSourceIndex      = 1;
NSUInteger const kFileChooserUncommittedChangesSourceIndex = 2;

static NSDictionary* globs_for_path (std::string const& path)
{
	static std::map<std::string, NSString*> const map = {
		{ kSettingsExcludeDirectoriesInFileChooserKey, kSearchExcludeDirectoryGlobsKey },
		{ kSettingsExcludeDirectoriesKey,              kSearchExcludeDirectoryGlobsKey },
		{ kSettingsExcludeFilesInFileChooserKey,       kSearchExcludeFileGlobsKey      },
		{ kSettingsExcludeFilesKey,                    kSearchExcludeFileGlobsKey      },
		{ kSettingsExcludeInFileChooserKey,            kSearchExcludeGlobsKey          },
		{ kSettingsExcludeKey,                         kSearchExcludeGlobsKey          },
		{ kSettingsBinaryKey,                          kSearchExcludeGlobsKey          },
		{ kSettingsIncludeDirectoriesKey,              kSearchDirectoryGlobsKey        },
		{ kSettingsIncludeFilesInFileChooserKey,       kSearchFileGlobsKey             },
		{ kSettingsIncludeFilesKey,                    kSearchFileGlobsKey             },
		{ kSettingsIncludeInFileChooserKey,            kSearchGlobsKey                 },
		{ kSettingsIncludeKey,                         kSearchGlobsKey                 },
	};

	NSMutableDictionary* res = [NSMutableDictionary dictionary];

	settings_t const settings = settings_for_path(NULL_STR, "", path);
	for(auto const& pair : map)
	{
		if(NSString* glob = to_ns(settings.get(pair.first)))
		{
			if(!res[pair.second])
				res[pair.second] = [NSMutableArray array];
			[res[pair.second] addObject:glob];
		}
	}

	if(!res[kSearchDirectoryGlobsKey] && !res[kSearchGlobsKey])
		res[kSearchDirectoryGlobsKey] = @[ @"*" ];
	if(!res[kSearchFileGlobsKey] && !res[kSearchGlobsKey])
		res[kSearchFileGlobsKey] = @[ @"*" ];

	return res;
}

@interface FileChooser ()
{
	scm::info_ptr                     _scmInfo;
	NSMutableArray<FileChooserItem*>* _records;

	NSString* _globString;
	NSString* _filterString;
	NSString* _selectionString;
	NSString* _symbolString;

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
	_scmInfo.reset();
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
	NSArray<NSString*>* bindings = OakNotEmptyString(_globString) ? nil : [[OakAbbreviations abbreviationsForName:@"OakFileChooserBindings"] stringsForAbbreviation:_filterString];
	self.items = [FileChooserItem rankedItemsFromRecords:_records fromIndex:first globString:_globString filterString:_filterString bindings:bindings];
}

// ========
// = Path =
// ========

- (void)setPath:(NSString*)aString
{
	if(_path == aString || [_path isEqualToString:aString])
		return;
	_path = aString;
	_scmInfo.reset();

	if(_sourceIndex == kFileChooserAllSourceIndex)
		[self startSearch:_path];
	else if(_sourceIndex == kFileChooserUncommittedChangesSourceIndex)
		[self reloadSCMStatus];
	[self updateWindowTitle];
}

- (void)reload
{
	[self stopSearch];
	_scmInfo.reset();

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
	if(!_scmInfo && (_scmInfo = scm::info(to_s(_path))))
	{
		_scmInfo->push_callback(^(scm::info_t const& info){
			if(_sourceIndex == kFileChooserUncommittedChangesSourceIndex)
				[self reloadSCMStatus];
		});
	}

	_records = [NSMutableArray array];
	if(_scmInfo)
	{
		NSMutableArray<OakDocument*>* scmStatus = [NSMutableArray array];
		for(auto pair : _scmInfo->status())
		{
			if(pair.second & (scm::status::modified|scm::status::added|scm::status::deleted|scm::status::conflicted))
				[scmStatus addObject:[OakDocument documentWithPath:to_ns(pair.first)]];
		}
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

	settings_t const settings = settings_for_path(NULL_STR, "", to_s(path));
	NSMutableDictionary* options = [globs_for_path(to_s(path)) mutableCopy];
	options[kSearchFollowDirectoryLinksKey] = @(settings.get(kSettingsFollowSymbolicLinksKey, false));
	options[kSearchIgnoreOrderingKey] = @YES;

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
		_pollInterval = std::min(_pollInterval * 2, 0.32);
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
	if(std::exchange(_searching, NO))
		++_lastSearchToken;

	[NSObject cancelPreviousPerformRequestsWithTarget:_progressIndicator selector:@selector(startAnimation:) object:self];
	[_progressIndicator stopAnimation:self];
	[_pollTimer invalidate];
	_pollTimer = nil;
}

- (void)updateFilterString:(NSString*)aString
{
	NSString* oldFilter = [(_globString ?: _filterString ?: @"") copy];
	aString = [aString decomposedStringWithCanonicalMapping];

	NSRegularExpression* const ptrn = [NSRegularExpression regularExpressionWithPattern:@"\\A(?:(.*?\\*.*?)|(.*?))(?::([\\d+:-x\\+]*)|@(.*))?\\z" options:NSAnchoredSearch error:nil];
	NSTextCheckingResult* m = aString ? [ptrn firstMatchInString:aString options:NSMatchingAnchored range:NSMakeRange(0, [aString length])] : nil;
	_globString      = m && [m rangeAtIndex:1].location != NSNotFound ? [aString substringWithRange:[m rangeAtIndex:1]] : nil;
	_filterString    = m && [m rangeAtIndex:2].location != NSNotFound ? [NSString stringWithCxxString:oak::normalize_filter(to_s([aString substringWithRange:[m rangeAtIndex:2]]))] : nil;
	_selectionString = m && [m rangeAtIndex:3].location != NSNotFound ? [aString substringWithRange:[m rangeAtIndex:3]] : nil;
	_symbolString    = m && [m rangeAtIndex:4].location != NSNotFound ? [aString substringWithRange:[m rangeAtIndex:4]] : nil;

	if(![oldFilter isEqualToString:_globString ?: _filterString ?: @""])
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
		std::string path = path::relative_to(to_s(_searchPath), to_s(_path));
		[self.statusTextField.cell setLineBreakMode:NSLineBreakByTruncatingMiddle];
		self.statusTextField.stringValue = [NSString stringWithFormat:@"Searching “%@”…", [NSString stringWithCxxString:path]];
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
					path = to_ns(path::relative_to(to_s(path), to_s(self.path)));
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
		if(OakNotEmptyString(_selectionString))
			item[@"selectionString"] = _selectionString;
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
	if(OakNotEmptyString(_filterString))
	{
		for(FileChooserItem* item in [self.items objectsAtIndexes:self.tableView.selectedRowIndexes])
		{
			if(!item.isDirectoryMatched && item.document.path)
				[[OakAbbreviations abbreviationsForName:@"OakFileChooserBindings"] learnAbbreviation:_filterString forString:item.document.path];
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
		activate = _sourceIndex == kFileChooserAllSourceIndex && to_s(_path) != path::parent(to_s(_path));
	return activate;
}
@end
