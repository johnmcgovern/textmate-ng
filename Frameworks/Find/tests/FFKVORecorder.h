// A KVO observer that records which key paths fired.
//
// A near-copy of TMFileReference's TMFRKVORecorder rather than a shared one:
// duplicating twelve lines is cheaper than inventing a shared test-support
// target, and `tests tests/*.mm` would try to make a suite out of one anyway.
//
// In its own header, and defined rather than merely declared, because
// ide/gen_xctest.rb wraps each test file's body in `namespace <basename>` and
// ObjC declarations may only appear at global scope — but it hoists every
// #import to the top, so anything reached through one is fine.
//
// **Two test files in this framework include it, and that is safe** —
// contradicting TMFRKVORecorder.h's warning that a second includer would collide
// at link. gen_xctest.rb emits every file's bodies into a *single* _impl.mm, and
// `#import` is idempotent within a translation unit, so there is only ever one
// copy of the @implementation. Checked by doing it, not by reasoning: the second
// includer was added on 2026-08-05 and the bundle links.
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
