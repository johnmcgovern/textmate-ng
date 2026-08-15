// Hand-written ObjC declaration of OFBFinderTagsChooser, which is implemented in
// OFBFinderTagsChooser.swift (Phase 4).
//
// FileBrowserViewController.mm builds one as a menu item's view, sets its
// target/action, and reads chosenTag / removeChosenTag when the action fires; it
// imports this header unchanged. It must never reach the Swift bridging header —
// it declares a class Swift defines.
//
// Nothing checks this against the Swift at build time; a drift is an
// unrecognized selector at runtime, which is what t_ofb_finder_tags_chooser.mm
// guards.
#import <Cocoa/Cocoa.h>

@class OakFinderTag;

@interface OFBFinderTagsChooser : NSView
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;
@property (nonatomic) OakFinderTag* chosenTag;
@property (nonatomic, readonly) BOOL removeChosenTag;
+ (OFBFinderTagsChooser*)finderTagsChooserWithSelectedTags:(NSArray<OakFinderTag*>*)selectedTags andSelectedTagsToRemove:(NSArray<OakFinderTag*>*)selectedTagsToRemove forMenu:(NSMenu*)aMenu;
@end
