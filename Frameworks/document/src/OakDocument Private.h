#import "OakDocument Internal.h"
#import <undo/undo.h> // ng::buffer_t and ng::undo_manager_t types

@interface OakDocument (Private)
- (ng::buffer_t&)buffer;
- (ng::undo_manager_t&)undoManager;

- (BOOL)performReplacements:(std::multimap<std::pair<size_t, size_t>, std::string> const&)someReplacements checksum:(uint32_t)crc32;
@end
