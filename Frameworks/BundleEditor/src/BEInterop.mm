// The three things the Swift BundleEditor structurally cannot do (Phase 4).
//
// Everything else about the window controller is Swift; this file is small on
// purpose, and each piece here is here for a reason Swift cannot argue with.
#import "BundleEditor.h"
#import "BESwiftClasses.h"
#import <TMBundleModel/TMBundleModelCxx.h>
#import <OakCommand/OakCommand.h>
#import <OakTextView/OakDocumentView.h>
#import <OakFoundation/OakStringListTransformer.h>

// What the category below forwards to. Declared here rather than in
// BESwiftClasses.h because a category needs the real @interface, and
// BESwiftClasses.h deliberately cannot import BundleEditor.h.
@interface BundleEditor (BESwiftInternals)
- (void)revealItem:(TMBundleItem*)item;
@property (nonatomic, readonly) OakDocumentView* documentView;
@end

// 1. A C++-typed selector on a Swift class.
//
// -revealBundleItem: takes bundles::item_ptr and is called from two other
// targets (AppController.mm, DocumentWindowController.mm), both still ObjC++.
// A Swift class cannot implement it — but ObjC can add a *category* to a Swift
// class, so the signature survives untouched and forwards to the Swift.
//
// This is the CommitWindow adapter recipe with one fewer object: there, the
// selector arrived at a delegate, so a stand-in could conform on the
// controller's behalf; here it is called on the class itself, and a category is
// what puts it there.
@implementation BundleEditor (BECxxInterop)

- (void)revealBundleItem:(bundles::item_ptr const&)anItem
{
	[self revealItem:[TMBundleItem itemWithCxxItem:anItem]];
}

// 2. OakCommandDelegate's environment hook, also C++-typed.
//
// OakCommand finds this by walking the responder chain with targetForAction:,
// so it has to be on the window controller itself rather than on a helper.
// The body only forwards to the text view, so no Swift is involved at all.
- (void)updateEnvironment:(std::map<std::string, std::string>&)res forCommand:(OakCommand*)aCommand
{
	[self.documentView.textView updateEnvironment:res];
}

@end

// 3. +load.
//
// Swift has no equivalent, and both of these genuinely need it — see the
// comments below. A plain class rather than a category on BundleEditor: a
// category +load on a Swift class works, but this runs before anything has
// realized that class and there is no reason to depend on the subtler spelling.
@interface BEBootstrap : NSObject
@end

@implementation BEBootstrap

+ (void)load
{
	// The property xibs bind through these transformers BY NAME, so they have to
	// exist before any of those nibs is loaded — CommandProperties.xib alone uses
	// six. They were once registered in +sharedInstance's dispatch_once, which
	// happened to work only because the Bundle Editor window was the sole way to
	// reach those nibs; the nib tests added 2026-07-28 fell straight into that
	// invisible ordering dependency.
	//
	// Still worth knowing now the layer is Swift: an NSException raised inside
	// nib loading unwinds through a Swift frame, and the Swift runtime traps on
	// it — "C++ exception handling detected but the Swift runtime was compiled
	// with exceptions disabled". What used to be a catchable ObjC exception is
	// now immediate process death, so an ordering bug like that one stops being
	// survivable.
	static struct { NSString* name; NSArray* array; } const converters[] =
	{
		{ @"OakSaveStringListTransformer",           @[ @"nop", @"saveActiveFile", @"saveModifiedFiles" ] },
		{ @"OakInputStringListTransformer",          @[ @"selection", @"document", @"scope", @"line", @"word", @"character", @"none" ] },
		{ @"OakInputFormatStringListTransformer",    @[ @"text", @"xml" ] },
		{ @"OakOutputLocationStringListTransformer", @[ @"replaceInput", @"replaceDocument", @"atCaret", @"afterInput", @"newWindow", @"toolTip", @"discard", @"replaceSelection" ] },
		{ @"OakOutputFormatStringListTransformer",   @[ @"text", @"snippet", @"html", @"completionList" ] },
		{ @"OakOutputCaretStringListTransformer",    @[ @"afterOutput", @"selectOutput", @"interpolateByChar", @"interpolateByLine", @"heuristic" ] },
	};

	[OakRot13Transformer register];
	for(auto const& converter : converters)
		[OakStringListTransformer createTransformerWithName:converter.name andObjectsArray:converter.array];

	// OakCommand posts this instead of calling us directly — that direct call
	// used to close a cycle in the framework graph (OakCommand → BundleEditor →
	// OakTextView → OakCommand).
	//
	// In +load, not in -init: BundleEditor is only instantiated lazily, so a
	// crash-recovery reveal arriving before the window has ever been opened
	// would otherwise post into a class that was never around to observe it.
	// +load runs unconditionally at process start, which is what the original
	// direct call actually guaranteed.
	//
	// No C++ here despite the .mm — the payload is a UUID string and
	// TMBundleItem resolves it, which is the wrapper doing its job.
	[NSNotificationCenter.defaultCenter addObserverForName:OakRevealBundleItemNotification object:nil queue:nil usingBlock:^(NSNotification* notification){
		if(TMBundleItem* item = [TMBundleItem itemWithUUIDString:notification.userInfo[OakCommandUUIDKey]])
			[BundleEditor.sharedInstance revealItem:item];
	}];
}

@end
