// Hand-declared (rule 23): this class is defined in AboutWindowController.swift.
//
// It must not appear in TextMate-Bridging-Header.h, where it would collide with
// the generated TextMate-Swift.h (rule 43). AppController.mm is its only
// consumer.
@interface AboutWindowController : NSWindowController
@property (class, readonly) AboutWindowController* sharedInstance;
+ (void)showChangesIfUpdated;
- (void)showAboutWindow:(id)sender;
- (void)showChangesWindow:(id)sender;
@end
