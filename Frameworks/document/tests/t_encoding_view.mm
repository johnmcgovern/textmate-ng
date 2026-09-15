#import "EncodingViewTesting.h"
#import <Cocoa/Cocoa.h>

// Pins for EncodingWindowController — the "Unknown Encoding" sheet OakDocument
// runs when a file's bytes decode as nothing it recognises — written against
// the ObjC++ and before any port of it (rule 18, rule 40).
//
// It had no test. The sheet is a programmatic window (no nib) with three
// Cocoa Bindings through an NSObjectController whose content is the controller
// itself, and one piece of C++: the transcode-and-highlight helper that turns
// the raw bytes into the preview, marking the lines and characters that were
// not ASCII. A port breaks two things silently — the bindings, if the three
// bound properties lose the `@objc dynamic` KVO needs, and the preview, if the
// helper's highlighting or the "does this encoding fit" verdict drifts. Both
// are pinned here through the controls and the text storage, the surfaces the
// user sees.
//
// Everything runs on windows that are never shown; AppKit lays out and binds
// without a screen.

void setup ()
{
	NSApplicationLoad();
}

// "café" in ISO-8859-1: one byte above 0x7F, which is not valid UTF-8 on its
// own. A first line of plain ASCII, so the highlighting has a line to leave
// alone and a line to mark.
static NSData* Latin1Fixture ()
{
	char const bytes[] = "plain\ncaf\xE9 latin\n";
	return [NSData dataWithBytes:bytes length:sizeof(bytes) - 1];
}

static EncodingWindowController* Controller ()
{
	return [[EncodingWindowController alloc] initWithData:Latin1Fixture()];
}

// MARK: - Selector surface (rule 18, rule 64)

void test_encoding_window_controller_answers_its_public_selectors ()
{
	NSArray<NSString*>* const required = @[
		@"initWithData:",
		@"beginSheetModalForWindow:completionHandler:",
		@"encoding", @"setEncoding:",
		@"encodingNoBOM",
		@"displayName", @"setDisplayName:",
		@"acceptableEncoding", @"setAcceptableEncoding:",
		@"trainClassifier", @"setTrainClassifier:",
		@"performOpenDocument:",
		@"performCancelOperation:",
		@"textView:doCommandBySelector:",
		@"updateConstraints",
	];

	NSMutableArray* missing = [NSMutableArray array];
	for(NSString* name in required)
	{
		if(![EncodingWindowController instancesRespondToSelector:NSSelectorFromString(name)])
			[missing addObject:name];
	}
	OAK_ASSERT_EQ(std::string([missing componentsJoinedByString:@", "].UTF8String), std::string(""));
}

// MARK: - Defaults

void test_initial_state ()
{
	EncodingWindowController* controller = Controller();
	OAK_ASSERT([controller.encoding isEqualToString:@"ISO-8859-1"]);
	OAK_ASSERT([controller.displayName isEqualToString:@"untitled"]);
	OAK_ASSERT(controller.trainClassifier == YES);
	OAK_ASSERT(controller.acceptableEncoding == YES); // Latin-1 decodes anything
	OAK_ASSERT(controller.window != nil);
	OAK_ASSERT(controller.window.delegate == (id)controller);
	OAK_ASSERT(controller.window.defaultButtonCell == controller.openButton.cell);
	OAK_ASSERT(controller.textView.isEditable == NO);
	OAK_ASSERT([controller.cancelButton.keyEquivalent isEqualToString:@"\e"]);
}

void test_encoding_without_bom_strips_the_modifier ()
{
	EncodingWindowController* controller = Controller();
	controller.encoding = @"UTF-8//BOM";
	OAK_ASSERT([controller.encoding isEqualToString:@"UTF-8//BOM"]);
	OAK_ASSERT([controller.encodingNoBOM isEqualToString:@"UTF-8"]);

	controller.encoding = @"UTF-16LE";
	OAK_ASSERT([controller.encodingNoBOM isEqualToString:@"UTF-16LE"]);
}

void test_display_name_is_written_into_the_explanation ()
{
	EncodingWindowController* controller = Controller();
	controller.displayName = @"notes.txt";
	OAK_ASSERT([controller.displayName isEqualToString:@"notes.txt"]);
	OAK_ASSERT([controller.explanation.stringValue containsString:@"“notes.txt”"]);
	OAK_ASSERT([controller.explanation.stringValue containsString:@"unknown encoding"]);
}

// MARK: - The preview

// The verdict the Open button hangs on: Latin-1 accepts the byte, UTF-8 does
// not, and choosing Latin-1 again restores it.
void test_acceptable_encoding_follows_whether_the_bytes_decode ()
{
	EncodingWindowController* controller = Controller();
	OAK_ASSERT(controller.acceptableEncoding == YES);

	controller.encoding = @"UTF-8";
	OAK_ASSERT(controller.acceptableEncoding == NO);

	controller.encoding = @"ISO-8859-1";
	OAK_ASSERT(controller.acceptableEncoding == YES);
}

void test_preview_shows_the_bytes_decoded_in_the_chosen_encoding ()
{
	EncodingWindowController* controller = Controller();
	OAK_ASSERT_EQ(std::string(controller.textView.string.UTF8String), std::string("plain\ncafé latin\n"));
}

