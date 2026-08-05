// A KVO observer that records which key paths fired.
//
// A near-copy of TMFileReference's TMFRKVORecorder rather than a shared one, and
// deliberately: that header *defines* its class, so two test files including one
// copy would collide at link time — its own comment says so. Duplicating twelve
// lines is cheaper than inventing a shared test-support target for them.
//
// In its own header, and defined rather than merely declared, because
// ide/gen_xctest.rb wraps each test file's body in `namespace <basename>` and
// ObjC declarations may only appear at global scope — but it hoists every
// #import to the top, so anything reached through one is fine.
//
// Only one test file in this framework may include this.
#import <Foundation/Foundation.h>

@interface FFKVORecorder : NSObject
@property (nonatomic, readonly) NSMutableArray<NSString*>* observed;
- (BOOL)sawKeyPath:(NSString*)keyPath;
@end

@implementation FFKVORecorder
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
@end
