// Stays Objective-C, permanently.
//
// This is an NSProxy that forwards every message to its target inside an
// NSAnimationContext group with implicit animation enabled — the trick that
// lets `someTabView.animator.frame = …` animate. Swift cannot express it at
// either end: NSProxy is not an NSObject subclass, and -forwardInvocation:
// requires NSInvocation, which Swift cannot import at all.
//
// Found while porting OakTabBarView (2026-07-28). It is also why
// ide/coupling_survey.py grew an `objc` column: the survey measured C++
// coupling and scored this framework a clean 3, missing a construct that is
// just as impossible for Swift as a C++ virtual subclass.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface OakAnimatorProxy : NSProxy
- (instancetype)initWithRealObject:(id)realObject;
@property (nonatomic) id realObject;
@end

NS_ASSUME_NONNULL_END
