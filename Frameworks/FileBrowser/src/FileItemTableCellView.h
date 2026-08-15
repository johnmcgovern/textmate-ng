// Hand-written ObjC declaration of FileItemTableCellView, which is implemented
// in FileItemTableCellView.swift (Phase 4).
//
// FileBrowserViewController.mm builds one with -init, sets openButton/closeButton
// target and action, and reads openButton back; it imports this header
// unchanged. It must never reach the Swift bridging header — it declares a class
// Swift defines.
//
// Nothing checks this against the Swift at build time; a drift is an
// unrecognized selector at runtime, which is what t_file_item_table_cell_view.mm
// guards.
#import <Cocoa/Cocoa.h>

@interface FileItemTableCellView : NSTableCellView
@property (nonatomic) NSButton* openButton;
@property (nonatomic) NSButton* closeButton;
@end
