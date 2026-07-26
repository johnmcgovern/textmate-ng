#ifndef PRELUDE_M_PCH_KZLXVFRT
#define PRELUDE_M_PCH_KZLXVFRT

#include "prelude.c"
#include "prelude-mac.h"

#import <objc/objc-runtime.h>
#import <AddressBook/AddressBook.h>
#import <Cocoa/Cocoa.h>
#import <ExceptionHandling/NSExceptionHandler.h>
#import <CoreFoundation/CFPlugInCOM.h> // must be loaded before QuickLook.h
#import <Quartz/Quartz.h> // includes the private QuickLookUI.h

/*
	WebKit stays in the shared prefix header. Stream 5 tried to remove it — the
	Stream 1 notes suggested the WKWebView migration would allow it — and it does
	not work, for two reasons worth recording so nobody repeats the experiment:

	1. PlugIns/dialog/Commands/tooltip/TMDHTMLTips.mm still uses the legacy WebView
	   (WebFrameLoadDelegate, WebPreferences). It lives in the `dialog` submodule,
	   which this project treats as out of scope for edits.
	2. Even with that fixed, the include-farm collision would remain. It is a
	   *per-target* problem, not the per-TU one PHASE2_PROGRESS.md described: the
	   TextMate app requires TextMate's own `network` framework, so its farm
	   include path carries a `network` directory, and any WebKit-using TU in that
	   target (AboutWindowController.mm) resolves the umbrella's
	   <Network/Network.h> to it on a case-insensitive filesystem.

	So the seed's no-umbrella farm variant (GEN_INCLUDE_NOU) has to stay.
*/
#import <WebKit/WebKit.h>

#endif /* end of include guard: PRELUDE_M_PCH_KZLXVFRT */
