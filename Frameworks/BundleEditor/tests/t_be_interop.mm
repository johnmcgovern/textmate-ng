#import "../src/BundleEditorCxx.h"
#import "../src/BESwiftClasses.h"
#import <TMBundleModel/TMBundleModelCxx.h>
#import <OakTextView/OakDocumentView.h>
#import <test/bundle_index.h>
#import <plist/ascii.h>
#import <ns/ns.h>

// BundleEditor is Swift, reached from ObjC++ through declarations that NOTHING
// checks against it at build time:
//
//   * BundleEditor.h — the C++-free public surface: -revealItem:, which takes a
//     TMBundleItem and is what a Swift consumer calls.
//   * BundleEditorCxx.h — -revealBundleItem:, which takes bundles::item_ptr and
//     is called from AppController.mm and DocumentWindowSupport.mm. Split out of
//     BundleEditor.h on 2026-09-03 (rule 11) so the class could reach a Swift
//     bridging header at all; the `#include <bundles/bundles.h>` it used to
//     carry for this one selector kept the whole thing out.
//   * BESwiftClasses.h — PropertiesViewController and OakRot13Transformer.
//   * BEInterop.mm's own @interface for -documentView.
//
// A drift in any of them is an unrecognized selector at runtime, in a window a
// user opened. These tests are the build-time check that was missing, and they
// import all three headers for exactly that reason.
//
// They deliberately do NOT instantiate the window controller: doing so builds a
// window and loads eight nibs, which the nib tests already cover one at a time
// and more precisely. What is under test here is the ObjC surface itself.

static bundles::item_ptr Command;

void setup_fixtures ()
{
	test::bundle_index_t index;
	Command = index.add(bundles::kItemTypeCommand,
		"{ name = 'Interop'; uuid = 'BE1DEA00-0000-0000-0000-000000000001'; command = 'true'; }");
	index.commit();
}

static Class bundle_editor_class ()
{
	return NSClassFromString(@"BundleEditor");
}

// The Swift class is actually registered under the name its ObjC consumers use.
// @objc(BundleEditor) is what makes that true; without it the class would be
// name-mangled and every consumer would fail at +sharedInstance.
void test_the_swift_class_is_registered_under_its_objc_name ()
{
	OAK_ASSERT(bundle_editor_class());
	OAK_ASSERT([bundle_editor_class() isSubclassOfClass:NSWindowController.class]);
}

// The three selectors other targets call. -showWindow: comes from
// NSWindowController; the other two are this framework's own contract.
void test_public_surface_from_bundle_editor_h ()
{
	Class klass = bundle_editor_class();

	OAK_ASSERT([klass respondsToSelector:@selector(sharedInstance)]);
	OAK_ASSERT([klass instancesRespondToSelector:@selector(showWindow:)]);
	OAK_ASSERT([klass instancesRespondToSelector:@selector(revealItem:)]);
	OAK_ASSERT([klass instancesRespondToSelector:@selector(browserSelectionDidChange:)]);
}

// The C++ half, now in its own header. Same contract, same two callers; only the
// file it is declared in changed.
void test_cxx_surface_from_bundle_editor_cxx_h ()
{
	OAK_ASSERT([bundle_editor_class() instancesRespondToSelector:@selector(revealBundleItem:)]);
}

// What BEInterop.mm's category forwards to. -documentView is internal to the
// framework, so nothing but that hand-written @interface names it — which is
// precisely why a test has to. (-revealItem: used to be here too; it is public
// now and is asserted above.)
void test_internal_surface_beinterop_forwards_to ()
{
	OAK_ASSERT([bundle_editor_class() instancesRespondToSelector:@selector(documentView)]);
}

// OakCommand finds this by walking the responder chain, so it has to be on the
// window controller itself. It is supplied by the ObjC++ category because its
// signature is C++-typed; if that category ever stopped being force-loaded, the
// symptom would be commands silently running with the wrong environment rather
// than a crash.
void test_command_environment_hook_is_present ()
{
	OAK_ASSERT([bundle_editor_class() instancesRespondToSelector:@selector(updateEnvironment:forCommand:)]);
}

// BESwiftClasses.h's other two declarations. PropertiesViewController is File's
// Owner of all eight property xibs, and the transformer is registered by name in
// +load — the nib tests exercise both, but only through the nibs, so a rename of
// the class itself would surface there as a confusing nib failure rather than as
// this.
void test_beswiftclasses_declarations_still_match ()
{
	OAK_ASSERT(NSClassFromString(@"PropertiesViewController"));
	OAK_ASSERT([NSClassFromString(@"PropertiesViewController") instancesRespondToSelector:@selector(initWithName:)]);
	OAK_ASSERT([NSClassFromString(@"PropertiesViewController") instancesRespondToSelector:@selector(labelWidth)]);

	OAK_ASSERT(NSClassFromString(@"OakRot13Transformer"));
	OAK_ASSERT([NSClassFromString(@"OakRot13Transformer") respondsToSelector:@selector(register)]);
}

// The six named transformers the property xibs bind through are registered in
// +load, not lazily — a nib loaded before any BundleEditor instance exists
// must still find them. That ordering was a real bug once (2026-07-28), so it
// is asserted here without touching the class that would paper over it.
void test_value_transformers_are_registered_before_any_instance ()
{
	// Names accumulated rather than asserted one at a time, so a failure reports
	// which transformers are missing instead of only the first.
	NSMutableArray<NSString*>* missing = [NSMutableArray array];
	for(NSString* name in @[ @"OakRot13Transformer", @"OakSaveStringListTransformer", @"OakInputStringListTransformer", @"OakInputFormatStringListTransformer", @"OakOutputLocationStringListTransformer", @"OakOutputFormatStringListTransformer", @"OakOutputCaretStringListTransformer" ])
	{
		if(![NSValueTransformer valueTransformerForName:name])
			[missing addObject:name];
	}
	OAK_ASSERT_EQ(to_s([missing componentsJoinedByString:@", "]), "");
}
