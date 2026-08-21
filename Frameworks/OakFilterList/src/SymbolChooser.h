// Hand-written ObjC declaration of the Swift SymbolChooser (SymbolChooser.swift), for its
// caller OakDocumentView.mm in OakTextView — so it is a public header. The class's own C++
// lives in SymbolChooserSupport; the contract here is pinned by t_symbol_chooser.mm
// (rule 18).
#import "OakChooser.h"
#import <document/OakDocument.h>

@interface SymbolChooser : OakChooser
@property (class, readonly) SymbolChooser* sharedInstance;

@property (nonatomic) OakDocument* TMDocument;
@property (nonatomic) NSString* selectionString;
@end
