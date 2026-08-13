// The C++ half of DocumentWindow's Swift files — the same shape as
// FindSupport.mm and FFResultNodeSupport.mm, and the same rule: the *decisions*
// stay in the Swift. Nothing here chooses what to run or where to put it.
//
// It began with one selector — -filterDocumentThroughCommand:input:output:
// takes two C++ enums and lives in OakTextView.h, which is not moving — and grew
// when DocumentWindowController was ported. That port found three kinds of C++,
// and only the first was written down beforehand:
//
//  1. **C++-typed selectors**, which stay ObjC++ in a category on the Swift
//     class (see DocumentWindowSupport.mm). Four of them are pinned by callers
//     in other frameworks; -scopeAttributes is pinned by the C++-typed property
//     it reads. That is five, not the ten the handoff predicted.
//
//  2. **C++ in *block* signatures**, which is the one nothing warned about.
//     -loadModalForWindow:completionHandler: and -saveModalForWindow:… hand
//     their block an `oak::uuid_t const&`, and OakSavePanel both takes an
//     `encoding::type` and passes one back. A block whose parameters Swift
//     cannot name makes the whole method uncallable, so the document-open path
//     and all three save paths come through the shims below. Find hit this at
//     FindSupport.h:118, but only where the block *ignored* the C++ argument;
//     here every one of them uses it, so these convert rather than just wrap.
//
//  3. **path:: / settings_for_path / bundles::query work**, the usual suspects,
//     the same as every other Support file in this project.
//
// Each function below is a place where C++ appears in a signature Swift cannot
// name. Where a whole algorithm was C++ end to end — -goToRelatedFile: — it
// moved here entire rather than being half-translated, so its behaviour is
// carried over rather than re-derived.
#import <Cocoa/Cocoa.h>
#import "DWOutputType.h"

// For OakDocumentIOResult. The header's C++-typed members (scmStatus, variables)
// are dropped by the importer, which is the same bargain Find-Bridging-Header.h
// makes when it imports this header.
#import <document/OakDocument.h>

@class DWScopeContext;
@class Find;
@class OakTextView;

// Find.delegate is `id<FindDelegate>`, and DocumentWindowController is not a
// FindDelegate as far as Swift is concerned: -selectRange:inDocument: takes a
// `text::range_t const&`, which — unlike a std::map return type — the importer
// does *not* drop under objcxx interop, so the conformance lives on the ObjC++
// category and the assignment comes through here.
void DWSetFindDelegate (Find* find, id delegate);

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

// ============================================================
// = The three APIs whose blocks carry C++                    =
// ============================================================

// -loadModalForWindow:completionHandler: and -saveModalForWindow:… , with
// `oak::uuid_t const& filterUUID` spelled as an NSString. Nil when the uuid is
// null, which is exactly the `if(filterUUID)` test both call sites make — the
// C++ type is falsy when null, and NSString nil is falsy too, so the Swift
// reads the same as the ObjC++ did.
//
// The block bodies did not come with these: they are substantial, entirely
// AppKit past the uuid, and stayed in the Swift.
void DWLoadDocumentModalForWindow (OakDocument* document, NSWindow* window, void(^handler)(OakDocumentIOResult result, NSString* errorMessage, NSString* filterUUID));
void DWSaveDocumentModalForWindow (OakDocument* document, NSWindow* window, void(^handler)(OakDocumentIOResult result, NSString* errorMessage, NSString* filterUUID));

// OakSavePanel, whose `encoding::type` appears twice — once as the suggestion
// going in, once as the choice coming back. Going in it is always built from the
// document's own diskNewlines/diskEncoding, so the document is the parameter and
// the construction stays here. Coming back, both call sites do nothing with it
// but assign `.newlines()` and `.charset()` straight onto a document, so those
// two strings are what the block receives.
//
// `path` nil means the user cancelled; both call sites return immediately.
void DWShowSavePanelForDocument (OakDocument* document, NSString* pathSuggestion, NSString* directorySuggestion, NSWindow* window, void(^handler)(NSString* path, NSString* newlines, NSString* charset));

// The failure alert behind a filterUUID, with its “Edit Command” button. Was a
// file-static in the ObjC++ (`show_command_error`) called from the two save/open
// error branches; `commandName` is not a parameter because neither passed one.
void DWShowCommandError (NSString* message, NSString* filterUUID, NSWindow* window);

// crash_reporter_info_t is RAII: constructing it registers a breadcrumb for a
// crash report and destroying it unregisters, so in -openAndSelectDocument: the
// live range *is* the rest of the block. Swift has no way to hold that, and
// dropping it would silently lose the diagnostic, so the scope becomes explicit:
// the info is live for exactly the duration of `block`.
void DWWithCrashReporterInfo (NSString* info, void(^block)(void));

