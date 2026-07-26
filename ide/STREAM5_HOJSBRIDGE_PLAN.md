# Stream 5 — HOJSBridge / HTMLOutput → WKWebView migration plan

_Written 2026-07-26, before any code changes. Branch: `claude/xcode-stream1-seed`._

## Status (updated 2026-07-26)

**Slices 1–3 are done and verified in the running app.** Slices 4–5 remain.

| Slice | State |
|-------|-------|
| 1 — scaffold swap (WKWebView, scheme handler, no JS API) | ✅ done |
| 2 — async `TextMate.system()` | ✅ done |
| 3 — synchronous `TextMate.system()` | ✅ done |
| 4 — peripherals (find/pboard/view-source, status text, console relay, `tm-file` handler) | ⬜ |
| 5 — cleanup (delete dead code, try dropping WebKit from the PCH) | ⬜ |

**The plan's two big open questions are both answered:**

1. **Sub-resource loading — was the real problem, and the plan under-rated it.**
   The page is served from a custom scheme, which WKWebView gives an *opaque
   origin*; bundle output references its CSS/JS/images as absolute `file://`
   URLs, so every one was refused. The legacy WebView was exempt only because
   `OakCommand` called `+[WebView registerURLSchemeAsLocal:]`, which has no
   WKWebView equivalent. Fixed by rewriting `file://` to
   `<scheme>://job/__tm_local__` **in the streamed HTML** and serving those paths
   from the scheme handler — same scheme *and* host, so same-origin.
2. **Synchronous XHR against a `WKURLSchemeHandler` works.** This was the
   load-bearing assumption of the whole sync design and it holds. Note
   `WKURLSchemeTask` does **not** receive a POST body, so the command travels
   base64-encoded in a header.

Verification lives in a scratch bundle outside the repo,
`~/Library/Application Support/TextMate/Managed/Bundles/TextMate-NG Dev.tmbundle`:
`⌃⌥⌘J` asserts the async round trip, `⌃⌥⌘K` the synchronous one. Both pages
report their own PASS/FAIL. Delete the bundle when the stream is finished.

**Still unexercised:** the 15-second watchdog path (needs a command that actually
runs that long), and `write()`/`close()`/`cancel()` on the async form.

Legacy `WebView` survives in exactly one framework: `Frameworks/HTMLOutput`
(~1,066 lines across 5 impl files) plus its consumers (`OakCommand`,
`HTMLOutputWindow`, `DocumentWindowController`, `OakCommandRefresh`).
`AboutWindowController.mm` is already on WKWebView and establishes the house
pattern: a `textmate` script-message handler, a `WKUserScript`-injected
`resources/WKWebView.js` defining a JS-side `TextMate` object, and a
callback-id registry (`nextCallbackId` + `callbacks` Map) for async replies.
This plan extends that pattern to the command-output bridge.

## 1. What the bridge does today (inventory)

### The `TextMate` object (HOJSBridge.mm, injected in `didClearWindowObject`)
| API | Semantics |
|---|---|
| `TextMate.system(cmd, null)` | **Synchronous.** Spawns `/bin/sh -c cmd`, blocks JS in a nested `cf::run_loop_t` until exit (15 s watchdog alert), returns `{outputString, errorString, status}`. |
| `TextMate.system(cmd, handler)` | **Async.** Returns a command object: `outputString`, `errorString`, `status`, `onreadoutput`/`onreaderror` (streaming callbacks), `cancel()`, `write(str)` (stdin), `close()` (EOF). `handler` called on exit. |
| `TextMate.log(msg)` | NSLog. |
| `TextMate.open(path, options)` | Open file in TextMate; `options` = line number or selection-range string. |
| `TextMate.busy = bool` | Status-bar spinner (via `HOJSBridgeDelegate` → `HOStatusBar`). |
| `TextMate.progress = 0..1` | Status-bar determinate progress. |

Injection is gated: only when `isRunningCommand` or scheme ∈ {`tm-file`,
`file`}, and never when `disableJavaScriptAPI` (per-command
`disableJavaScriptAPI` flag from the bundle command plist).

