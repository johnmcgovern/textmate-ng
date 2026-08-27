// Hand-declared (rule 23): this class is defined in OTVHUD.swift.
//
// It must not appear in OakTextView-Bridging-Header.h, where it would collide
// with the generated OakTextView-Swift.h (rule 43).
#import <oak/debug.h>

@interface OTVHUD : NSWindowController
+ (OTVHUD*)showHudForView:(NSView*)aView withText:(NSString*)someText;
@end
