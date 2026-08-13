#import "DocumentWindowTesting.h"
#import <document/OakDocument.h>

// NOTE on the extra parentheses below: OAK_ASSERT is a one-argument macro and
// the preprocessor does not treat @[ ] as grouping, so a comma inside an array
// literal would split the argument. Wrapping the expression is the fix.
//
// The first tests against DocumentWindowController — the 2885-line window
// controller, and the largest single file left in the migration.
//
// Two things are being established here, in this order, because the second
// depends on the answer to the first:
//
//  1. **Is the controller constructible in a test process at all?** Its -init
//     stands up an OakDocumentView, which is the C++ text engine, a window, a
//     tab bar, an array controller and eight KVO registrations. Find's
//     controller turned out to be constructible and CrashReporter's did not, so
//     this is asserted rather than assumed — it decides whether the rest of this
//     framework's coverage can use instances.
//
//  2. **The tab-reordering subsequence test**, which is the one piece of real
//     algorithm in the file and the one most likely to be quietly rewritten.

void test_document_window_controller_is_constructible ()
{
	DocumentWindowController* controller = [DocumentWindowController new];
	OAK_ASSERT(controller != nil);
	OAK_ASSERT(controller.window != nil);
	OAK_ASSERT_EQ(controller.documents.count, 0);
}

// ==================================================================
// = -documentsHaveCommonSubsequence: the animation decision         =
// ==================================================================
//
// Asked before replacing the tab array: if the old and new orders share a
// consistent subsequence, the change is animated, because tabs appear to slide.
// If they do not, animation is suppressed, because tabs would appear to swap
// places at random.
//
// It is a **class** method rather than an instance one. In the ObjC++ it was an
// instance method that touched no instance state, and hoisting it is what lets
// these tests run whatever the answer to the constructibility question above.
// The port keeps that spelling — DocumentWindowTesting.h pins it.

static OakDocument* Doc (NSString* name)
{
	return [OakDocument documentWithString:@"" fileType:@"text.plain" customName:name];
}

void test_identical_orders_have_a_common_subsequence ()
{
	OakDocument* a = Doc(@"a"); OakDocument* b = Doc(@"b"); OakDocument* c = Doc(@"c");
	OAK_ASSERT(([DocumentWindowController documents:@[ a, b, c ] hasCommonSubsequenceWithDocuments:@[ a, b, c ]]));
}

// Nothing in common is vacuously consistent — there is no pair to disagree
// about, so the move animates.
void test_disjoint_orders_have_a_common_subsequence ()
{
	OakDocument* a = Doc(@"a"); OakDocument* b = Doc(@"b");
	OakDocument* x = Doc(@"x"); OakDocument* y = Doc(@"y");
	OAK_ASSERT(([DocumentWindowController documents:@[ a, b ] hasCommonSubsequenceWithDocuments:@[ x, y ]]));
	OAK_ASSERT(([DocumentWindowController documents:@[] hasCommonSubsequenceWithDocuments:@[ x, y ]]));
	OAK_ASSERT(([DocumentWindowController documents:@[ a, b ] hasCommonSubsequenceWithDocuments:@[]]));
}

// Documents added and removed around a stable core still animate: the shared
// documents appear in the same relative order in both lists.
void test_insertions_around_a_stable_core_keep_the_subsequence ()
{
	OakDocument* a = Doc(@"a"); OakDocument* b = Doc(@"b"); OakDocument* c = Doc(@"c");
	OakDocument* n = Doc(@"new");

	OAK_ASSERT(([DocumentWindowController documents:@[ a, b, c ] hasCommonSubsequenceWithDocuments:@[ n, a, b, c ]]));
	OAK_ASSERT(([DocumentWindowController documents:@[ a, b, c ] hasCommonSubsequenceWithDocuments:@[ a, b ]]));
}

// And the case the whole thing exists to catch: two shared documents whose
// relative order is reversed. Animating that reads as tabs teleporting.
void test_a_reversed_pair_has_no_common_subsequence ()
{
	OakDocument* a = Doc(@"a"); OakDocument* b = Doc(@"b");
	OAK_ASSERT((![DocumentWindowController documents:@[ a, b ] hasCommonSubsequenceWithDocuments:@[ b, a ]]));
}

// The loop advances i and j *unconditionally* at the end of each iteration, on
// top of whichever branch already advanced one of them — so a non-shared element
// moves its index by two, not one. That reads like a bug and is load-bearing:
// rewriting it as the obvious two-pointer walk changes which reorderings animate.
// This case is the one that distinguishes them.
void test_the_double_advance_is_preserved ()
{
	OakDocument* a = Doc(@"a"); OakDocument* b = Doc(@"b"); OakDocument* c = Doc(@"c");
	OakDocument* x = Doc(@"x");

	// `x` is in neither intersection position; the ObjC++ skips past `a` as well
	// on that iteration, and so never compares a against a.
	OAK_ASSERT(([DocumentWindowController documents:@[ x, a, b ] hasCommonSubsequenceWithDocuments:@[ a, b ]]));
	OAK_ASSERT(([DocumentWindowController documents:@[ a, b, c ] hasCommonSubsequenceWithDocuments:@[ c, b, a ]] == NO));
}

// ==================================================================
// = Sticky tabs                                                     =
// ==================================================================
//
// A sticky tab survives "close other tabs". The set is created lazily, so
// asking about a document before anything is sticky must answer NO rather than
// trap — the implicitly-unwrapped-optional trap this project hit on
// FFResultsViewController's outline view.

void test_no_document_is_sticky_by_default ()
{
	DocumentWindowController* controller = [DocumentWindowController new];
	OAK_ASSERT(![controller isDocumentSticky:Doc(@"a")]);
}

