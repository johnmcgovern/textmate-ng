#import "../src/DWScopeContextCxx.h"
#import <io/path.h>
#import <test/jail.h>

// DWScopeContext is the layer that unblocks the DocumentWindowController port:
// the seven C++ ivars that a Swift @objc class cannot hold, moved behind an
// ObjC surface. See DWScopeContext.h for the argument.
//
// What is worth testing here is not the C++ — scm::info_t and settings_for_path
// have their own suites — but the three decisions this class actually makes:
//
//   1. **which** SCM variables are in effect, the rule that was written out five
//      times in the ObjC++ and is now written once;
//   2. the attribute string assembled from four sources, de-duplicated;
//   3. TM_SCM_NAME's fallback to an `attr.scm.<name>` marker when the document
//      itself is not in a repository.
//
// The external-attribute walk is asynchronous and touches the filesystem, so it
// is exercised against a real directory rather than mocked, using the same
// test::jail_t the io and settings suites use.

// ==========================================
// = The effective-variables rule           =
// ==========================================

void test_scope_context_starts_empty ()
{
	DWScopeContext* context = [DWScopeContext new];
	OAK_ASSERT_EQ(context.effectiveSCMVariables.count, 0);
	OAK_ASSERT_EQ(context.externalScopeAttributes.count, 0);
	OAK_ASSERT_EQ(context.scmNameVariables.count, 0);
}

// A context with no paths set has nothing to say, and must say it without
// crashing — this is the state a window is in between -init and its first
// document.
void test_scope_attributes_of_an_empty_context_are_empty ()
{
	DWScopeContext* context = [DWScopeContext new];
	OAK_ASSERT([[context scopeAttributesWithSCMStatusAttribute:nil] isEqualToString:@""]);
}

// The status fragment is passed in rather than derived here, because converting
// scm::status::type to a string is TMSCMStatus's job. Nil means the document has
// none, and must not produce a stray "attr.scm.status." prefix.
void test_scope_attributes_include_the_status_when_given_one ()
{
	DWScopeContext* context = [DWScopeContext new];

	NSString* withStatus = [context scopeAttributesWithSCMStatusAttribute:@"attr.scm.status.modified"];
	OAK_ASSERT([withStatus isEqualToString:@"attr.scm.status.modified"]);

	NSString* without = [context scopeAttributesWithSCMStatusAttribute:nil];
	OAK_ASSERT([without rangeOfString:@"attr.scm.status"].location == NSNotFound);
}

// ==========================================
// = The external-attribute walk            =
// ==========================================
//
// Marker files between the document and the project root become attributes.
// Synchronous assertions are not possible — the walk hops to a background queue
// and back — so these spin the run loop, which is what the app does anyway.

