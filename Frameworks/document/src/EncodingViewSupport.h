// The one C++ fragment of EncodingWindowController, kept in ObjC++ so the rest
// of EncodingView can be Swift (rule 25).
//
// Transcodes the bytes from the chosen encoding and builds the preview: every
// line holding a byte above 0x7F gets a background from its start, and each
// such character run gets one too — what the user reads to judge whether the
// encoding is right. Real C++ (text::transcode_t; rule 6, moved verbatim), with
// a C++-free signature so the bridging header can import this.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface EncodingViewSupport : NSObject
// nil when the encoding is unknown to the transcoder. `couldConvert` answers
// whether every byte decoded, which is what enables the Open button; the
// preview is built from at most `length` bytes.
+ (nullable NSAttributedString*)previewForData:(NSData*)data length:(NSUInteger)length encoding:(NSString*)encodeFrom couldConvert:(nullable BOOL*)couldConvert NS_SWIFT_NAME(preview(for:length:encoding:couldConvert:));
@end

NS_ASSUME_NONNULL_END
