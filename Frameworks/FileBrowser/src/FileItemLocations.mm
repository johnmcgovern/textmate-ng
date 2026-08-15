#import "FileItemLocations.h"

// Moved verbatim from FileItem.mm. See FileItemLocations.h for why these globals
// live in ObjC++ rather than in FileItem.swift.
NSURL* const kURLLocationComputer  = [[NSURL alloc] initWithString:@"computer:///"];
NSURL* const kURLLocationFavorites = [[NSURL alloc] initFileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TextMate/Favorites"] isDirectory:YES];