### Bundle reality check (audited 2026-07-26 on this machine's Managed bundles)
`TextMate.system(cmd, null)` **synchronous calls with immediate
`.outputString` reads are live** in Git, Ruby, Subversion, Mercurial and
Bundle-Support bundles (e.g. Git's `rb_gateway.js`, Ruby's `linked_ri.rb`).
**Sync semantics are load-bearing; a Promise-only API is not feature parity.**

### Every other legacy-WebKit touchpoint that dies with WebView
| Site | Legacy API | WK replacement |
|---|---|---|
| `HOBrowserView.mm` view creation | `WebPreferences`, `plugInsEnabled` | `WKWebViewConfiguration` (+ shared `WKProcessPool` for reuse) |
| `HOBrowserView.mm` progress | `WebViewProgress*` notifications | KVO on `estimatedProgress` (also satisfies Stream 5's KVO goal) |
| `HOBrowserView.mm` swipe | `goBack`/`goForward` on WebView | same methods exist on WKWebView; or `allowsBackForwardNavigationGestures` |
| `OakHTMLOutputView.mm` `didClearWindowObject` | `WebScriptObject setValue:forKey:` | `WKUserScript` @ document start + `addScriptMessageHandlerWithReply` |
| `OakHTMLOutputView.mm` `mainFrameTitle` | `webView.mainFrameTitle` + manual KVO dance | KVO-compliant `WKWebView.title`; keep a `processName` fallback property |
| `OakHTMLOutputView.mm` policy (`txmt:`) | `WebPolicyDelegate` | `decidePolicyForNavigationAction:decisionHandler:` |
| `OakHTMLOutputView.mm` printing | `printOperationWithView:` on frame view | `-[WKWebView printOperationWithPrintInfo:]` (macOS 11+; floor is 15) |
| `OakHTMLOutputView.mm` `setContent:` scroll restore | `documentView visibleRect` | `evaluateJavaScript` scroll save/restore, or `WKScrollView` is iOS-only → JS |
| `HOWebViewDelegateHelper.mm` status text | `setStatusText`/`mouseDidMoveOverElement` | gone in WK → JS `mouseover` shim posting `{command:"status"}` messages |
| `HOWebViewDelegateHelper.mm` JS alert/confirm | `runJavaScript*PanelWithMessage` | `WKUIDelegate` completion-handler equivalents |
| `HOWebViewDelegateHelper.mm` file open panel | `WebOpenPanelResultListener` | `runOpenPanelWithParameters:` |
| `HOWebViewDelegateHelper.mm` `createWebViewWithRequest` | returns a `WebView` | `webView:createWebViewWithConfiguration:…` (MUST use passed-in config) |
| `HOWebViewDelegateHelper.mm` `webViewClose` + `needsNewWebView` | WebKit bug 121232 workaround | `webViewDidClose:`; the workaround dies. Add `webViewWebContentProcessDidTerminate:` handling instead |
| `HOWebViewDelegateHelper.mm` console log | undocumented `addMessageToConsole` | JS `window.addEventListener("error", …)` shim (About window already does this) |
| `HOWebViewDelegateHelper.mm` `tm-file:`→`file:` + error_not_found + protocol-relative rewrite | `WebResourceLoadDelegate` `willSendRequest` | `WKURLSchemeHandler` for `tm-file`; `decidePolicyForNavigationAction` for the rest. **Sub-resource rewriting is impossible in WK** — see Risks |
| `OakCommand.mm` `OakFileHandleURLProtocol` | `NSURLProtocol` + `registerURLSchemeAsLocal` + properties smuggled on the request | `WKURLSchemeHandler` for `x-txmt-filehandle` + an app-side registry keyed by URL (see §3.4) — request properties do NOT survive into WK navigations |
| `WebView Additions.mm` find/copy-to-pboard | `searchFor:direction:…`, DOM selection walk | `findString:withConfiguration:completionHandler:`; selection via `evaluateJavaScript("getSelection().toString()")` |
| `WebView Additions.mm` `viewSource:` | `WebDataSource data` | `evaluateJavaScript("document.documentElement.outerHTML")` (loses pre-DOM source fidelity — acceptable) or retain streamed bytes app-side (we have them: we serve the stream) |
| `HOAutoScroll.mm` | `WebFrameView`/`documentView` frame notifications | JS-side: `ResizeObserver` + "stick to bottom if at bottom" in the user script |

## 2. The hard constraint

WKWebView is out-of-process. There is **no synchronous ObjC↔JS call in
either direction**:
- JS→native: `postMessage` is fire-and-forget; `addScriptMessageHandlerWithReply`
  returns a **Promise** to JS — still async.
- native→JS: `evaluateJavaScript` is async.

So `TextMate.system(cmd, null)` — which must *block the calling JS statement*
and hand back the exit status — cannot be built from the message-handler
primitives at all.

### The one loophole: synchronous XHR against a WKURLSchemeHandler
A synchronous `XMLHttpRequest` from page JS blocks only the **web-content
process**; the URL scheme handler runs in the **app process** and can take as
long as it needs. This is the standard (if inelegant) pattern for sync bridges
in WKWebView. Deprecated by the HTML spec but fully functional in WebKit, and
our floor is a fixed WebKit (macOS 15+), not the open web.

## 3. Target architecture

### 3.1 JS side — extend `WKWebView.js` (shared with About window)
New user script `HTMLOutput.js` (HTMLOutput-specific; About keeps its own)
defining the full `TextMate` object in JS:

```
TextMate.system(cmd, handler):
  handler === null/undefined →  SYNC PATH:
      sync XHR  POST x-txmt-bridge://system  body={cmd, token}
      → returns {outputString, errorString, status} JSON. 15 s watchdog
        stays app-side (alert offers Stop, handler then completes the task
        with status −1).
  handler is a function     →  ASYNC PATH:
      postMessage {command:"system", cmd, token}; returns a JS-side
      TMCommand object (created immediately, identified by token) with
      outputString/errorString accumulating locally from pushed chunks,
      onreadoutput/onreaderror assignable, cancel/write/close posting
      {command:"systemCtl", token, op, data}.
TextMate.log / open       → postMessage (fire-and-forget)
busy / progress           → defineProperty setters → postMessage
window.status shim        → mouseover/mouseout listeners → postMessage {command:"status"}
error → console relay     → window "error" listener (as in About)
auto-scroll               → ResizeObserver; stick-to-bottom iff currently at bottom
```

Native pushes stream data with
`evaluateJavaScript("TextMate._dispatch(token, kind, chunk)")` — chunks are
UTF-8-safe strings cut with the existing `add_to_buffer.h` logic, which moves
app-side unchanged.

### 3.2 Native side — `HOJSBridge` becomes a `WKScriptMessageHandler`
- One handler object per OakHTMLOutputView, name `textmate`, registered
  `WithReply` (Promise-based) for future use; the sync path goes through the
  scheme handler, not the message handler.
- Keeps: environment map, delegate (`HOStatusBarDelegate` unchanged),
  `io::spawn` + dispatch plumbing from `HOJSShellCommand` (drop
  `cf::run_loop_t` — no nested run loop needed; the sync case blocks in the
  scheme handler's own dispatch work, not on the main thread).
- New: a `token → HOJSShellCommand` registry so `systemCtl` messages and
  `_dispatch` pushes find their process. Registry lives on the bridge;
  cleared on navigation (matches old per-window-object lifetime).
- `WebUndefined` check dies with WebScriptObject; JS decides sync vs async
  and says so explicitly in the message.

### 3.3 Injection gating
`didClearWindowObject` fired per-navigation; WK user scripts are
per-configuration. Replicate the gate at (re)configuration time:
- `disableJavaScriptAPI` → build the config **without** the user script and
  without message/scheme handlers. Config is immutable after creation → a
  change of `disableJavaScriptAPI` (command reuse) forces a fresh WKWebView.
  `OakCommand` already sets it before `loadRequest:…`, and view reuse already
  goes through `htmlOutputView:forIdentifier:` — add "API-enabled matches" to
  the reuse predicate next to `needsNewWebView`.
- scheme gate (`file`/`tm-file`/running-command): keep a `WKUserScript`
  injected unconditionally but have `decidePolicyForNavigationAction` set a
  per-navigation flag pushed into the page (`TextMate._enabled`), OR simpler:
  since HTML output only ever loads `x-txmt-filehandle`, `tm-file`, `file`
  and command-generated `loadHTMLString`, inject always and rely on
  `disableJavaScriptAPI` for the untrusted case. **Decision: simpler path;
  document the delta.** External http(s) pages opened via links navigate the
  main frame — add scheme check in `decidePolicyForNavigationAction` to strip
  API on non-local navigations by loading them in a fresh non-API view (same
  as today's effective behavior, since didClearWindowObject re-fired and
  skipped injection for http).

### 3.4 Streaming command output — replace `OakFileHandleURLProtocol`
- `WKURLSchemeHandler` registered for `x-txmt-filehandle` on the config
  (`setURLSchemeHandler:forURLScheme:`).
- `NSURLProtocol propertyForKey:` smuggling does not survive WKWebView's
  request copying → replace with an app-side registry:
  `OakCommand` registers `{URL → (fileHandle, processIdentifier, processName,
  commandIdentifier, command)}` before calling `loadRequest:`; the scheme
  handler and `OakHTMLOutputView` look up by `task.request.URL` /
  `navigationAction.request.URL`. Unregister on stream close (existing
  removePropertyForKey sites map 1:1).
- Handler reads the pipe on a background queue exactly as `startLoading`
  does today, calling `didReceiveData` on the main queue; honors
  `stopURLSchemeTask` → `kill_process_group_in_background` (existing
  `stopLoading` logic).
- `tm-file` gets its own small scheme handler doing the file resolution +
  `index.html` + `error_not_found` logic from `HOWebViewDelegateHelper`
  (main-document only — see Risks for sub-resources).

### 3.5 View/plumbing swap (mechanical)
- `HOBrowserView`: `WKWebView` + shared `WKProcessPool`; KVO on
  `estimatedProgress`, `title`, `canGoBack`/`canGoForward` (all
  KVO-compliant) → status bar. `HTMLOutputWindow`'s
  `bind:NSTitleBinding … "mainFrameTitle"` re-points at a new
  `title`-derived property (keep `mainFrameTitle` name, KVO-bridged, with
  `processName` fallback so window titles don't regress while loading).
- `OakHTMLOutputView`: `loadRequest:` → `loadRequest:` (WK has it);
  `setContent:` → `loadHTMLString:baseURL:` (WK has it) + JS scroll
  save/restore; stop-loading sheet logic unchanged (WK `stopLoading` works;
  the `OakCommandDidTerminateNotification` dance is WebView-agnostic).
- `WebView Additions.mm` → `WKWebView Additions.mm`: find via
  `findString:`, pboard copy + `viewSource:` via `evaluateJavaScript`.
  All four consumers (menu actions, `Find.mm` responder-chain
  `performFindOperation:`) keep their selectors.
- `HOAutoScroll` deleted (JS ResizeObserver in user script);
  `helpers/add_to_buffer.h` survives unchanged.

## 4. Sequencing (each slice builds + is manually verifiable)

1. **Scaffold swap** — `HOBrowserView`/`OakHTMLOutputView` on WKWebView with
   scheme-handler streaming (§3.4, §3.5) but NO JS API. Verify: run a bundle
   command with HTML output (e.g. Markdown preview, `git log`), output
   streams, title/progress/back-forward work, `txmt:` links open files,
   window placement setting works, stop-command sheet works.
   `disableJavaScriptAPI` commands are already fully correct after this slice.
2. **Async bridge** — user script + message handler + process registry +
   `_dispatch` streaming + busy/progress/log/open. Verify with a test
   command using async `TextMate.system` (Subversion `Status.js` uses the
   streaming callbacks; or a purpose-built test page exercising
   onreadoutput/write/close/cancel).
3. **Sync bridge** — `x-txmt-bridge` scheme handler + sync-XHR path + 15 s
   watchdog. Verify: Git bundle `rb_gateway.js` round-trip, Ruby
   `linked_ri`, the `(null)` calls found in the audit.
4. **Peripheals** — find/pboard/view-source additions, JS alert/confirm/open
   panel, `window.open` (`createWebView`) + `webViewDidClose`, status-text
   shim, printing, console relay, `tm-file` handler.
5. **Cleanup** — delete `HOAutoScroll`, `WebView Additions.mm`,
   `HOWebViewDelegateHelper` legacy paths, the `needsNewWebView` plumbing
   (`OakCommand.mm`, `DocumentWindowController.mm` predicate) — replaced by
   process-termination handling; drop `<WebKit/WebKit.h>` from
   `Shared/PCH/prelude.m` if AppController allows → potentially retire the
   option-4 no-umbrella farm variant in the Xcode seed (flagged in
   NEXT_SESSION_HANDOFF as a Stream 5 simplification).

Slices 1–3 are sequential; 4's items are independent of each other; 5 last.
Commit per green slice on `claude/xcode-stream1-seed` per repo convention.

## 5. Risks / open questions

- **Sync-XHR longevity.** Sync XHR is spec-deprecated; WebKit still supports
  it with no announced removal (macOS 15/26 SDKs). Mitigation: the JS shim is
  the only place that knows — if WebKit ever drops it, only
  `HTMLOutput.js` changes strategy (e.g. to a busy-wait on Atomics/
  SharedArrayBuffer or acceptance of async-only). Bundle sources untouched.
- **Sub-resource URL rewriting is gone.** Old `willSendRequest` rewrote
  `tm-file:` and protocol-relative URLs for EVERY resource (imgs, css).
  WK scheme handlers cover custom schemes; `file:` sub-resources inside
  scheme-handler-served pages need `loadHTMLString` baseURL discipline or
  the tm-file handler serving them. Audit real bundle output in slice 1;
  x-txmt-filehandle pages referencing `file:` assets may need
  `WKWebViewConfiguration.setValue:@YES forKey:@"allowUniversalAccessFromFileURLs"`-
  style private API — avoid; prefer serving assets through `tm-file`.
  **Open until slice-1 testing.**
- **`loadHTMLString` + `file:` base URL sandboxing.** `setContent:` uses
  `baseURL:file://~`; WK restricts file access from HTML strings. May need
  `loadFileURL:allowingReadAccessToURL:` via a temp file, or accept the
  restriction (output that references local images). Test in slice 1 with
  `updateHTMLViewAtomically` commands (output-reuse mode).
- **Process-pool/view reuse semantics.** The `needsNewWebView` (bug 121232)
  workaround is obsolete, but WK adds a new failure mode: web-content
  process termination. `webViewWebContentProcessDidTerminate:` must mark the
  view non-reusable (`reusable = NO`) so `DocumentWindowController`'s reuse
  predicate skips it.
- **15 s watchdog UX.** Old code showed the alert from inside the nested run
  loop on main. New sync path blocks only the page; the watchdog timer +
  alert run normally on main. Strictly better, but "Stop Command" must fail
  the pending XHR (return status −1 JSON) or the page hangs forever.
- **`disableJavaScriptAPI` reuse edge.** New constraint (config immutability)
  → reuse predicate change in TWO places (`OakCommand.mm:615` area,
  `DocumentWindowController.mm:1236` predicate). Miss one and a trusted
  command inherits an API-less view (or worse, inverse).
- **Bundle audit breadth.** This machine's Managed set is not the universe.
  The sync/async audit should re-run against the full default-bundle set
  once default-bundles provisioning lands in the Xcode world (tracked in
  PROJECT_PHASES.md).

## 6. Explicit non-goals of Stream 5 (first pass)

- No SwiftUI/Swift — that's Phase 3+.
- No redesign of the bundle-facing `TextMate.*` API. Bundles run unmodified;
  the documented contract (Dashboard-era `system()` semantics, §HOJSBridge.mm
  comments) is the spec.
- About window untouched (already WK).
- `AboutWindowController`-style callback-Promise modernization for bundle
  JS is available for NEW bundle code via the WithReply handler, but nothing
  existing moves to it in this stream.
