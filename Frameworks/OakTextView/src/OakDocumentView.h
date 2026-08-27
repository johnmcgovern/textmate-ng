// Hand-declared (rule 23): this class is defined in OakDocumentView.swift.
//
// It must not appear in OakTextView-Bridging-Header.h, where it would collide
// with the generated OakTextView-Swift.h (rule 43).
#import "OakTextView.h"
#import <oak/debug.h>

@class OakDocument;

@interface OakDocumentView : NSView
@property (nonatomic, readonly) OakTextView* textView;
@property (nonatomic) OakDocument* document;
@property (nonatomic) BOOL hideStatusBar;
- (IBAction)toggleLineNumbers:(id)sender;

- (void)addAuxiliaryView:(NSView*)aView atEdge:(NSRectEdge)anEdge;
- (void)removeAuxiliaryView:(NSView*)aView;

- (IBAction)showSymbolChooser:(id)sender;
@end
