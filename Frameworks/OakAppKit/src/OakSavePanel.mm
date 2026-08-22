#import "OakSavePanel.h"
#import "OakSavePanelCxx.h"
#import "OakEncodingPopUpButton.h"
#import "OakUIConstructionFunctions.h"
#import "NSSavePanel Additions.h"

// What is left after the C++ moved to OakSavePanelSupport: an accessory view
// controller and a save panel. No encoding::type ivar, no settings_for_path, and
// no +initialize — the transformer registration is now a call, because Swift
// cannot define +initialize.
//
// The entry point keeps its C++ signature. Both callers (OakDocument.mm and
// DocumentWindowSupport.mm) pass an encoding::type *and* take one back through
// the completion block, and rule 15 says a block parameter with a C++ type makes
// the method uncallable from Swift — so this method is the boundary, and the box
// crosses it in both directions.

@interface OakEncodingSaveOptionsViewController : NSViewController <NSOpenSavePanelDelegate>
@property (nonatomic) OakEncodingOptions* encodingOptions;
@property (nonatomic) NSString* fileType;
@property (nonatomic) NSString* lineEndings;
@property (nonatomic) NSString* encoding;
@property (nonatomic) NSSavePanel* savePanel;
- (instancetype)initWithOptions:(OakEncodingOptions*)someEncodingOptions fileType:(NSString*)aFileType;
- (OakEncodingOptions*)resolvedOptionsForURL:(NSURL*)anURL;
- (void)updateSettingsWithOptions:(OakEncodingOptions*)options;
@end

@implementation OakEncodingSaveOptionsViewController
- (void)dealloc
{
	if(_savePanel.delegate == self)
		_savePanel.delegate = nil;
}

- (instancetype)initWithOptions:(OakEncodingOptions*)someEncodingOptions fileType:(NSString*)aFileType
{
	if(self = [super init])
	{
		// +initialize's job, moved to a call. It has to happen before -loadView:
		// the line-endings pop-up binds through this transformer by name, and a
		// missing transformer is a silent no-selection rather than an error.
		[OakSavePanelSupport registerValueTransformers];

		_encodingOptions = someEncodingOptions;
		_fileType = aFileType;
	}
	return self;
}

- (void)loadView
{
	NSPopUpButton* encodingPopUpButton    = [[OakEncodingPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
	NSPopUpButton* lineEndingsPopUpButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];

	[encodingPopUpButton setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

	encodingPopUpButton.accessibilityLabel    = @"Encoding";
	lineEndingsPopUpButton.accessibilityLabel = @"Line endings";

	NSArray* titles = @[ @"LF", @"CR", @"CRLF" ];
	for(NSUInteger i = 0; i < [titles count]; ++i)
		[[lineEndingsPopUpButton.menu addItemWithTitle:titles[i] action:nil keyEquivalent:@""] setTag:i];

	NSDictionary* views = @{
		@"encodingLabel":    OakCreateLabel(@"Encoding:"),
		@"encodingPopUp":    encodingPopUpButton,
		@"lineEndingsPopUp": lineEndingsPopUpButton,
	};

	NSView* containerView = [[NSView alloc] initWithFrame:NSZeroRect];
	OakAddAutoLayoutViewsToSuperview([views allValues], containerView);

	[containerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[encodingLabel]-[encodingPopUp]-[lineEndingsPopUp]-(>=20)-|" options:NSLayoutFormatAlignAllBaseline metrics:nil views:views]];
	[containerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(8)-[encodingPopUp]-(8)-|" options:NSLayoutFormatAlignAllLeading metrics:nil views:views]];

	containerView.frame = (NSRect){ NSZeroPoint, [containerView fittingSize] };
	self.view = containerView;

	[encodingPopUpButton bind:@"encoding" toObject:self withKeyPath:@"encoding" options:nil];
	[lineEndingsPopUpButton bind:NSSelectedTagBinding toObject:self withKeyPath:@"lineEndings" options:@{ NSValueTransformerNameBindingOption: @"OakLineEndingsTransformer" }];
}

- (void)updateSettingsWithOptions:(OakEncodingOptions*)options
{
	self.lineEndings = options.newlines;
	self.encoding    = options.charset;
}

- (OakEncodingOptions*)resolvedOptionsForURL:(NSURL*)anURL
{
	return [OakSavePanelSupport resolveOptions:_encodingOptions forURL:anURL fileType:_fileType];
}

- (void)panel:(NSSavePanel*)sender didChangeToDirectoryURL:(NSURL*)anURL
{
	[self updateSettingsWithOptions:[self resolvedOptionsForURL:[sender URL]]];
}
@end

@implementation OakSavePanel
+ (void)showWithPath:(NSString*)aPathSuggestion directory:(NSString*)aDirectorySuggestion fowWindow:(NSWindow*)aWindow encoding:(encoding::type const&)encoding fileType:(NSString*)aFileType completionHandler:(void(^)(NSString* path, encoding::type const& encoding))aCompletionHandler
{
	OakEncodingSaveOptionsViewController* optionsViewController = [[OakEncodingSaveOptionsViewController alloc] initWithOptions:[OakEncodingOptions optionsWithCxxEncoding:encoding] fileType:aFileType];
	if(!optionsViewController)
		return;

	[[aWindow attachedSheet] orderOut:self]; // incase there already is a sheet showing (like “Do you want to save?”)

	NSSavePanel* savePanel = [NSSavePanel savePanel];
	optionsViewController.savePanel = savePanel;
	[savePanel setTreatsFilePackagesAsDirectories:YES];
	if(aDirectorySuggestion)
		[savePanel setDirectoryURL:[NSURL fileURLWithPath:aDirectorySuggestion]];
	[savePanel setNameFieldStringValue:[aPathSuggestion lastPathComponent]];
	[savePanel setAccessoryView:optionsViewController.view];
	[optionsViewController updateSettingsWithOptions:[optionsViewController resolvedOptionsForURL:[savePanel URL]]];
	savePanel.delegate = optionsViewController;
	[savePanel beginSheetModalForWindow:aWindow completionHandler:^(NSModalResponse result) {
		savePanel.delegate = nil;
		NSString* path = result == NSModalResponseOK ? [[savePanel.URL filePathURL] path] : nil;
		OakEncodingOptions* chosen = [OakEncodingOptions optionsWithNewlines:optionsViewController.lineEndings charset:optionsViewController.encoding];
		aCompletionHandler(path, [chosen cxxEncoding]);
	}];

	// Deselect Extension
	if([savePanel.firstResponder isKindOfClass:[NSTextView class]])
	{
		NSTextView* tw = (NSTextView*)savePanel.firstResponder;
		NSRange extRange = [tw.textStorage.string rangeOfString:@"."];
		if(extRange.location != NSNotFound)
			[tw setSelectedRange:NSMakeRange(0, extRange.location)];
	}
}
@end
