#import "OakSavePanelCxx.h"
#import "OakAppKit-Swift.h" // OakSavePanel, which is defined in Swift

// The one method that cannot be Swift, and the reason is rule 15 rather than
// anything about the panel: `encoding::type` appears in the *completion block's*
// parameter list, which makes the whole method uncallable from Swift no matter
// how it is spelled. Both callers (OakDocument.mm, DocumentWindowSupport.mm) rely
// on exactly this signature.
//
// The category is redeclared here rather than imported from OakSavePanel.h,
// because that header also hand-declares the class and would collide with the
// generated OakAppKit-Swift.h (rule 43). It is the same declaration; the header
// is the copy external consumers see.

@interface OakSavePanel (CxxImplementation)
+ (void)showWithPath:(NSString*)aPathSuggestion directory:(NSString*)aDirectorySuggestion fowWindow:(NSWindow*)aWindow encoding:(encoding::type const&)encoding fileType:(NSString*)aFileType completionHandler:(void(^)(NSString* path, encoding::type const& encoding))aCompletionHandler;
@end

@implementation OakSavePanel (CxxImplementation)
+ (void)showWithPath:(NSString*)aPathSuggestion directory:(NSString*)aDirectorySuggestion fowWindow:(NSWindow*)aWindow encoding:(encoding::type const&)encoding fileType:(NSString*)aFileType completionHandler:(void(^)(NSString* path, encoding::type const& encoding))aCompletionHandler
{
	[OakSavePanel showWithPath:aPathSuggestion directory:aDirectorySuggestion fowWindow:aWindow options:[OakEncodingOptions optionsWithCxxEncoding:encoding] fileType:aFileType completionHandler:^(NSString* path, OakEncodingOptions* chosen){
		aCompletionHandler(path, [chosen cxxEncoding]);
	}];
}
@end
