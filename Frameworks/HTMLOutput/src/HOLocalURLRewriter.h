// The one part of the scheme handler that stays ObjC++.
//
// Rule 20: its carry is a `std::string` ivar — state, not a parameter — and a
// category can add methods to a Swift class but never storage. It is also the
// right shape as it is: bytes in, bytes out, with the partial match held back.
//
// NSData rather than NSString throughout: this is a byte stream and a chunk
// boundary can fall inside a UTF-8 sequence, so going through text would corrupt
// exactly the case the carry exists to handle. Pinned by t_local_url_rewriter.mm.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface HOLocalURLRewriter : NSObject
- (NSData*)rewriteChunk:(NSData*)chunk;
@property (nonatomic, readonly) NSData* carry;
@end

NS_ASSUME_NONNULL_END