void test_sticky_round_trips ()
{
	DocumentWindowController* controller = [DocumentWindowController new];
	OakDocument* a = Doc(@"a");
	OakDocument* b = Doc(@"b");

	[controller setDocument:a sticky:YES];
	OAK_ASSERT([controller isDocumentSticky:a]);
	OAK_ASSERT(![controller isDocumentSticky:b]);

	[controller setDocument:a sticky:NO];
	OAK_ASSERT(![controller isDocumentSticky:a]);
}

// Un-sticking something that was never sticky must not create the set or throw —
// it is reachable from the Tabs menu before anything has been made sticky.
void test_unsticking_an_unknown_document_is_harmless ()
{
	DocumentWindowController* controller = [DocumentWindowController new];
	[controller setDocument:Doc(@"a") sticky:NO];
	OAK_ASSERT(![controller isDocumentSticky:Doc(@"a")]);
}

// ==================================================================
// = The ObjC selector surface the Swift port has to keep            =
// ==================================================================
//
// Written *after* the port, because the port lost a method and nothing caught
// it: -goToRelatedFile: was simply not carried across, and the whole suite
// stayed green because no test and no compiler check reaches an action method.
// It was found by opening the app and noticing the menu item was disabled.
//
// Two things make that failure mode easy to hit here, and both are silent:
//
//   * Action methods are looked up by selector through -targetForAction:. A
//     missing one is a greyed-out menu item, never a build error.
//   * OakTabBarViewDelegate is @optional. A delegate method whose Swift
//     spelling does not match the imported name still compiles — it just never
//     gets called, so the tab bar quietly loses its context menu or its
//     double-click behaviour.
//
// So this pins the surface by selector rather than by Swift signature: every
// action in DocumentWindowController.h, both tab-bar protocols, and the four
// C++-typed selectors that live on the ObjC++ category. -respondsToSelector: is
// the right check precisely because it is what AppKit itself does.

static void assert_responds (SEL selector)
{
	OAK_ASSERT([DocumentWindowController instancesRespondToSelector:selector]);
}

void test_document_window_controller_keeps_its_action_methods ()
{
	SEL const actions[] = {
		@selector(newFolder:), @selector(newDocumentInTab:), @selector(newDocumentInDirectory:),
		@selector(moveDocumentToNewWindow:), @selector(mergeAllWindows:),
		@selector(goToRelatedFile:), @selector(selectNextTab:), @selector(selectPreviousTab:),
		@selector(takeSelectedTabIndexFrom:), @selector(toggleSticky:),
		@selector(toggleHTMLOutput:), @selector(moveFocus:),
		@selector(performCloseTab:), @selector(performCloseSplit:), @selector(performCloseWindow:),
		@selector(performCloseAllTabs:), @selector(performCloseOtherTabsXYZ:),
		@selector(performCloseTabsToTheRight:), @selector(performCloseTabsToTheLeft:),
		@selector(saveDocument:), @selector(saveDocumentAs:), @selector(saveAllDocuments:),
		@selector(orderFrontFindPanel:), @selector(orderFrontRunCommandWindow:), @selector(goToFile:),
		@selector(toggleFileBrowser:), @selector(revealFileInProject:), @selector(goToProjectFolder:),
		@selector(goBack:), @selector(goForward:), @selector(goToParentFolder:),
		@selector(goToComputer:), @selector(goToHome:), @selector(goToDesktop:),
		@selector(goToFavorites:), @selector(goToSCMDataSource:), @selector(orderFrontGoToFolder:),
		@selector(takeNewTabIndexFrom:), @selector(takeTabsToCloseFrom:), @selector(takeTabsToTearOffFrom:),
		@selector(takeProjectPathFrom:), @selector(showWindow:), @selector(positionForWindowUnderCaret),
	};

	for(SEL selector : actions)
		assert_responds(selector);
}

void test_document_window_controller_keeps_its_delegate_methods ()
{
	// OakTabBarViewDataSource is @required, so these would fail to compile if the
	// spelling drifted — they are here so the @optional ones below sit beside the
	// full picture rather than alone.
	assert_responds(@selector(numberOfRowsInTabBarView:));
	assert_responds(@selector(tabBarView:titleForIndex:));
	assert_responds(@selector(tabBarView:pathForIndex:));
	assert_responds(@selector(tabBarView:UUIDForIndex:));
	assert_responds(@selector(tabBarView:isEditedAtIndex:));

	// These are the @optional ones, and the reason this test exists.
	assert_responds(@selector(tabBarView:shouldSelectIndex:));
	assert_responds(@selector(tabBarView:didDoubleClickIndex:));
	assert_responds(@selector(tabBarViewDidDoubleClick:));
	assert_responds(@selector(menuForTabBarView:));
	assert_responds(@selector(performDropOfTabItem:fromTabBar:index:toTabBar:index:operation:));

	// FileBrowserDelegate and NSWindowDelegate.
	assert_responds(@selector(fileBrowser:openURLs:));
	assert_responds(@selector(fileBrowser:closeURL:));
	assert_responds(@selector(windowShouldClose:));
	assert_responds(@selector(windowWillClose:));
}

void test_document_window_controller_keeps_its_cxx_selectors ()
{
	// The four that stayed ObjC++ because a caller in another framework pins the
	// signature — the same check t_be_interop.mm makes for BundleEditor, and the
	// only evidence that the category on the Swift class actually linked.
	assert_responds(@selector(variables));
	assert_responds(@selector(updateEnvironment:forCommand:));
	assert_responds(@selector(performBundleItem:));
	assert_responds(@selector(selectRange:inDocument:));

	// -scopeAttributes is OakTextViewDelegate's and is Swift, not ObjC++; it is
	// here because it reads a C++-typed property and so is easy to mistake for a
	// category method.
	assert_responds(@selector(scopeAttributes));
}
