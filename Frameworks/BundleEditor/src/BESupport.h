// The ObjC boundary the BundleEditor Swift code sits on (Phase 4).
//
// Same rule as CWSupport.h / PWSupport.h: everything here exists because Swift
// cannot express it. The bundle-item model itself moved out to TMBundleModel
// (TMBundleItem / TMScopeContext) and the browser tree to BEEntry.h; what is
// left here is the handful of engine calls that are specific to this one
// window — its plist text format, its command popups, its item templates.
//
// This header is free of C++ so the Swift bridging header can import it.
#import <Cocoa/Cocoa.h>
#import <TMBundleModel/TMBundleItem.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - Property-list text
//
// The Bundle Editor edits some item bodies as TextMate's ASCII plist dialect
// (a theme's settings, a macro's commands, a settings item's dictionary), so
// these are the document's text ↔ object conversions — not the binary/XML
// plist NSPropertyListSerialization would give.

// Single-quoted strings and BundleEditor's own key sort order, which is what
// makes a re-serialized item diff cleanly against the one on disk instead of
// reordering every key alphabetically.
NSString* BEPlistString (id object);

// nil when the text does not parse. The Bundle Editor turns that into the
// "Error Parsing Property List" alert rather than silently discarding an edit.
id _Nullable BEObjectFromPlistString (NSString* string);

// MARK: - Command properties

// The six popup values CommandProperties.xib binds to, resolved from
// command::parse_command's enums to the strings its value transformers expect,
// plus autoScrollOutput. Keys: beforeRunningCommand, input, inputFormat,
// outputLocation, outputFormat, outputCaret, autoScrollOutput.
//
// Resolved here, in C++, rather than handing Swift the raw enum to index a
// literal array with. parse_command's output_format enum has five values while
// the xib offers four, and an out-of-range index is an NSRangeException in ObjC
// but a hard trap in Swift — the same "clamp in the wide domain, convert last"
// rule that has cost this project three crashes.
NSDictionary<NSString*, id>* BECommandPopupValues (TMBundleItem* item);

// MARK: - New-item templates

// The ${VAR} expansion applied to a new item's template plist, recursing
// through nested dictionaries and arrays (a boost::static_visitor in C++, which
// has no ObjC-shaped equivalent, so it stays here).
NSDictionary* BEExpandVariables (NSDictionary* plist, NSDictionary<NSString*, NSString*>* variables);

// The environment a new item's template expands against: the basic shell
// environment plus TM_ROT13_EMAIL, the obfuscated contact address the Bundle
// properties xib round-trips through the OakRot13Transformer.
NSDictionary<NSString*, NSString*>* BEDefaultTemplateVariables (void);

// MARK: - Commands

// command::fix_shebang — supplies the interpreter line a command body is
// missing, so an edited command still runs.
NSString* BEFixShebang (NSString* command);

// decode::rot13 — the Bundle Editor obfuscates contact e-mail addresses in the
// stored plist, and the Bundle properties xib binds through a value transformer
// registered under the name "OakRot13Transformer".
NSString* BERot13 (NSString* _Nullable string);

NS_ASSUME_NONNULL_END
