// The strip that slides down from the top of a document offering to install the
// bundle that would syntax-highlight it.
//
// The response enum moved to SelectGrammarResponse.h so the Swift bridging
// header can import it without importing this file, which declares a class the
// Swift defines. This header re-imports it, so nothing that includes this one
// changed.
#import "SelectGrammarResponse.h"

@class BundleGrammar;
@class OakDocumentView;

@interface SelectGrammarViewController : NSViewController
@property (nonatomic) NSString* documentDisplayName;
- (void)showGrammars:(NSArray<BundleGrammar*>*)grammars forView:(OakDocumentView*)documentView completionHandler:(void(^)(SelectGrammarResponse, BundleGrammar*))callback;
- (void)dismiss;
@end
