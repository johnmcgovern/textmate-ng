// The C++ half of OakAppKit's Swift files — the same shape as
// DocumentWindowSupport.mm and FindSupport.mm, and the same rule: the
// *decisions* stay in the Swift. Nothing here chooses anything.
//
// Note the direction. Swift cannot *define* a function visible to ObjC, which
// is why OakShowPopOutAnimation stays in its own .mm — but it can freely *call*
// one declared here. Everything below is that second kind: an ObjC-typed entry
// point onto something Swift cannot name.
#import <Cocoa/Cocoa.h>

// ============================================================
// = Key equivalents                                          =
// ============================================================

// ns::glyphs_for_event_string — "@$s" becomes "⇧⌘S". Returns the empty string
// for an empty input, which is what the caller's placeholder test relies on.
NSString* OakGlyphsForEventString (NSString* eventString);

// ns::glyphs_for_flags — the modifier glyphs alone, for the live display while a
// key equivalent is being recorded and no key has been pressed yet.
NSString* OakGlyphsForModifierFlags (NSUInteger flags);

// ns::to_s(NSEvent*) — an event as the string TextMate stores key equivalents
// in. The C++ has a second `preserveNumPadFlag` parameter defaulted to false;
// the one caller here never passed it, so it is not a parameter.
NSString* OakEventString (NSEvent* anEvent);

// ============================================================
// = Symbolic hot key mode                                    =
// ============================================================

// PushSymbolicHotKeyMode/PopSymbolicHotKeyMode are undocumented HIToolbox calls
// that suppress the system's own ⌘-shortcuts while a key equivalent is being
// recorded — without them, recording ⌘Space opens Spotlight instead.
//
// Behind a shim for two reasons: the token is a bare `void*`, and an
// undocumented API is worth having exactly one call site for, so the day it
// stops existing there is one place to change.
void* OakPushSymbolicHotKeyModeAllDisabled (void);
void OakPopSymbolicHotKeyMode (void* token);
