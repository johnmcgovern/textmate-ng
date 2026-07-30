// An opaque box around scope::context_t (Phase 4).
//
// Swift cannot express scope::context_t and does not need to: every consumer
// only ever *obtains* a scope and *passes it back* into a bundles:: query. So
// this class carries the value across the boundary without ever spelling it,
// which is what lets TMBundleItem.h stay free of C++.
//
// The scope itself comes from OakTextView's -scopeContext, a C++-typed selector
// that keeps OakTextView permanently ObjC++ (roadmap Phase 4). +currentScope is
// the [NSApp targetForAction:] lookup BundleMenuDelegate does inline today.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface TMScopeContext : NSObject <NSCopying>

// The scope of whatever currently answers -scopeContext in the responder chain,
// or +wildcardScope when nothing does.
@property (class, nonatomic, readonly) TMScopeContext* currentScope;

// scope::wildcard — matches every scope selector.
@property (class, nonatomic, readonly) TMScopeContext* wildcardScope;

// The empty scope. This is what BundleMenuDelegate falls back to, and it is NOT
// the same as +wildcardScope: an empty scope matches only selectors that accept
// it, where the wildcard matches all of them.
@property (class, nonatomic, readonly) TMScopeContext* emptyScope;

- (instancetype)initWithString:(NSString*)scopeString;

@property (nonatomic, readonly) NSString* stringValue;

@end

NS_ASSUME_NONNULL_END
