// Hand-written ObjC declaration of the Swift OakChooser (OakChooser.swift), for its four
// still-ObjC++ subclasses: SymbolChooser, FileChooser and BundleItemChooser in this
// framework, FavoriteChooser (Favorites.mm) in the app — so it is a public header. Kept
// out of the bridging header (Swift defines the class); the contract, including that the
// base's internal calls reach subclass overrides of the three hooks at the bottom, is
// pinned by t_chooser.mm (rule 18).
@interface OakChooser : NSWindowController
@property (nonatomic) SEL action;
@property (nonatomic, weak) id target;

@property (nonatomic) NSString* filterString;
@property (nonatomic, readonly) NSArray* selectedItems;

- (void)showWindowRelativeToFrame:(NSRect)parentFrame;

// For subclasses
@property (nonatomic) NSArray* items;
@property (nonatomic, readonly) NSSearchField*      searchField;
@property (nonatomic, readonly) NSScrollView*       scrollView;
@property (nonatomic, readonly) NSTableView*        tableView;
@property (nonatomic, readonly) NSVisualEffectView* footerView;
@property (nonatomic, readonly) NSTextField*        statusTextField;
@property (nonatomic, readonly) NSTextField*        itemCountTextField;
- (void)addTitlebarAccessoryView:(NSView*)titlebarView;
- (void)updateScrollViewInsets;

@property (nonatomic) BOOL drawTableViewAsHighlighted;
- (void)updateFilterString:(NSString*)aString;
- (NSUInteger)removeItemsAtIndexes:(NSIndexSet*)anIndexSet;
- (void)performDefaultButtonClick:(id)sender;
- (void)accept:(id)sender;
- (void)cancel:(id)sender;
@end
