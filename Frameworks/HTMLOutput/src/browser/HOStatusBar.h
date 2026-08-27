// Hand-declared (rule 23): this class is defined in HOStatusBar.swift.
//
// It must not appear in HTMLOutput-Bridging-Header.h, where it would collide with
// the generated HTMLOutput-Swift.h (rule 43).
@protocol HOStatusBarDelegate
- (void)goBack:(id)sender;
- (void)goForward:(id)sender;
@end

@interface HOStatusBar : NSVisualEffectView
@property (nonatomic, weak) id              delegate;

@property (nonatomic) NSString*             statusText;
@property (nonatomic) CGFloat               progress;
@property (nonatomic, getter = isBusy) BOOL busy;
@property (nonatomic) BOOL                  canGoBack;
@property (nonatomic) BOOL                  canGoForward;
@end
