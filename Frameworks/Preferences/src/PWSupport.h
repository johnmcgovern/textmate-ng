// The ObjC boundary the Swift Preferences panes sit on (Phase 4).
//
// Same rule as the CommitWindow pilot (CWSupport.h): everything here exists
// because Swift cannot express it directly, or because letting C++ types cross
// into Swift would leak engine details (notably the NULL_STR sentinel, which is
// converted to nil exactly once, here).
//
//  * settings_t is a C++ struct with std::string parameters and defaulted
//    arguments — wrapped as plain NSString functions.
//  * The `mate` install path uses AuthorizationRef, C varargs, and recursive
//    POSIX file operations (oak::execute_with_privileges). None of it is
//    expressible in Swift; it stays C++ behind three entry points.
//  * OakSetupGridViewWithSeparators takes std::vector<NSUInteger> and a default
//    argument; re-exposed taking NSArray<NSNumber*>.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// ============
// = settings =
// ============

// The `settings` keys the panes bind to. Exposed as functions rather than
// constants because the underlying kSettings*Key are C++ std::strings.
NSString* PWSettingsEncodingKey (void);
NSString* PWSettingsLineEndingsKey (void);
NSString* PWSettingsFileTypeKey (void);
NSString* PWSettingsExcludeKey (void);
NSString* PWSettingsIncludeKey (void);
NSString* PWSettingsBinaryKey (void);

// settings_t::raw_get / settings_t::set. `section` (a.k.a. fileType) may be nil
// for the unscoped variant. raw_get returns nil rather than the NULL_STR
// sentinel when unset — the sentinel must never reach Swift.
NSString* _Nullable PWSettingsRawGet (NSString* key, NSString* _Nullable section);
void PWSettingsSet (NSString* key, NSString* _Nullable value, NSString* _Nullable fileType);

// ============
// = grammars =
// ============

// bundles::query over grammars, sorted by name, hidden ones removed. Each entry
// is @{ @"name": …, @"scope": … }; grammars with no scope are skipped.
NSArray<NSDictionary<NSString*, NSString*>*>* PWGrammarList (void);

// ===========
// = general =
// ===========

// format_string::expand — the Terminal pane's status text uses ${var} patterns
// baked into the xib's string values.
NSString* PWExpandFormatString (NSString* format, NSDictionary<NSString*, NSString*>* variables);

// NSGridView layout shared by the grid-based panes. `separatorRows` are the row
// indices that become full-width separators.
NSView* PWSetupGridView (NSGridView* gridView, NSArray<NSNumber*>* separatorRows);

// =========================
// = `mate` shell support  =
// =========================

// Whether writing to `path` would need an admin prompt.
BOOL PWCopyRequiresAdmin (NSString* path);

// Install/uninstall the bundled `mate` tool, escalating through
// AuthorizationExecuteWithPrivileges when the destination is not user-writable.
// Both return whether the operation succeeded.
BOOL PWInstallMate (NSString* srcPath, NSString* dstPath);
BOOL PWUninstallMate (NSString* path);

// `<mate> --version` parsed down to the bare version string, or nil.
NSString* _Nullable PWMateVersion (NSString* matePath);

NS_ASSUME_NONNULL_END
