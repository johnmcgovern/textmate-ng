// The encoding::type side of the box. Kept out of OakSavePanelSupport.h so that
// header can go in a bridging header; this one can never (rule 17).
#import "OakSavePanelSupport.h"
#import <file/encoding.h>

@interface OakEncodingOptions (Cxx)
+ (instancetype)optionsWithCxxEncoding:(encoding::type const&)encoding;
- (encoding::type)cxxEncoding;
@end
