// The Swift-implemented methods this framework's **tests** call by name.
//
// Now that FileBrowserViewController is Swift, the only ObjC++ left that calls
// into it is FileBrowserViewControllerCxx.mm — which hand-declares the handful
// it needs — and these tests. FileBrowserDiskOperations.h and
// FileBrowserActions.h existed to serve the old .mm and are deleted with the
// flip; this is the same rule-23 hand-declaration, scoped to the test bundle so
// it cannot drift back into the framework's own surface.
//
// A test file cannot declare these itself: seed_xcodeproj.rb wraps each
// tests/t_*.mm body in a C++ namespace, and an @interface inside one fails with
// "Objective-C declarations may only appear in global scope" (rule 34). It
// hoists `#import`s out of the namespace and rewrites the path, which is why
// this has to be a header rather than a few lines at the top of the test.
//
// Only what a test actually sends. Everything else the tests reach they reach
// through a protocol they can cast to — NSOutlineViewDataSource,
// NSOutlineViewDelegate, NSMenuDelegate, NSMenuValidation — which is better,
// because that is how AppKit reaches it too.
//
// Nothing checks these against the Swift at build time beyond the selector
// names, so this file is exactly as trustworthy as
// test_controller_keeps_the_selectors_that_moved_to_swift makes it (rule 18).
#import "../src/FileBrowserViewController.h"
#import "../src/FileBrowserTypes.h"

@interface FileBrowserViewController (SwiftSurfaceForTests)

// FileBrowserDiskOperations.swift. t_file_browser_disk_operations.mm runs both
// against a real temporary directory.
- (NSArray<NSURL*>*)performOperation:(FBOperation)op withURLs:(NSDictionary<NSURL*, NSURL*>*)urls unique:(BOOL)makeUnique select:(BOOL)selectDestinationURLs;
- (NSArray<NSURL*>*)performOperation:(FBOperation)op sourceURLs:(NSArray<NSURL*>*)srcURLs destinationURLs:(NSArray<NSURL*>*)destURLs unique:(BOOL)makeUnique select:(BOOL)selectDestinationURLs;

// FileBrowserLoading.swift. Drives the pending expand/select sets, which is what
// test_collapsing_an_item_drops_it_from_the_pending_expanded_urls sets up and
// what test_expand_urls_drains_its_completion_handlers exercises.
- (void)expandURLs:(NSArray<NSURL*>*)expandURLs selectURLs:(NSArray<NSURL*>*)selectURLs;

@end
