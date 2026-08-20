// Hand-written ObjC declaration of the Swift OakPasteboardChooser
// (OakPasteboardChooser.swift), for its cross-framework caller OakDocumentView.mm.
// Same arrangement as OakScopeBarView.h; kept out of OakAppKit-Bridging-Header.h
// (Swift defines the class, and it sees OakPasteboard / OakScopeBarViewController
// in-module). The selector surface is pinned by t_pasteboard.mm (rule 18).
@class OakPasteboard;

@interface OakPasteboardChooser : NSWindowController
@property (nonatomic) NSString* filterString;
@property (nonatomic) SEL action;
@property (nonatomic) SEL alternateAction;
@property (nonatomic, weak) id target;

+ (instancetype)sharedChooserForPasteboard:(OakPasteboard*)pboard;
- (void)showWindowRelativeToFrame:(NSRect)parentFrame;
@end