// ============================================================
// = settings_for_path                                        =
// ============================================================

// The fileType a document falls back to when it has none and the user was not
// offered a grammar — `attr.file.unknown-type` for a document on disk,
// `attr.untitled` for one that is not. Defaults to "text.plain".
NSString* DWDefaultFileTypeForDocument (OakDocument* document, NSString* projectPath);

// The `projectDirectory` setting, when the user has pointed one somewhere
// absolute; nil otherwise, meaning "keep the path you already had". Normalized,
// because the setting is user-written and the caller compares it against paths.
NSString* DWUserProjectDirectoryForPath (NSString* projectPath);

// The saveOnBlur setting, which is why a document gets written when TextMate
// stops being the active application.
BOOL DWShouldSaveOnBlur (OakDocument* document);

// ============================================================
// = Paths and strings                                        =
// ============================================================

// path::expand_braces — "foo.{h,cc}" becomes two paths. Always at least one
// element, which the ObjC++ asserted and the callers rely on.
NSArray<NSString*>* DWExpandBraces (NSString* path);

BOOL DWIsChildPath (NSString* path, NSString* parent);
BOOL DWPathExists (NSString* path);

// ~/Library/Application Support/TextMate-NG/Session/Info.plist, via
// oak::application_t::support.
NSString* DWSessionPath (void);

// What Go to File pre-fills from the find clipboard, but only when the entry
// looks like a file reference with a line number ("foo.cc:42") — the regular
// expression is the whole test. Nil when it does not match, which is the
// ObjC++'s "leave the filter string empty".
//
// Relative to `basePath` when the entry is under it, absolute otherwise.
NSString* DWFindClipboardFilterString (NSString* string, NSString* basePath);

// ============================================================
// = Bundles                                                  =
// ============================================================

// The callback.document.did-open semantic-class items, run against the view's
// own scope. bundles::query returns C++ item_ptrs and -performBundleItem: takes
// one, so the loop never leaves this file.
void DWPerformDidOpenCallbacks (OakTextView* textView);

// Whether the bundle server is reachable, which gates the grammar-install
// suggestion. The host comes from the REST_API build setting — a preprocessor
// define, so it is not visible to Swift at all.
BOOL DWCanReachBundleServer (void);

// ============================================================
// = Window and tab titles                                    =
// ============================================================

// Which settings key the title comes from. The ObjC++ passed
// kSettingsWindowTitleKey / kSettingsTabTitleKey — two std::strings — to a
// -titleForDocument:withSetting: whose signature was C++ for that reason alone.
// Nothing outside the class ever called it, so the parameter narrows to this
// instead of the selector staying ObjC++.
typedef NS_ENUM(NSInteger, DWTitleSetting) {
	DWTitleSettingWindow = 0,
	DWTitleSettingTab,
};

// The document's title under that setting, with the window's SCM variables and
// projectDirectory merged into the settings lookup. Falls back to the document's
// display name, exactly as settings_t::get did.
//
// `scopeAttributes` and `untitledSavePath` are parameters rather than being
// recomputed here: both are the caller's, and passing them keeps this function
// from deciding anything.
NSString* DWTitleForDocument (OakDocument* document, DWTitleSetting setting, NSString* projectPath, NSString* untitledSavePath, NSString* scopeAttributes, DWScopeContext* scopeContext);

// The `attr.scm.status.…` fragment for a document, or nil when it has no SCM
// status. This exists because OakDocument.scmStatus is scm::status::type, which
// the importer drops — so -scopeAttributes reads as portable and is not.
// Converting the enum to its string is TMSCMStatus's business, which is why it
// is here and not on DWScopeContext.
NSString* DWSCMStatusAttribute (OakDocument* document);

// ============================================================
// = Go to Related File                                       =
// ============================================================

// The file ⌥⌘↑ moves to, or nil when the ObjC++ would have beeped.
//
// This is the one function here that decides something, and it is here because
// it was C++ from top to bottom: a std::set of candidates, path::entries over
// the directory, utf8 validation of each candidate's content, two path::glob_t
// filters, and a rotation through the sorted result. Splitting it would have
// meant re-deriving the ordering rules in Swift, so it moved across whole.
//
// Two details are carried over deliberately rather than cleaned up. The filter
// reads `name == documentName || !binaryGlob.does_match(name) &&
// !excludeGlob.does_match(name)` — mixed && and || without parentheses, which
// means the current document is always kept even when a glob would exclude it.
// And the candidate set is a std::set, so the rotation order is byte-wise by
// name and not the order the files were found in.
NSString* DWRelatedFilePath (OakDocument* document, NSArray<OakDocument*>* documents, NSString* projectPath, NSString* scopeAttributes, DWScopeContext* scopeContext);
