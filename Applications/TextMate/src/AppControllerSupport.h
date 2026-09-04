// Extracted from AppController.mm ahead of porting it to Swift (rule 25).
//
// -applicationWillFinishLaunching: is 94 lines, and all of its C++ is in three
// clusters that have nothing to do with what the method is *for*: two settings
// paths, the first-launch unpack of DefaultBundles.tbz, and the marker file that
// makes a crash during session restore recoverable. The rest is NSMenu,
// NSUserDefaults, NSAlert and two singletons, which Swift reaches on its own.
//
// The marker is deliberately split into a path and three primitives that take
// one. The original computed `path::join(path::temp(), …)` into a local and used
// it three times; parameterising it changes nothing at the call site — which
// still uses +sessionRestoreMarkerPath — and makes the create/exists/remove
// cycle testable against a scratch file. The real marker lives at a fixed path
// shared with the running app, so a test must never touch it: creating one and
// failing before the cleanup would make the next real launch offer to skip
// session restore (rule 53).
//
// STILL BLOCKING a Swift -applicationWillFinishLaunching:, and neither is C++:
//
//   * `-[NSAlert addButtons:…, nil]` is an ObjC variadic, which Swift cannot
//     call at all (rule 16). NSAlert (Other) declares only variadics, so there
//     is no sibling to use — OakAppKit needs an array-taking spelling.
//   * `RegisterDefaults()` is a C++-linkage free function (Preferences/Keys.h).
//     Rule 19 says Swift can call a global, but that is not settled for a
//     mangled C++ symbol under SWIFT_OBJC_INTEROP_MODE=objcxx; it needs a probe
//     (rule 55) or a one-line shim.
#import <Foundation/Foundation.h>
#import <TMBundleModel/TMScopeContext.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppControllerSupport : NSObject

// settings_t::set_default_settings_path and set_global_settings_path. Both take
// C strings built from a bundle resource and from path::home(), so the NSBundle
// lookup comes along rather than being passed in as an NSString.
+ (void)setupSettingsPaths;

// Unpacks DefaultBundles.tbz into ~/Library/Application Support/TextMate/Managed
// on first launch, by piping the archive into a tar subprocess (network::tbz_t).
// Does nothing once that directory exists. Every failure here is logged and
// swallowed, exactly as before — a missing archive is not fatal.
+ (void)installDefaultBundlesIfNeeded;

// path::join(path::temp(), "textmate_session_restore"). Written before session
// restore and unlinked after, so a crash in between leaves it behind and the
// next launch offers to skip restoring.
@property (class, nonatomic, readonly) NSString* sessionRestoreMarkerPath;

+ (BOOL)markerExistsAtPath:(NSString*)path;
+ (void)createMarkerAtPath:(NSString*)path;
+ (void)removeMarkerAtPath:(NSString*)path;

// MARK: - The key text view's scope
//
// -showBundleItemChooser: finds the text view with
// `[NSApp targetForAction:@selector(scopeContext)]` and asks it two things. The
// second, -hasSelection, is a plain BOOL; the first returns `scope::context_t`,
// and the wrapper that converts it — +[TMScopeContext scopeContextWithCxxContext:]
// — is itself C++-typed, so neither end of that line can be Swift.
//
// This is deliberately *not* an addition to OakTextView. The caller never needs
// that class: `targetForAction:` hands back an `id`, and everything else it does
// with the view (window, -convertRect:toView:, -visibleRect) is NSView API. So
// the boundary belongs here, in the app's own support file, rather than in a
// framework with many consumers.
//
// Both take the target verbatim, **including nil**, because the ObjC++ relied on
// nil-messaging for it (rule 33): with no text view, -hasSelection answered NO
// and the scope fell back to the wildcard. Passing nil is the normal case when
// no document window is key.

// +[TMScopeContext scopeContextWithCxxContext:[target scopeContext]], or the
// wildcard scope when target is nil.
+ (TMScopeContext*)scopeContextForTarget:(nullable id)target;

// [target hasSelection], or NO when target is nil.
+ (BOOL)targetHasSelection:(nullable id)target;

// MARK: - A position string, normalised
//
// `to_ns(text::range_t(text::pos_t(position)))` — parse a position in pos_t's own
// notation and render it back. -editBundleItem: passes the result to
// OakDocument.selection instead of calling
// -showDocument:andSelect:inProject:bringToFront:, whose only use of its
// `text::range_t const&` is that same assignment.
//
// The round trip is NOT a no-op and the string cannot simply be forwarded.
// text::pos_t parses "%zu:%zu+%zu" and stops, so "5-7" is the *point* 5;
// text::range_t, which is what OakDocument.selection is eventually read as,
// splits on "-x" first and would make it the *range* 5 to 7. Normalising here
// keeps the point the original produced.
//
// Not to be confused with +[TxMtURLSupport selectionStringForLine:column:],
// which takes decimal line and column numbers from a URL and converts 1-based to
// 0-based. This one takes a string already in pos_t notation.
+ (nullable NSString*)selectionStringForPositionString:(nullable NSString*)position;

@end

NS_ASSUME_NONNULL_END
