#import <TMBundleModel/TMBundleModelCxx.h>
#import <ns/ns.h>

// TMScopeContext exists so Swift can carry a scope::context_t it cannot spell.
// The interesting assertions are therefore about the values *not* collapsing
// into each other on the way across.

void test_scope_string_round_trips ()
{
	TMScopeContext* scope = [[TMScopeContext alloc] initWithString:@"source.ruby meta.function.ruby"];
	OAK_ASSERT_EQ(to_s(scope.stringValue), "source.ruby meta.function.ruby");
	OAK_ASSERT_EQ(to_s(scope.cxxContext.right), "source.ruby meta.function.ruby");
}

// The wildcard and the empty scope are both "no particular scope" to a reader,
// and conflating them is the plausible mistake: the wildcard matches every
// selector, the empty scope matches almost none. BundleMenuDelegate falls back
// to the empty one, so a bundle menu built with the wildcard by accident would
// silently list every item in the index.
void test_wildcard_and_empty_are_different_scopes ()
{
	scope::selector_t const selector("source.ruby");

	OAK_ASSERT(selector.does_match(TMScopeContext.wildcardScope.cxxContext).has_value());
	OAK_ASSERT(!selector.does_match(TMScopeContext.emptyScope.cxxContext).has_value());
}

// No responder answers -scopeContext inside a test bundle, so this exercises the
// fallback branch — which must be the empty scope, not the wildcard, for the
// reason above.
void test_current_scope_falls_back_to_empty ()
{
	scope::selector_t const selector("source.ruby");
	OAK_ASSERT(!selector.does_match(TMScopeContext.currentScope.cxxContext).has_value());
}
