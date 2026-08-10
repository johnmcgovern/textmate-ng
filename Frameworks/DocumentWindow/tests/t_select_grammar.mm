#import "DocumentWindowTesting.h"
#import "DWKVORecorder.h"
#import <BundlesManager/Bundle.h>

// DocumentWindow's first tests. The framework had none — 3564 lines of ObjC++
// and zero coverage — which is the state Find was in on 2026-08-04, and these
// are written for the same reason and in the same order: against the ObjC++,
// before the port, so the port has something to be wrong against.
//
// SelectGrammarViewController is the smallest of the four files and the only one
// with no C++ at all. What is worth pinning in it is -labelString: three
// sentences chosen by which of two properties are set, and a KVO dependency
// declaring that both of them affect it. The sentence is what the user reads
// before deciding whether to install a bundle, and the dependency is what makes
// it update when the document changes underneath the strip.

static BundleGrammar* GrammarInBundleNamed (NSString* bundleName)
{
	Bundle* bundle = [[Bundle alloc] initWithIdentifier:[NSUUID UUID]];
	bundle.name = bundleName;

	BundleGrammar* grammar = [BundleGrammar new];
	grammar.bundle = bundle;
	return grammar;
}

// Asserted rather than assumed, the way Find's construction test is: this is a
// view controller with no nib, and everything below depends on being able to
// stand one up outside a bundled app.
void test_select_grammar_controller_is_constructible ()
{
	SelectGrammarViewController* controller = [SelectGrammarViewController new];
	OAK_ASSERT(controller != nil);
}

// The three branches of the decision table, which differ in more than wording:
// the first names the document, the second does not, and the third does not even
// name the bundle.
void test_label_string_names_both_the_bundle_and_the_document ()
{
	SelectGrammarViewController* controller = [SelectGrammarViewController new];
	controller.grammar             = GrammarInBundleNamed(@"Ruby");
	controller.documentDisplayName = @"rakefile.rb";

	NSString* label = controller.labelString;
	OAK_ASSERT([label rangeOfString:@"Ruby"].location != NSNotFound);
	OAK_ASSERT([label rangeOfString:@"rakefile.rb"].location != NSNotFound);
}

// A grammar with no document name still names the bundle — this is the branch
// reached before the document has a display name, and it must not print
// "(null)".
void test_label_string_without_a_document_name_still_names_the_bundle ()
{
	SelectGrammarViewController* controller = [SelectGrammarViewController new];
	controller.grammar = GrammarInBundleNamed(@"Ruby");

	NSString* label = controller.labelString;
	OAK_ASSERT([label rangeOfString:@"Ruby"].location != NSNotFound);
	OAK_ASSERT([label rangeOfString:@"(null)"].location == NSNotFound);
	OAK_ASSERT([label rangeOfString:@"this document"].location != NSNotFound);
}

// No grammar at all falls all the way through — note that a document name on its
// own does *not* reach the middle branch, because the condition tests the
// grammar first. Pinned because reading the ternary chain the other way round is
// the easy mistake.
void test_label_string_without_a_grammar_names_nothing ()
{
	SelectGrammarViewController* controller = [SelectGrammarViewController new];
	OAK_ASSERT([controller.labelString isEqualToString:@"Would you like to install additional support for this document?"]);

	controller.documentDisplayName = @"rakefile.rb";
	OAK_ASSERT([controller.labelString isEqualToString:@"Would you like to install additional support for this document?"]);
}

// The KVO dependency, and the reason this file exists at all. `labelString` is
// bound into the strip's label, so it has to recompute when either input moves.
// In Swift the two inputs must be `dynamic`, not merely `@objc` — the trap that
// has now caused two defects in this project. Writing this before the port makes
// that checkable instead of hoped for.
void test_label_string_declares_both_its_dependencies ()
{
	NSSet* keyPaths = [SelectGrammarViewController keyPathsForValuesAffectingValueForKey:@"labelString"];
	OAK_ASSERT([keyPaths containsObject:@"grammar"]);
	OAK_ASSERT([keyPaths containsObject:@"documentDisplayName"]);
}

