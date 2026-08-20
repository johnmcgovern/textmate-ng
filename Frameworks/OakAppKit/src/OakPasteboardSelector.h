// Hand-written ObjC declaration of the Swift OakPasteboardSelector
// (OakPasteboardSelector.swift), for the one cross-framework caller that sees it
// through a header — FFTextFieldViewController.mm reaches +sharedInstance.window.
// Same arrangement as OakScopeBarView.h; kept out of OakAppKit-Bridging-Header.h
// (Swift defines the class, and OakPasteboard.swift sees it in-module). The tableView
// outlet is now an @IBOutlet in the Swift class, so it is gone from here.
@interface OakPasteboardSelector : NSWindowController
@property (class, readonly) OakPasteboardSelector* sharedInstance;

- (void)setIndex:(NSUInteger)index;
- (void)setEntries:(NSArray*)entries;

- (NSInteger)showAtLocation:(NSPoint)aLocation;
- (void)setWidth:(CGFloat)width;
- (void)setPerformsActionOnSingleClick;
- (NSArray*)entries;
@end
