#import <oak/misc.h>
#import "OakTabBarViewProtocols.h"

// OakTabBarView is implemented in Swift (@objc(OakTabBarView), see
// OakTabBarView.swift). This header is hand-written and stays the framework's
// public ObjC surface — the same pattern as Preferences.h — because the module
// name equals the class name and the generated *-Swift.h cannot be exported
// through the include farm. Keep it in step with the Swift class by hand.
@interface OakTabBarView : NSView
@property (nonatomic, weak) id <OakTabBarViewDelegate> delegate;
@property (nonatomic, weak) id <OakTabBarViewDataSource> dataSource;
@property (nonatomic, readonly) NSInteger countOfVisibleTabs;
@property (nonatomic) NSUInteger selectedTabIndex;
- (void)reloadData;
- (void)performClose:(id)sender;

@property (nonatomic) BOOL neverHideLeftBorder;
@end
