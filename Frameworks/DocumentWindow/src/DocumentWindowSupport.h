// The C++ half of DocumentWindow's Swift files — the same shape as
// FindSupport.mm and FFResultNodeSupport.mm, and the same rule: the *decisions*
// stay in the Swift. Nothing here chooses what to run or where to put it.
//
// Small for now, because the framework is being ported leaf-first and the leaves
// are nearly C++-free. It exists at all because of one selector:
// -filterDocumentThroughCommand:input:output: takes two C++ enums and lives in
// OakTextView.h, which is not moving.
#import <Cocoa/Cocoa.h>
#import "DWOutputType.h"

// Runs `command` over the first responder that accepts it, taking the selection
// as input and putting the result where `outputType` says.
//
// The ObjC++ found that responder with -targetForAction: and sent it
// -filterDocumentThroughCommand:input:output:, whose `input::type` and
// `output::type` parameters Swift cannot name. `input` is not a parameter here
// because the call site only ever passes input::selection.
//
// Returns NO when no responder accepted the command, which is also what the
// ObjC++ did by simply not sending it.
BOOL DWFilterDocumentThroughCommand (NSString* command, DWOutputType outputType);
