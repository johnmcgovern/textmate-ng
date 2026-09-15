// The C++-free part of OakDocument's private surface (rule 11): what
// OakDocumentController needs — the path initializer and the untitled number —
// declared where a bridging header can import it. `OakDocument Private.h`
// imports this and adds the C++ (the buffer and undo manager references).
#import "OakDocument.h"

@interface OakDocument (Internal)
- (instancetype)initWithPath:(NSString*)aPath;

@property (nonatomic) NSUInteger  untitledCount;
@property (nonatomic) NSString*   folded;
@end
