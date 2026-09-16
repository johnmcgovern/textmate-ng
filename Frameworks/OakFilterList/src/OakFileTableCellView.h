// Hand-written ObjC declaration of the Swift OakFileTableCellView
// (OakFileTableCellView.swift). Both callers, FileChooser and FavoriteChooser, are Swift
// in this framework now; the header remains for t_file_table_cell_view.mm, which pins
// the behaviour (rule 18).
@interface OakFileTableCellView : NSTableCellView
- (instancetype)initWithCloseButton:(NSButton*)closeButton;
@end
