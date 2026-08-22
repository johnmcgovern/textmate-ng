// Hand-declared (rule 23): OakSavePanel is defined in OakSavePanel.swift.
//
// The class method below is *not* — it is in OakSavePanelCxx.mm, because
// `encoding::type` appears in its completion block's parameter list and rule 15
// makes such a method uncallable from Swift. That is the whole reason this file
// still carries a C++ include, and why it must not appear in OakAppKit's own
// bridging header.
//
// Imported by OakDocument.mm and DocumentWindowSupport.mm, which pass and receive
// encoding::type on both sides of the call.
#import <file/encoding.h>

@interface OakSavePanel : NSObject
@end

@interface OakSavePanel (Cxx)
+ (void)showWithPath:(NSString*)aPathSuggestion directory:(NSString*)aDirectorySuggestion fowWindow:(NSWindow*)aWindow encoding:(encoding::type const&)encoding fileType:(NSString*)aFileType completionHandler:(void(^)(NSString* path, encoding::type const& encoding))aCompletionHandler;
@end
