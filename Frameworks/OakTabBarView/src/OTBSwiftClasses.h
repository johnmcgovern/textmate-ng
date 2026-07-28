// Hand-written ObjC declarations for the classes this framework implements in
// Swift, for use by its own ObjC++ (OakTabBarView.mm).
//
// The generated OakTabBarView-Swift.h cannot be imported there — module name and
// ObjC class name collide, see OakTabBarView-Bridging-Header.h. Keep these in
// step with the Swift definitions by hand; nothing checks them at build time, so
// a mismatch surfaces as an unrecognized selector at runtime.
@class OakTabView;

// OakTabItem.swift — the tab model and drag payload.
@interface OakTabItem : NSObject <NSPasteboardWriting>
@property (class, nonatomic, readonly) NSPasteboardType pasteboardType;
@property (nonatomic, readonly) NSString* identifier;
@property (nonatomic) NSString* title;
@property (nonatomic) NSString* path;
@property (nonatomic, getter = isModified) BOOL modified;
@property (nonatomic, getter = isSelected) BOOL selected;
@property (nonatomic) CGFloat fittingWidth;
@property (nonatomic) BOOL needsLayout;
@property (nonatomic, weak) OakTabView* tabView;
- (instancetype)initWithTitle:(NSString*)aTitle path:(NSString*)aPath identifier:(NSString*)anIdentifier modified:(BOOL)flag;
+ (instancetype)tabItemWithTitle:(NSString*)aTitle path:(NSString*)aPath identifier:(NSString*)anIdentifier modified:(BOOL)flag;
+ (instancetype)tabItemFromPasteboardItem:(NSPasteboardItem*)pasteboardItem;
@end

// OakBox.swift — flat solid-colour view.
@interface OakBox : NSView
@property (nonatomic) NSColor* fillColor;
@end
