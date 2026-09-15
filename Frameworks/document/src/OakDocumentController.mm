#import "OakDocumentController.h"
#import "OakDocument Internal.h"
#import "OakDocumentRegistry.h"
#import "OakDocumentWalk.h"

@interface OakDocumentController ()
{
	// The C++ registry — three maps under a mutex — behind an ObjC face
	// (rule 25). Created with the controller, as the maps were.
	OakDocumentRegistry* _registry;

	NSMutableDictionary* _rankedPaths;
	NSMutableDictionary* _rankedUUIDs;
	NSUInteger _lastLRURank;
	NSTimer* _saveRankedPathsTimer;
}
@end

@implementation OakDocumentController
+ (instancetype)sharedInstance
{
	static OakDocumentController* sharedInstance = [self new];
	return sharedInstance;
}

- (instancetype)init
{
	if(self = [super init])
	{
		_registry = [[OakDocumentRegistry alloc] init];
	}
	return self;
}

- (OakDocument*)untitledDocument
{
	return [self documentWithPath:nil];
}

- (OakDocument*)documentWithPath:(NSString*)aPath
{
	return [_registry documentForPath:aPath];
}

- (OakDocument*)findDocumentWithIdentifier:(NSUUID*)anUUID
{
	return [_registry documentForIdentifier:anUUID];
}

- (void)register:(OakDocument*)aDocument
{
	[_registry addDocument:aDocument];
}

- (void)unregister:(OakDocument*)aDocument
{
	[_registry removeDocument:aDocument];
}

- (void)update:(OakDocument*)aDocument
{
	[_registry updateDocument:aDocument];
}

- (NSUInteger)firstAvailableUntitledCount
{
	return [_registry firstAvailableUntitledCount];
}

- (NSArray<OakDocument*>*)documents
{
	return [_registry documents];
}

- (NSArray<OakDocument*>*)openDocuments
{
	NSArray<OakDocument*>* array = [self.documents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isOpen == YES"]];
	return [array sortedArrayUsingComparator:^NSComparisonResult(OakDocument* lhs, OakDocument* rhs){
		if(!lhs.path && !rhs.path)
			return lhs.untitledCount < rhs.untitledCount ? NSOrderedAscending : (lhs.untitledCount > rhs.untitledCount ? NSOrderedDescending : NSOrderedSame);
		else if(lhs.path && rhs.path)
			return [lhs.path localizedCompare:rhs.path];
		else if(lhs.path)
			return NSOrderedDescending;
		else
			return NSOrderedAscending;
	}];
}

- (NSArray<OakDocument*>*)openDocumentsInDirectory:(NSString*)aDirectory
{
	NSArray<OakDocument*>* array = [self.documents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"path BEGINSWITH %@ OR directory BEGINSWITH %@", aDirectory, aDirectory]];
	return [array sortedArrayUsingComparator:^NSComparisonResult(OakDocument* lhs, OakDocument* rhs){
		if(lhs.untitledCount != rhs.untitledCount)
			return lhs.untitledCount < rhs.untitledCount ? NSOrderedAscending : NSOrderedDescending;
		return [lhs.displayName localizedCompare:rhs.displayName];
	}];
}

- (NSArray<OakDocument*>*)untitledDocumentsInDirectory:(NSString*)aDirectory
{
	return [[self openDocumentsInDirectory:aDirectory] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"path == NULL"]];
}

// The two window wrappers, -showDocument: and -showDocument:inProject:
// bringToFront:, are in OakDocumentControllerCxx.mm: they pass a C++ range.

// ======================
// = Last Recently Used =
// ======================

- (void)setupRankedPaths
{
	if(_rankedPaths)
		return;

	_rankedPaths = [NSMutableDictionary dictionary];
	_rankedUUIDs = [NSMutableDictionary dictionary];

	NSArray* paths = [NSUserDefaults.standardUserDefaults stringArrayForKey:@"LRUDocumentPaths"];

	// LEGACY format used by 2.0-beta.12.11 and earlier
	if(!paths)
	{
		NSDictionary* dictionary = [NSUserDefaults.standardUserDefaults dictionaryForKey:@"LRUDocumentPaths"];
		paths = dictionary[@"paths"];
	}

	for(NSString* path in [paths reverseObjectEnumerator])
		_rankedPaths[path] = @(++_lastLRURank);
}

- (void)saveRankedPathsTimerDidFire:(NSTimer*)aTimer
{
	_saveRankedPathsTimer = nil;

	// Was a std::map keyed by the negated rank: highest rank first, and the
	// first fifty. Ranks are unique, so a sort says the same thing.
	NSArray* paths = [_rankedPaths.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString* lhs, NSString* rhs){
		return [_rankedPaths[rhs] compare:_rankedPaths[lhs]];
	}];
	NSMutableArray* array = [NSMutableArray array];
	for(NSString* path in paths)
	{
		[array addObject:path];
		if(array.count == 50)
			break;
	}
	[NSUserDefaults.standardUserDefaults setObject:array forKey:@"LRUDocumentPaths"];
}

- (NSInteger)lruRankForDocument:(OakDocument*)aDocument
{
	[self setupRankedPaths];
	return aDocument.path ? [_rankedPaths[aDocument.path] intValue] : [_rankedUUIDs[aDocument.identifier] intValue];
}

- (void)didTouchDocument:(OakDocument*)aDocument
{
	if(!aDocument)
		return;

	[self setupRankedPaths];
	if(aDocument.path)
			_rankedPaths[aDocument.path] = @(++_lastLRURank);
	else	_rankedUUIDs[aDocument.identifier] = @(++_lastLRURank);

	[_saveRankedPathsTimer invalidate];
	_saveRankedPathsTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(saveRankedPathsTimerDidFire:) userInfo:nil repeats:NO];
}

// ======================
// = Directory Scanning =
// ======================

- (void)enumerateDocumentsAtPath:(NSString*)aDirectory options:(NSDictionary*)someOptions usingBlock:(void(^)(OakDocument* document, BOOL* stop))block;
{
	[self enumerateDocumentsAtPaths:@[ aDirectory ] options:someOptions usingBlock:block];
}

- (void)enumerateDocumentsAtPaths:(NSArray*)items options:(NSDictionary*)someOptions usingBlock:(void(^)(OakDocument* document, BOOL* stop))block
{
	[OakDocumentWalk enumerateDocumentsAtPaths:items options:someOptions openDocumentsInDirectory:^NSArray<OakDocument*>*(NSString* directory, BOOL ignoreOrdering){
		return ignoreOrdering ? [self openDocumentsInDirectory:directory] : [self untitledDocumentsInDirectory:directory];
	} usingBlock:block];
}
@end
