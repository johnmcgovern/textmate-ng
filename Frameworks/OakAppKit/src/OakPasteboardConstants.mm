#import "OakPasteboardConstants.h"

// Definitions moved verbatim from OakPasteboard.mm (rule 6). Kept in ObjC so they
// survive OakPasteboard.mm becoming Swift (rule 19).

NSNotificationName const OakPasteboardDidChangeNotification = @"OakClipboardDidChangeNotification";

NSString* const kUserDefaultsFindWrapAround        = @"findWrapAround";
NSString* const kUserDefaultsFindIgnoreCase        = @"findIgnoreCase";

NSString* const OakFindIgnoreWhitespaceOption      = @"ignoreWhitespace";
NSString* const OakFindFullWordsOption             = @"fullWordMatch";
NSString* const OakFindRegularExpressionOption     = @"regularExpression";