// And the dependency actually firing, which the declaration above does not by
// itself guarantee: a Swift property that is `@objc` but not `dynamic` is
// written directly from Swift and the notification never happens.
void test_label_string_notifies_when_the_document_name_changes ()
{
	SelectGrammarViewController* controller = [SelectGrammarViewController new];
	controller.grammar = GrammarInBundleNamed(@"Ruby");

	DWKVORecorder* recorder = [[DWKVORecorder alloc] initWithObject:controller keyPath:@"labelString"];
	controller.documentDisplayName = @"rakefile.rb";
	OAK_ASSERT_EQ(recorder.count, 1);
	OAK_ASSERT([recorder.lastValue rangeOfString:@"rakefile.rb"].location != NSNotFound);

	[recorder stop];
}

void test_label_string_notifies_when_the_grammar_changes ()
{
	SelectGrammarViewController* controller = [SelectGrammarViewController new];

	DWKVORecorder* recorder = [[DWKVORecorder alloc] initWithObject:controller keyPath:@"labelString"];
	controller.grammar = GrammarInBundleNamed(@"Ruby");
	OAK_ASSERT_EQ(recorder.count, 1);
	OAK_ASSERT([recorder.lastValue rangeOfString:@"Ruby"].location != NSNotFound);

	[recorder stop];
}

// The button tags *are* the response values, which is what lets three buttons
// share one action. A sender with no tag falls back to NotNow — the safe answer,
// since it neither installs nor suppresses the offer forever.
void test_click_reports_the_senders_tag_as_the_response ()
{
	SelectGrammarViewController* controller = [SelectGrammarViewController new];

	__block SelectGrammarResponse reported = SelectGrammarResponseCount;
	__block BundleGrammar* reportedGrammar = nil;
	BundleGrammar* grammar = GrammarInBundleNamed(@"Ruby");

	// forView:nil is a message to nil in the ObjC++, and must stay harmless: the
	// strip is added to a document view it does not own.
	[controller showGrammars:@[ grammar ] forView:nil completionHandler:^(SelectGrammarResponse response, BundleGrammar* aGrammar){
		reported        = response;
		reportedGrammar = aGrammar;
	}];

	NSMenuItem* never = [NSMenuItem new];
	never.tag = SelectGrammarResponseNever;
	[controller didClickButton:never];

	OAK_ASSERT_EQ((NSInteger)reported, (NSInteger)SelectGrammarResponseNever);
	OAK_ASSERT(reportedGrammar == grammar);
}

void test_click_without_a_tag_reports_not_now ()
{
	SelectGrammarViewController* controller = [SelectGrammarViewController new];

	__block SelectGrammarResponse reported = SelectGrammarResponseCount;
	[controller showGrammars:@[ GrammarInBundleNamed(@"Ruby") ] forView:nil completionHandler:^(SelectGrammarResponse response, BundleGrammar* aGrammar){
		reported = response;
	}];

	// NSString does not respond to -tag, which is the guard's actual condition.
	[controller didClickButton:@"not a control"];
	OAK_ASSERT_EQ((NSInteger)reported, (NSInteger)SelectGrammarResponseNotNow);
}

// -showGrammars: takes an array and keeps only the first, so an empty array
// leaves the grammar nil rather than trapping — the state
// test_label_string_without_a_grammar_names_nothing describes.
void test_show_grammars_with_an_empty_array_leaves_no_grammar ()
{
	SelectGrammarViewController* controller = [SelectGrammarViewController new];
	[controller showGrammars:@[] forView:nil completionHandler:^(SelectGrammarResponse response, BundleGrammar* aGrammar){}];
	OAK_ASSERT(controller.grammar == nil);
}