// The line with the non-ASCII byte gets a background from its start, and the
// character itself gets one too; the plain line gets none. That is what the
// user reads to judge whether the encoding is right.
void test_preview_highlights_the_line_and_the_character_but_not_plain_lines ()
{
	EncodingWindowController* controller = Controller();
	NSAttributedString* text = controller.textView.textStorage;
	NSString* str = text.string;

	NSUInteger plain  = [str rangeOfString:@"plain"].location;
	NSUInteger caf    = [str rangeOfString:@"caf"].location;
	NSUInteger eacute = [str rangeOfString:@"é"].location;
	OAK_ASSERT(plain != NSNotFound && caf != NSNotFound && eacute != NSNotFound);

	OAK_ASSERT([text attribute:NSBackgroundColorAttributeName atIndex:plain effectiveRange:NULL] == nil);
	OAK_ASSERT([text attribute:NSBackgroundColorAttributeName atIndex:caf effectiveRange:NULL] != nil);
	OAK_ASSERT([text attribute:NSBackgroundColorAttributeName atIndex:eacute effectiveRange:NULL] != nil);
	OAK_ASSERT([text attribute:NSForegroundColorAttributeName atIndex:caf effectiveRange:NULL] != nil);
	OAK_ASSERT([text attribute:NSForegroundColorAttributeName atIndex:eacute effectiveRange:NULL] == nil); // the character style carries no foreground colour
}

// MARK: - Bindings

// The three bindings the sheet is built on, driven the way the app drives them:
// set the property on the controller, read the control.
void test_open_button_follows_acceptable_encoding ()
{
	EncodingWindowController* controller = Controller();
	OAK_ASSERT(controller.openButton.isEnabled == YES);
	controller.acceptableEncoding = NO;
	OAK_ASSERT(controller.openButton.isEnabled == NO);
	controller.acceptableEncoding = YES;
	OAK_ASSERT(controller.openButton.isEnabled == YES);
}

void test_learn_check_box_follows_train_classifier ()
{
	EncodingWindowController* controller = Controller();
	OAK_ASSERT(controller.learnCheckBox.state == NSControlStateValueOn);
	controller.trainClassifier = NO;
	OAK_ASSERT(controller.learnCheckBox.state == NSControlStateValueOff);
}

void test_pop_up_follows_encoding ()
{
	EncodingWindowController* controller = Controller();
	OAK_ASSERT([controller.popUpButton.encoding isEqualToString:@"ISO-8859-1"]);
	controller.encoding = @"UTF-8";
	OAK_ASSERT([controller.popUpButton.encoding isEqualToString:@"UTF-8"]);
}

// And the other direction, which OakEncodingPopUpButton pushes by hand through
// -infoForBinding:: choosing an encoding in the pop-up changes the controller's,
// and the preview and verdict follow.
void test_choosing_in_the_pop_up_updates_the_encoding_and_the_verdict ()
{
	EncodingWindowController* controller = Controller();
	controller.popUpButton.encoding = @"UTF-8";
	OAK_ASSERT([controller.encoding isEqualToString:@"UTF-8"]);
	OAK_ASSERT(controller.acceptableEncoding == NO);
	OAK_ASSERT(controller.openButton.isEnabled == NO);
}

// MARK: - The sheet

// Enter in the read-only preview clicks the default button — Open — and the
// sheet ends with OK; Cancel ends it with Cancel. Both go through the real
// sheet machinery on a parent window that is never shown. After either, the
// controller has let go of its object controller's content, which is the
// retain cycle -cleanup exists to break.
static NSModalResponse RunSheet (EncodingWindowController* controller, void(^act)(void))
{
	NSWindow* parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
	__block NSModalResponse response = -1;
	[controller beginSheetModalForWindow:parent completionHandler:^(NSModalResponse r){ response = r; }];
	act();
	for(int i = 0; i < 50 && response == -1; ++i)
		[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
	return response;
}

void test_enter_in_the_preview_opens ()
{
	EncodingWindowController* controller = Controller();

	// The button's target is nil in the app, and the action climbs the responder
	// chain from the key window to the window controller. A test process has no
	// key window, so nil-target dispatch falls through to NSDocumentController
	// instead — which, headless, dies on an XPC endpoint it cannot get. The
	// target is named here so the pin covers the Enter → default button → Open
	// chain without that detour.
	controller.openButton.target = controller;

	NSModalResponse response = RunSheet(controller, ^{
		OAK_ASSERT([controller textView:controller.textView doCommandBySelector:@selector(insertNewline:)] == YES);
	});
	OAK_ASSERT(response == NSModalResponseOK);
	OAK_ASSERT(controller.objectController.content == nil);
}

void test_cancel_ends_the_sheet_with_cancel ()
{
	EncodingWindowController* controller = Controller();
	NSModalResponse response = RunSheet(controller, ^{
		[controller performCancelOperation:nil];
	});
	OAK_ASSERT(response == NSModalResponseCancel);
	OAK_ASSERT(controller.objectController.content == nil);
}

void test_other_commands_in_the_preview_are_not_handled ()
{
	EncodingWindowController* controller = Controller();
	OAK_ASSERT([controller textView:controller.textView doCommandBySelector:@selector(moveDown:)] == NO);
}

// MARK: - Layout

// The constraints are installed by -updateConstraints on the content view,
// which forwards to the controller. A layout pass on the never-shown window
// must resolve them without a conflict and give the buttons a size.
void test_layout_resolves_without_conflicts ()
{
	EncodingWindowController* controller = Controller();
	[controller.window layoutIfNeeded];
	OAK_ASSERT(NSWidth(controller.openButton.frame) > 0);
	OAK_ASSERT(NSWidth(controller.cancelButton.frame) > 0);
	OAK_ASSERT(NSMinX(controller.cancelButton.frame) < NSMinX(controller.openButton.frame)); // H:[cancel]-[open]-|
}
