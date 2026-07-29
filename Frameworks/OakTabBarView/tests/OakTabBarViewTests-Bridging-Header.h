// Bridging header for the OakTabBarViewTests bundle.
//
// OakTabBarView and OakTabItem are implemented in Swift but are internal to the
// OakTabBarView module, so the test bundle cannot `import OakTabBarView`. It does
// not need to: the classes are @objc-named, the bundle links libOakTabBarView.a,
// and -ObjC force-loads the archive's ObjC metadata, so a hand-written ObjC
// declaration is enough to drive them from Swift.
//
// Importing OakTabBarView.h is safe *here* precisely because it is unsafe inside
// the framework: there is no generated OakTabBarView-Swift.h in this target for
// the `namespace OakTabBarView` emission to collide with. That is what makes
// these tests worth having — the framework's public header is hand-written and
// nothing else checks it against the Swift implementation, so a drift between
// the two is an unrecognized selector at runtime. Here, it is a test failure.
#include "../../../Shared/PCH/prelude.cc"
#import <Cocoa/Cocoa.h>

#import "../src/OakTabBarView.h"

// OakTabItem has no header in the framework any more — nothing in production
// ObjC needs it since OakTabBarView.mm went away. Declared here so the drag
// payload's pasteboard contract can be tested; the test calling these is what
// verifies the declaration still matches the Swift.
//
// Nullability is annotated rather than left implicit for the reason the
// Preferences port recorded: an unannotated ObjC pointer imports as an
// implicitly-unwrapped optional, which decays to a plain Optional wherever the
// type is inferred — so `let item = OakTabItem(…)` would be `OakTabItem?` and
// every member access would need unwrapping.
//
// tabItemFromPasteboardItem: deliberately returns OakTabItem* and not
// instancetype: an instancetype class method whose name echoes the class is
// imported as an *initializer*, which is not the spelling under test here.
NS_ASSUME_NONNULL_BEGIN

@interface OakTabItem : NSObject <NSPasteboardWriting>
@property (class, nonatomic, readonly) NSPasteboardType pasteboardType;
@property (nonatomic, readonly, nullable) NSString* identifier;
@property (nonatomic, nullable) NSString* title;
@property (nonatomic, nullable) NSString* path;
@property (nonatomic, getter = isModified) BOOL modified;
@property (nonatomic, getter = isSelected) BOOL selected;
- (instancetype)initWithTitle:(nullable NSString*)aTitle path:(nullable NSString*)aPath identifier:(nullable NSString*)anIdentifier modified:(BOOL)flag;
+ (nullable OakTabItem*)tabItemFromPasteboardItem:(NSPasteboardItem*)pasteboardItem;
@end

NS_ASSUME_NONNULL_END
