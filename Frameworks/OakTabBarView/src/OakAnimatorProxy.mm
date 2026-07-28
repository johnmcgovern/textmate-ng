#import "OakAnimatorProxy.h"

@implementation OakAnimatorProxy
- (instancetype)initWithRealObject:(id)realObject
{
	_realObject = realObject;
	return self;
}

- (void)forwardInvocation:(NSInvocation*)anInvocation
{
	[NSAnimationContext runAnimationGroup:^(NSAnimationContext* context){
		context.allowsImplicitAnimation = YES;
		[anInvocation setTarget:_realObject];
		[anInvocation invoke];
	} completionHandler:^{
	}];
}

- (NSMethodSignature*)methodSignatureForSelector:(SEL)aSelector
{
	return [_realObject methodSignatureForSelector:aSelector];
}
@end
