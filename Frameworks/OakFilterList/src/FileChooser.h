// Hand-written ObjC declaration of the Swift FileChooser (FileChooser.swift), for its
// callers outside this framework: OakDocumentView.mm (ObjC++) and
// DocumentWindowController.swift, which reaches it through DocumentWindow's bridging
// header — so it is a public header. The panel's C++ lives in FileChooserItem and
// FileChooserSupport; the contract here is pinned by t_file_chooser.mm (rule 18).
//
// The three kFileChooser*SourceIndex constants that used to be declared here are gone: they
// were extern NSUInteger definitions, which Swift cannot provide (rule 19), and nothing
// outside FileChooser.mm ever read them. They are private to FileChooser.swift now.
#import "OakChooser.h"

@class OakDocument;

@interface FileChooser : OakChooser
@property (class, readonly) FileChooser* sharedInstance;

@property (nonatomic) NSString* path;
@property (nonatomic) NSUUID* currentDocument;
@property (nonatomic) NSUInteger sourceIndex;
@end
