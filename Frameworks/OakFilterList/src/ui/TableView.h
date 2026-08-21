// Hand-written ObjC declaration of the Swift OakInactiveTableRowView
// (ui/TableView.swift), for its one caller OakChooser.mm, still ObjC++. Kept out of
// any bridging header (Swift defines the class); the selector surface is pinned by
// t_tableview.mm (rule 18). Disappears once OakChooser is Swift too.
@interface OakInactiveTableRowView : NSTableRowView
@property (nonatomic) BOOL drawAsHighlighted;
@end
