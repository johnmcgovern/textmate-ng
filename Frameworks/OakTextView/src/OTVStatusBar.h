// Hand-declared (rule 23): this class is defined in OTVStatusBar.swift.
//
// OakDocumentView.mm is the sole consumer; it constructs the bar, adopts
// OTVStatusBarDelegate and drives the eight properties below.
//
// This file must not appear in OakTextView-Bridging-Header.h, where it would
// collide with the generated OakTextView-Swift.h (rule 43). The delegate protocol
// lives in its own header for that reason — Swift needs it, this does not.
#import "OTVStatusBarDelegate.h"

@interface OTVStatusBar : NSVisualEffectView
- (void)showBundlesMenu:(id)sender;
@property (nonatomic) NSString* selectionString;
@property (nonatomic) NSString* grammarName;
@property (nonatomic) NSString* symbolName;
@property (nonatomic) NSString* fileType; // This will update grammarName
@property (nonatomic, getter = isRecordingMacro) BOOL recordingMacro;
@property (nonatomic) BOOL softTabs;
@property (nonatomic) NSUInteger tabSize;

@property (nonatomic, weak) id <OTVStatusBarDelegate> delegate;
@property (nonatomic, weak) id target;
@end