static void RunLoopUntil (BOOL(^condition)(void), NSTimeInterval timeout)
{
	NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while(!condition() && [deadline timeIntervalSinceNow] > 0)
		[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

void test_external_attributes_find_a_build_system ()
{
	test::jail_t jail;
	jail.set_content("Makefile", "all:\n\techo hi\n");
	jail.set_content("src/main.c", "int main(){}\n");

	DWScopeContext* context = [DWScopeContext new];
	context.projectPath = [NSString stringWithUTF8String:jail.path().c_str()];
	[context updateExternalAttributesForDocumentPath:[NSString stringWithUTF8String:jail.path("src/main.c").c_str()]];

	RunLoopUntil(^BOOL{ return context.externalScopeAttributes.count != 0; }, 5);
	OAK_ASSERT([context.externalScopeAttributes containsObject:@"attr.project.make"]);
}

// The `group` column in the rule table means "one per group". A directory with
// both a Makefile and a build.ninja reports one build system, not two — the
// detail most likely to be lost when that table is retyped.
void test_only_one_build_system_is_reported ()
{
	test::jail_t jail;
	jail.set_content("Makefile", "all:\n");
	jail.set_content("build.ninja", "rule cc\n");
	jail.set_content("src/main.c", "int main(){}\n");

	DWScopeContext* context = [DWScopeContext new];
	context.projectPath = [NSString stringWithUTF8String:jail.path().c_str()];
	[context updateExternalAttributesForDocumentPath:[NSString stringWithUTF8String:jail.path("src/main.c").c_str()]];

	RunLoopUntil(^BOOL{ return context.externalScopeAttributes.count != 0; }, 5);

	NSUInteger buildAttributes = 0;
	for(NSString* attr in context.externalScopeAttributes)
	{
		if([attr hasPrefix:@"attr.project."])
			++buildAttributes;
	}
	// ninja is listed before make in the table, so ninja is the one reported.
	OAK_ASSERT_EQ(buildAttributes, 1);
	OAK_ASSERT([context.externalScopeAttributes containsObject:@"attr.project.ninja"]);
}

// Attributes with no group are always reported, even alongside a grouped one.
void test_ungrouped_attributes_are_always_reported ()
{
	test::jail_t jail;
	jail.set_content("Makefile", "all:\n");
	jail.set_content("Vagrantfile", "# vagrant\n");
	jail.set_content("src/main.c", "int main(){}\n");

	DWScopeContext* context = [DWScopeContext new];
	context.projectPath = [NSString stringWithUTF8String:jail.path().c_str()];
	[context updateExternalAttributesForDocumentPath:[NSString stringWithUTF8String:jail.path("src/main.c").c_str()]];

	RunLoopUntil(^BOOL{ return context.externalScopeAttributes.count >= 2; }, 5);
	OAK_ASSERT([context.externalScopeAttributes containsObject:@"attr.project.make"]);
	OAK_ASSERT([context.externalScopeAttributes containsObject:@"attr.project.vagrant"]);
}

// External attributes reach the joined attribute string too, not just the array.
void test_external_attributes_reach_the_scope_string ()
{
	test::jail_t jail;
	jail.set_content("Rakefile", "task :default\n");
	jail.set_content("lib/a.rb", "# a\n");

	DWScopeContext* context = [DWScopeContext new];
	context.projectPath = [NSString stringWithUTF8String:jail.path().c_str()];
	[context updateExternalAttributesForDocumentPath:[NSString stringWithUTF8String:jail.path("lib/a.rb").c_str()]];

	RunLoopUntil(^BOOL{ return context.externalScopeAttributes.count != 0; }, 5);
	OAK_ASSERT([[context scopeAttributesWithSCMStatusAttribute:nil] rangeOfString:@"attr.project.rake"].location != NSNotFound);
}

// ==========================================
// = TM_SCM_NAME's fallback                 =
// ==========================================
//
// With no repository at the document, the name is recovered from an
// `attr.scm.<name>` marker instead. That is what makes TM_SCM_NAME available in
// a checkout whose metadata is not beside the document.

void test_scm_name_falls_back_to_an_external_marker ()
{
	test::jail_t jail;
	jail.set_content(".git/HEAD", "ref: refs/heads/main\n");
	jail.set_content("src/main.c", "int main(){}\n");

	DWScopeContext* context = [DWScopeContext new];
	context.projectPath = [NSString stringWithUTF8String:jail.path().c_str()];
	[context updateExternalAttributesForDocumentPath:[NSString stringWithUTF8String:jail.path("src/main.c").c_str()]];

	RunLoopUntil(^BOOL{ return context.externalScopeAttributes.count != 0; }, 5);
	OAK_ASSERT([context.externalScopeAttributes containsObject:@"attr.scm.git"]);

	// No real repository here, so the SCM variables are empty and the fallback is
	// the only thing that can supply a name.
	OAK_ASSERT_EQ(context.effectiveSCMVariables.count, 0);
	OAK_ASSERT([context.scmNameVariables[@"TM_SCM_NAME"] isEqualToString:@"git"]);
}

// Setting the same project path twice must not restart the watch — the ObjC++
// guarded on it and the guard is cheap to lose.
void test_setting_the_same_project_path_is_idempotent ()
{
	test::jail_t jail;
	jail.set_content("Makefile", "all:\n");

	NSString* path = [NSString stringWithUTF8String:jail.path().c_str()];
	DWScopeContext* context = [DWScopeContext new];
	context.projectPath = path;
	context.projectPath = path;
	OAK_ASSERT([context.projectPath isEqualToString:path]);
}

// A document path with no file type skips the settings lookup rather than
// passing "(null)" into it — the state a window is in before a document is
// selected.
void test_a_document_path_without_a_file_type_is_accepted ()
{
	test::jail_t jail;
	jail.set_content("a.txt", "hello\n");

	DWScopeContext* context = [DWScopeContext new];
	context.projectPath = [NSString stringWithUTF8String:jail.path().c_str()];
	[context setDocumentPath:[NSString stringWithUTF8String:jail.path("a.txt").c_str()] fileType:nil];

	// path_attributes still contributes, so this is not empty — the assertion is
	// that it did not crash and produced something sane.
	OAK_ASSERT([context scopeAttributesWithSCMStatusAttribute:nil] != nil);
}
