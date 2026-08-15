#import "FileItemEditingName.h"

// Moved verbatim from FileItemTableCellView.mm's FileItem (FileItemWrapper)
// category. See the header for why it lives on FileItem rather than in the
// Swift cell view.
@implementation FileItem (EditingName)
+ (NSSet*)keyPathsForValuesAffectingEditingAndDisplayName
{
	return [NSSet setWithObjects:@"URL", @"displayName", nil];
}

- (NSArray*)editingAndDisplayName
{
	return @[ self.URL.lastPathComponent ?: @"", self.displayName ];
}

- (void)setEditingAndDisplayName:(NSArray*)unused
{
	// Because ‘editingAndDisplayName’ is bound to our text field then we receive updates when user edits the text field
}
@end
