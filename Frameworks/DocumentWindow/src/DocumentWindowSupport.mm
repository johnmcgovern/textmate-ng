#import "DocumentWindowSupport.h"
#import <OakTextView/OakTextView.h>
#import <command/parser.h>

// The static half of the guard DWOutputType.h describes. A divergence here is a
// compile error rather than a Filter Through Command that quietly does the wrong
// thing to your document; t_output_type.mm checks the same pairs at runtime,
// because this file only exists as long as the C++ does.
static_assert((NSInteger)output::replace_input     == DWOutputTypeReplaceInput,     "DWOutputType diverged from output::type: replace_input");
static_assert((NSInteger)output::replace_document  == DWOutputTypeReplaceDocument,  "DWOutputType diverged from output::type: replace_document");
static_assert((NSInteger)output::at_caret          == DWOutputTypeAtCaret,          "DWOutputType diverged from output::type: at_caret");
static_assert((NSInteger)output::after_input       == DWOutputTypeAfterInput,       "DWOutputType diverged from output::type: after_input");
static_assert((NSInteger)output::new_window        == DWOutputTypeNewWindow,        "DWOutputType diverged from output::type: new_window");
static_assert((NSInteger)output::tool_tip          == DWOutputTypeToolTip,          "DWOutputType diverged from output::type: tool_tip");
static_assert((NSInteger)output::discard           == DWOutputTypeDiscard,          "DWOutputType diverged from output::type: discard");
static_assert((NSInteger)output::replace_selection == DWOutputTypeReplaceSelection, "DWOutputType diverged from output::type: replace_selection");

BOOL DWFilterDocumentThroughCommand (NSString* command, DWOutputType outputType)
{
	// -targetForAction: walks the responder chain for something that implements
	// the selector, exactly as the ObjC++ did; nothing accepting it is a no-op
	// rather than an error, which is what "no document is frontmost" looks like.
	if(id textView = [NSApp targetForAction:@selector(filterDocumentThroughCommand:input:output:)])
		return [textView filterDocumentThroughCommand:command input:input::selection output:(output::type)outputType];
	return NO;
}
