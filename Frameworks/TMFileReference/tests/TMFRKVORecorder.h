// A KVO observer that records which key paths fired.
//
// In its own header, and defined rather than merely declared, because
// ide/gen_xctest.rb wraps each test file's body in `namespace <basename>` and
// ObjC declarations may only appear at global scope — but it hoists every
// #import to the top, so anything reached through one is fine.
//
// Only one test file includes this; if a second ever does, move the
// @implementation into a .mm of its own or the symbols will collide.
#import <Foundation/Foundation.h>

@interface TMFRKVORecorder : NSObject
@property (nonatomic, readonly) NSMutableArray<NSString*>* observed;
- (BOOL)sawKeyPath:(NSString*)keyPath;
- (void)reset;
@end

@implementation TMFRKVORecorder
- (instancetype)init
{
	if(self = [super init])
		_observed = [NSMutableArray array];
	return self;
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
	[_observed addObject:keyPath];
}

- (BOOL)sawKeyPath:(NSString*)keyPath
{
	return [_observed containsObject:keyPath];
}

- (void)reset
{
	[_observed removeAllObjects];
}
@end
