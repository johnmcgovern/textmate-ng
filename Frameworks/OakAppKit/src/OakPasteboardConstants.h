// The externally-consumed OakPasteboard constants, split out ahead of the Swift
// port. Swift cannot *export* an `extern NSString* const` (rule 19), so these have
// to keep an ObjC home once OakPasteboard.mm becomes OakPasteboard.swift; consumers
// (Find.swift, AppController, clipboard.mm, WKWebView Additions, the chooser) go on
// seeing them unchanged, whether through this header or the bridging header.
//
// Only the six that cross the framework boundary moved here. The clipboard-history
// and pasteboard-type names used only inside OakPasteboard stay with it and become
// Swift `let`s at translation time.
//
// C++-free, so a Swift bridging header can import it.
#import <Foundation/Foundation.h>

extern NSNotificationName const OakPasteboardDidChangeNotification;

extern NSString* const kUserDefaultsFindWrapAround;
extern NSString* const kUserDefaultsFindIgnoreCase;

extern NSString* const OakFindIgnoreWhitespaceOption;
extern NSString* const OakFindFullWordsOption;
extern NSString* const OakFindRegularExpressionOption;
