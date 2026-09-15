// Hand-declared (rule 23): this class is defined in EncodingView.swift.
//
// It must stay out of this framework's bridging header, where it would collide
// with the generated document-Swift.h (rule 43). Its one consumer,
// OakDocument.mm, imports it unchanged. Nothing checks this file against the
// Swift at build time; the selectors are pinned by tests/t_encoding_view.mm
// (rule 18).
@interface EncodingWindowController : NSWindowController
- (instancetype)initWithData:(NSData*)data;
- (void)beginSheetModalForWindow:(NSWindow*)aWindow completionHandler:(void(^)(NSModalResponse))callback;
@property (nonatomic) NSString* encoding;
@property (nonatomic, readonly) NSString* encodingNoBOM; // Same as encoding except there will never be a //BOM modifier
@property (nonatomic) NSString* displayName;
@property (nonatomic) BOOL acceptableEncoding;
@property (nonatomic) BOOL trainClassifier;
@end
