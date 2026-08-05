#import "../src/FFResultsViewController.h"
#import "../src/FFResultNode.h"
#import "FFKVORecorder.h"

// FFResultsViewController is the find results outline view. Most of it needs a
// window and is out of reach here (the GUI-suite problem under Stream 7) — but
// the part that has already broken this framework twice is not the drawing, it
// is the **observation contract**, and that is testable without one.
//
// Three of this class's properties are observed rather than read:
//
//  - `replaceString` and `showReplacementPreviews` are *bound* by Find.mm
//    (Find.mm:194-195) to the replace text field, and are listed in
//    OakSearchResultsMatchCellView's +keyPathsForValuesAffectingExcerptString,
//    so a change has to repaint every visible excerpt.
//  - `showKeyEquivalent` is observed by OakSearchResultsHeaderCellView through
//    OakTableCellView's `observeKeyPaths` bridge, which registers on the *view
//    controller* and mirrors values back with -setValue:forKey:.
//
// Written before the Swift port deliberately. Against the ObjC++ they pass for
// free — the runtime swizzles any setter an observer registers on. After the
// port they pass only if each property is `@objc dynamic`, which is the defect
// that shipped in the FFResultNode port (9d560946) and was caught in the
// FFDocumentSearch one. This file is the guard for the third instance.

static FFResultsViewController* Controller ()
{
	return [[FFResultsViewController alloc] init];
}

// ==========================
// = The observation contract =
// ==========================

void test_replace_string_notifies_observers ()
{
	FFResultsViewController* controller = Controller();
	FFKVORecorder* recorder = [FFKVORecorder new];
	[controller addObserver:recorder forKeyPath:@"replaceString" options:NSKeyValueObservingOptionNew context:NULL];

	controller.replaceString = @"something";

	OAK_ASSERT([recorder sawKeyPath:@"replaceString"]);
	OAK_ASSERT([controller.replaceString isEqualToString:@"something"]);

	[controller removeObserver:recorder forKeyPath:@"replaceString"];
}

void test_show_replacement_previews_notifies_observers ()
{
	FFResultsViewController* controller = Controller();
	FFKVORecorder* recorder = [FFKVORecorder new];
	[controller addObserver:recorder forKeyPath:@"showReplacementPreviews" options:NSKeyValueObservingOptionNew context:NULL];

	controller.showReplacementPreviews = YES;

	OAK_ASSERT([recorder sawKeyPath:@"showReplacementPreviews"]);
	OAK_ASSERT(controller.showReplacementPreviews);

	[controller removeObserver:recorder forKeyPath:@"showReplacementPreviews"];
}

// Not in the public header — it is a class-extension property — but the header
// cell observes it by name through the KVC bridge, so its spelling and its KVO
// compliance are both load-bearing. Reached here the same way the cell reaches
// it: by string.
void test_show_key_equivalent_is_observable_by_name ()
{
	FFResultsViewController* controller = Controller();
	FFKVORecorder* recorder = [FFKVORecorder new];
	[controller addObserver:recorder forKeyPath:@"showKeyEquivalent" options:NSKeyValueObservingOptionNew context:NULL];

	[controller setValue:@YES forKey:@"showKeyEquivalent"];

	OAK_ASSERT([recorder sawKeyPath:@"showKeyEquivalent"]);
	OAK_ASSERT([[controller valueForKey:@"showKeyEquivalent"] boolValue]);

	[controller removeObserver:recorder forKeyPath:@"showKeyEquivalent"];
}

// The cells mirror the controller's values onto themselves with
// -setValue:forKey: using the *same* string, so every observed key path has to
// be readable by name too. A port that renames a property in Swift without
// pinning the ObjC selector breaks this silently, at runtime, only when a cell
// scrolls into view.
void test_observed_key_paths_are_readable_by_name ()
{
	FFResultsViewController* controller = Controller();
	controller.replaceString           = @"xyz";
	controller.showReplacementPreviews = YES;

	OAK_ASSERT([[controller valueForKey:@"replaceString"] isEqualToString:@"xyz"]);
	OAK_ASSERT([[controller valueForKey:@"showReplacementPreviews"] boolValue]);
	OAK_ASSERT([controller valueForKey:@"showKeyEquivalent"] != nil);
}

// ==================
// = Plain contract =
// ==================

void test_a_fresh_controller_has_no_selection ()
{
	FFResultsViewController* controller = Controller();
	OAK_ASSERT_EQ(controller.selectedResults.count, 0);
}

// -setResults: takes the whole tree; Find.mm hands it a bare root before the
// first batch of matches arrives, so nil and empty both have to be survivable.
void test_results_accepts_an_empty_tree ()
{
	FFResultsViewController* controller = Controller();

	controller.results = [FFResultNode new];
	OAK_ASSERT(controller.results != nil);
	OAK_ASSERT_EQ(controller.selectedResults.count, 0);

	controller.results = nil;
	OAK_ASSERT(controller.results == nil);
}
