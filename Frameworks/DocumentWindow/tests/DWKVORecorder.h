// A KVO observer that registers itself and records the values it was handed.
//
// A near-relative of Find's FFKVORecorder and TMFileReference's TMFRKVORecorder
// rather than a shared one: duplicating twenty lines is cheaper than inventing a
// shared test-support target, and `tests tests/t_*.mm` would try to make a suite
// out of it anyway. This one differs from Find's in keeping the *values* as well
// as the key paths, because what these tests assert is that a derived string
// recomputed — not merely that something fired.
//
// Defined rather than merely declared, and in a header, because
// ide/gen_xctest.rb wraps each test file's body in `namespace <basename>` and
// ObjC declarations may only appear at global scope — but it hoists every
// #import to the top. Several test files may include it: gen_xctest.rb emits all
// bodies into a single _impl.mm and `#import` is idempotent within a translation
// unit, so there is only ever one @implementation. Find checked that by doing it.
#import <Foundation/Foundation.h>

@interface DWKVORecorder : NSObject
@property (nonatomic, readonly) NSMutableArray* values;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) id lastValue;
- (instancetype)initWithObject:(id)anObject keyPath:(NSString*)aKeyPath;
- (void)stop;
@end

@implementation DWKVORecorder
{
	__weak id _object;
	NSString* _keyPath;
	BOOL      _observing;
}

- (instancetype)initWithObject:(id)anObject keyPath:(NSString*)aKeyPath
{
	if(self = [super init])
	{
		_values    = [NSMutableArray array];
		_object    = anObject;
		_keyPath   = aKeyPath;
		_observing = YES;
		[anObject addObserver:self forKeyPath:aKeyPath options:NSKeyValueObservingOptionNew context:NULL];
	}
	return self;
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
	id value = change[NSKeyValueChangeNewKey];
	[_values addObject:value ?: [NSNull null]];
}

- (NSUInteger)count { return _values.count; }
- (id)lastValue     { id res = _values.lastObject; return res == [NSNull null] ? nil : res; }

// Explicit rather than in -dealloc: an observer still registered when its target
// dies is a hard crash, and a test that forgets to stop should fail loudly at the
// point of the mistake rather than at some later teardown.
- (void)stop
{
	if(_observing)
	{
		[_object removeObserver:self forKeyPath:_keyPath];
		_observing = NO;
	}
}
@end
