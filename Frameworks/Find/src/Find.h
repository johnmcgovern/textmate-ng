// The Find window's public interface. Unchanged for consumers — AppController,
// DocumentWindowController and OakTextView import this header and see the same
// class, the same properties and the same delegate protocol they always did.
//
// Two things moved underneath it. `Find` itself is implemented in Find.swift
// (`@objc(Find)`), so this declaration is hand-written rather than generated —
// the pattern TMFileReference established and FFResultNode repeated. And
// FindMatch, FFSearchTarget and FindDelegate moved to FindTypes.h so the Swift
// bridging header can import *them* without also importing this file, which
// would declare the class a second time. FindTypes.h is exported alongside this
// header, and imported here, so `#import <Find/Find.h>` still yields everything.
#import <OakFoundation/OakFindProtocol.h>

// Quoted, not <Find/FindTypes.h>: a target's farm include dirs are its
// *dependencies'* headers, never its own, so the angle form does not resolve
// while compiling this framework. The quoted form works from both sides — the
// two headers sit next to each other in src/ and are symlinked next to each
// other in the farm. Same arrangement as BundlesManager.h → Bundle.h and
// OakDocumentView.h → OakTextView.h.
#import "FindTypes.h"

@interface Find : NSWindowController
@property (class, readonly) Find* sharedInstance;

@property (nonatomic) FFSearchTarget searchTarget;

@property (nonatomic, weak) id <FindDelegate> delegate;
@property (nonatomic) NSString* projectFolder;
@property (nonatomic) NSArray* fileBrowserItems;
@property (nonatomic) NSUUID* documentIdentifier;

@property (nonatomic, readonly, getter = isVisible) BOOL visible;

@property (nonatomic) NSArray<FindMatch*>* findMatches;
- (IBAction)showFolderSelectionPanel:(id)sender;
- (IBAction)takeFindOptionToToggleFrom:(id)sender;
@end
