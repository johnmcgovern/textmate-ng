#import "FileChooserItem.h"
#import "OakChooserMarkup.h"
#import "OakAbbreviations.h"
#import <OakFoundation/OakFoundation.h>
#import <OakFoundation/NSString Additions.h>
#import <document/OakDocument.h>
#import <document/OakDocumentController.h>
#import <ns/ns.h>
#import <regexp/glob.h>
#import <text/ranker.h>

// The C++ half of FileChooser's row model, moved from FileChooser.mm (2026-08-20); see
// FileChooserItem.h for why it cannot become Swift.
//
// The class body below came out of the original with `git show`, not retyping (rule 6),
// and t_file_chooser_item.mm asserts the C++ is byte-identical. The edits are mechanical:
// the ivar block became a class extension (the properties are in the public header now),
// -initWithDocument:base: takes an NSString base instead of std::string const&, and
// -updateRecordsFrom:'s body became the batch class method at the bottom — its ivar reads
// are parameters and it returns the sorted array rather than assigning self.items.

@interface FileChooserItem ()
{
	std::string _path;
	std::string _directory;
	std::string _file;
	NSInteger _lruRank;

	BOOL _isCurrent;
	double _rank;

	std::vector<std::pair<size_t, size_t>> _coverDirectory;
	std::vector<std::pair<size_t, size_t>> _coverFile;

	NSAttributedString* _name;
	NSAttributedString* _folder;
}
// C++-typed and therefore private to this file; the batch ranker below is their only
// caller, which is the whole point of the extraction.
- (void)updateRankUsingFilter:(std::string const&)filter bindings:(std::vector<std::string> const&)bindings;
- (void)updateRankUsingGlob:(path::glob_t const&)glob;
@end

@implementation FileChooserItem
+ (NSSet*)keyPathsForValuesAffectingIcon
{
	return [NSSet setWithObjects:@"document.icon", nil];
}

+ (NSSet*)keyPathsForValuesAffectingCloseDisabled
{
	return [NSSet setWithObjects:@"document.open", @"document.path", nil];
}

- (NSImage*)icon
{
	NSImage* image = [_document.icon copy];
	[image setSize:NSMakeSize(32, 32)];
	return image;
}

- (BOOL)isCloseDisabled
{
	return !_document.open || !_document.path;
}

- (instancetype)initWithDocument:(OakDocument*)aDocument base:(NSString*)aBase isCurrent:(BOOL)isCurrent
{
	if(self = [super init])
	{
		std::string const base = to_s(aBase);
		_document  = aDocument;
		_path      = to_s(_document.path);
		_directory = _document.path ? path::relative_to(path::parent(_path), base) : "";
		_file      = _document.path ? path::name(_path) : to_s(_document.displayName);
		_lruRank   = [OakDocumentController.sharedInstance lruRankForDocument:_document];
		_isCurrent = isCurrent;

		if(_directory.empty() && _document.path)
			_directory = ".";
	}
	return self;
}

- (void)reset
{
	_matched = NO;
	_name    = nil;
	_folder  = nil;
	_rank    = 0;
	_coverDirectory.clear();
	_coverFile.clear();
}

- (void)updateRankUsingFilter:(std::string const&)filter bindings:(std::vector<std::string> const&)bindings
{
	[self reset];

	double rank = _isCurrent ? 0.1 : 3;
	if(!filter.empty() && filter != NULL_STR)
	{
		std::vector<std::pair<size_t, size_t>> cover;
		if(rank = oak::rank(filter, _file, &_coverFile))
		{
			rank += 1;

			auto it = std::find(bindings.begin(), bindings.end(), _path);
			if(it != bindings.end())
				rank = 2 + (bindings.end() - it) / (double)bindings.size();
		}
		else if(rank = oak::rank(filter, _directory + "/" + _file, &cover))
		{
			for(auto pair : cover)
			{
				if(pair.first < _directory.size())
					_coverDirectory.emplace_back(pair.first, std::min(pair.second, _directory.size()));
				if(_directory.size() + 1 < pair.second)
					_coverFile.emplace_back(std::max(pair.first, _directory.size() + 1) - _directory.size() - 1, pair.second - _directory.size() - 1);
			}
		}
	}

	if(rank)
	{
		_matched = YES;
		_rank = 3 - rank;
	}
}

- (void)updateRankUsingGlob:(path::glob_t const&)glob
{
	[self reset];
	_matched = glob.does_match(_path);
}

- (NSAttributedString*)name
{
	if(!_name)
		_name = CreateAttributedStringWithMarkedUpRanges(_file, _coverFile, NSLineBreakByTruncatingTail);
	return _name;
}

- (NSAttributedString*)folder
{
	if(!_folder)
		_folder = CreateAttributedStringWithMarkedUpRanges(_directory, _coverDirectory, NSLineBreakByTruncatingHead);
	return _folder;
}

- (BOOL)isDirectoryMatched
{
	return !_coverDirectory.empty();
}

- (NSComparisonResult)rankCompare:(FileChooserItem*)otherItem
{
	if(_rank < otherItem->_rank)
		return NSOrderedAscending;
	else if(_rank > otherItem->_rank)
		return NSOrderedDescending;
	else if(_lruRank > otherItem->_lruRank)
		return NSOrderedAscending;
	else if(_lruRank < otherItem->_lruRank)
		return NSOrderedDescending;
	return [self compare:otherItem];
}

- (NSComparisonResult)compare:(FileChooserItem*)otherItem
{
	return [to_ns(_file) localizedCompare:to_ns(otherItem->_file)];
}

+ (NSArray<FileChooserItem*>*)rankedItemsFromRecords:(NSArray<FileChooserItem*>*)records fromIndex:(NSUInteger)first globString:(NSString*)globString filterString:(NSString*)filterString bindings:(NSArray<NSString*>*)bindings
{
	SEL compareSelector = @selector(compare:);
	if(OakNotEmptyString(globString))
	{
		path::glob_t const glob(to_s(globString), false, false);
		[records enumerateObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(first, records.count - first)] options:NSEnumerationConcurrent usingBlock:^(FileChooserItem* item, NSUInteger idx, BOOL* stop){
			[item updateRankUsingGlob:glob];
		}];
	}
	else
	{
		compareSelector = @selector(rankCompare:);

		std::string const filter = to_s(filterString);

		std::vector<std::string> cxxBindings;
		for(NSString* str in bindings)
			cxxBindings.push_back(to_s(str));

		[records enumerateObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(first, records.count - first)] options:NSEnumerationConcurrent usingBlock:^(FileChooserItem* item, NSUInteger idx, BOOL* stop){
			[item updateRankUsingFilter:filter bindings:cxxBindings];
		}];
	}

	NSArray* array = [records filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isMatched == YES"]];
	return [array sortedArrayUsingSelector:compareSelector];
}
@end
