// Hand-written ObjC declaration of the Swift OakFileTableCellView
// (OakFileTableCellView.swift), for its still-ObjC++ callers: FileChooser.mm in this
// framework and FavoriteChooser (Favorites.mm) in the app, so it is a public header.
// Behaviour is pinned by t_file_table_cell_view.mm (rule 18); this disappears once those
// callers are Swift too.
@interface OakFileTableCellView : NSTableCellView
- (instancetype)initWithCloseButton:(NSButton*)closeButton;
@end
