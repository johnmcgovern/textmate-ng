#import "TMBundleModelCxx.h"
#import <OakFoundation/NSString Additions.h>
#import <ns/ns.h>

// OakTextView vends the current scope through this C++-typed selector, which is
// one of the reasons it stays ObjC++ permanently. Declared here so the lookup
// below compiles without importing OakTextView (TMBundleModel must not depend on
// the UI framework that happens to answer).
@interface NSObject (TMScopeContextProvider)
- (scope::context_t)scopeContext;
@end

@implementation TMScopeContext
{
	scope::context_t _context;
}

+ (TMScopeContext*)currentScope
{
	// Same lookup BundleMenuDelegate did inline. Note the empty-scope fallback
	// is deliberate and is *not* the wildcard: with no text view in the
	// responder chain, a bundle menu should show the items that apply to no
	// scope, not every item in the index.
	if(id provider = [NSApp targetForAction:@selector(scopeContext)])
		return [self scopeContextWithCxxContext:[provider scopeContext]];
	return self.emptyScope;
}

+ (TMScopeContext*)wildcardScope
{
	static TMScopeContext* res = [self scopeContextWithCxxContext:scope::wildcard];
	return res;
}

+ (TMScopeContext*)emptyScope
{
	static TMScopeContext* res = [self scopeContextWithCxxContext:scope::context_t()];
	return res;
}

+ (TMScopeContext*)scopeContextWithCxxContext:(scope::context_t const&)context
{
	TMScopeContext* res = [[TMScopeContext alloc] init];
	res->_context = context;
	return res;
}

- (instancetype)initWithString:(NSString*)scopeString
{
	if(self = [super init])
		_context = scope::context_t(to_s(scopeString));
	return self;
}

- (scope::context_t)cxxContext
{
	return _context;
}

- (NSString*)stringValue
{
	return [NSString stringWithCxxString:to_s(_context.right)] ?: @"";
}

- (id)copyWithZone:(NSZone*)zone
{
	return self; // immutable
}

- (NSString*)description
{
	return [NSString stringWithFormat:@"<%@: %@>", self.class, self.stringValue];
}

@end
