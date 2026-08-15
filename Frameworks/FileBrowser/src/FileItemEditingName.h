// The [filename, displayName] pair the file browser's cell binds its text field
// to, as a category on FileItem.
//
// It stays ObjC++ (rather than moving into the Swift cell view) because it
// belongs to FileItem, which is not ported yet, and because the binding
// "objectValue.editingAndDisplayName" needs FileItem itself to publish KVO for
// that key — the +keyPathsForValuesAffectingEditingAndDisplayName in the .mm
// declares it depends on URL and displayName. When FileItem becomes Swift this
// folds into it.
//
// The setter is intentionally a no-op: the text field binds two-way, so editing
// writes back here, but the actual rename is driven from the controller's text
// field delegate, not from this key.
#import "FileItem.h"

@interface FileItem (EditingName)
@property (nonatomic) NSArray* editingAndDisplayName;
@end
