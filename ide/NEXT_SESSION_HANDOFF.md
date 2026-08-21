# Next-session handoff — TextMate-NG

_Snapshot at end of session 2026-08-18. Point-in-time; when it disagrees with the
git log or the docs below, trust those. The section this file used to end with —
"Next: port DocumentWindowController … now unblocked" — got three things wrong
about that port, which is a fair warning about how much to trust the rest._

## Where things stand (updated 2026-08-18)

- **Phase 2 is DONE.** Stream 3 (signing & notarization) landed: Developer ID
  `John McGovern (R22V2H7QF4)`, `bin/notarize` drives `notarytool`, and shipped
  builds are notarized and stapled. Build a release with
  `TM_CODE_SIGN_IDENTITY`/`TM_DEVELOPMENT_TEAM` set, then run `bin/notarize`.
- **The app ships as `TextMate-NG.app`, id `com.j23software.TextMate-NG`**
  (id moved 2026-08-03, for alpha.6). The *target* is still named `TextMate` and
  must stay that way — renaming it drags `PRODUCT_MODULE_NAME` to `TextMate_NG`
  and breaks `#import "TextMate-Swift.h"` (`102162ec`) — so the id is now a
  **literal** in the seed rather than derived from `${TARGET_NAME}`.
  The old note here said the id "must not move again"; it moved once more, on
  purpose, to match the product name while the audience was still alpha-only.
  Now it does match, so there is no third move worth making.
- **Eight releases are published:** alpha.7 through alpha.14, the newest
  `v2026.8-alpha.14` on 2026-08-18. (alpha.3–alpha.5 shipped 2026-08-02/03 but
  were never backfilled to GitHub — see the end of "Distribution".) **3 commits
  are unreleased and unpushed as of 2026-08-18** — the SCMManager shim, the
  preference-class `final` fix, and the window-chrome theme change. Count what is
  unreleased with `git rev-list --count "$(git tag | sort -V | tail -1)"..HEAD`
  rather than by assertion — that number has been stated wrong here three times,
  this bullet was stale for five releases and then again for two, and it is
  cheaper to run the command than to trust the sentence.
  **The crashes are understood and shipped fixed in alpha.15 — see "RESOLVED"
  below.** They were one heap-corruption bug (`dc66d10d`), reproduced deterministically
  and gone on HEAD. The `final` audit that completes the fix landed as `142b0059` (56
  classes, 42 files), and `v2026.8-alpha.15` (`824e4f4e`) is tagged and published
  carrying both. The gate is cleared; this bullet is kept only as the trail.
- **Builds are downloadable.** `bin/release` publishes a notarized build to
  GitHub Releases. The flow has been run six times and verified from the outside
  — download the published asset, set `com.apple.quarantine`, check `spctl`. As
  of alpha.13 a release carries **two** assets, the app and its dSYMs. See
  "Distribution" below.
- **Phase 4's Find work is DONE (2026-08-07).** All four substantial files are
  Swift — `FFResultNode`, `FFDocumentSearch`, `FFResultsViewController` and now
  `Find.mm` (1402) — each with its tests written *before* the port. The framework
  went from **zero tests to 76** and from 3123 lines of ObjC++ to **1107**. The
  last port left `FindSupport.mm` (271) behind, which is why the directory fell
  by 1131 and not by 1402. What it cost, and the four new rules it earned, are in
  `ide/FIND_PORT_HANDOFF.md`.
- **658 tests across 36 bundles**, green (measured 2026-08-18 at `7dde4c06`;
  76 Find, 51 DocumentWindow, 29 OakAppKit). Counted from `Test Case … started` lines, which
  is what the rest of this bullet has been telling people to do — and which is
  how the 58 previously claimed for DocumentWindow was caught: it was never
  measured, the bundle ran 48. Re-measure by summing each bundle's own `Executed N tests`; do not
  increment the documented figure. **Match `Executed ([0-9]+) tests?,` — with the
  `s` optional.** xctest prints `Executed 1 test` for single-test suites, and a
  plural-only pattern skips those lines and then mis-attributes the next
  bundle's total, which reads as 500 instead of 484. **And take only the
  *bundle-level* lines.** xctest prints an `Executed …` summary for every nested
  suite as well — 203 lines for 36 bundles — so summing all of them reads as 1947
  (2026-08-18). Filter to the line that follows a `Test Suite '…xctest' passed`.
  Cross-check that `Test Case … started` and `… passed` counts are equal; the two
  methods agreeing is the only reason to believe either. Full note in
  `PROJECT_PHASES.md` under the test-count corrections.
- **QuickLook works again, as a Preview Extension (2026-08-03).** Legacy
  `.qlgenerator`s no longer load from *any* third-party app on this macOS, so it
  was rewritten as a sandboxed `TextMateQL.appex` in `Contents/PlugIns`. The
  scary part — moving the app's storage into an app-group container — turned out
  to be unnecessary: `temporary-exception` entitlements let the sandboxed
  extension read the real paths. A throwaway probe extension established that in
  one run; write one before scoping this kind of work. Full notes in
  `PROJECT_PHASES.md` under "Phase 2.6 — QuickLook".
- **The "About box shows 2.0.23" bug was never a bug.** That window belonged to
  the *installed upstream TextMate*, which answered the About click while both
  apps presented identically in the menu bar. The alpha.5 rename makes the
  mixup impossible. Beware generally: with upstream installed, confirm *which*
  app you are looking at before believing a UI screenshot.

## Where things stood at 2026-07-26

- **Branching: trunk-based, single branch.** Everything lives on `master`, which
  is in sync with `GH-johnmcgovern/master`. The old `claude/xcode-stream1-seed`
  and `claude/upbeat-galileo-eae114` branches were merged and deleted on
  2026-07-26 (tips were `0fba3af2` and `119d34a1` if anything ever needs
  recovering). Work on `master` and push; the solo-developer preference is to
  land changes on trunk regularly rather than accumulate long-lived branches.
- **Phase 2 streams 1, 2, 4, 5, 6: DONE.** Stream 3 (signing/notarization) is the
  only stream left and is blocked on the user's Apple Developer certificates.
- **The app really works.** `xcodebuild -target TextMate` produces an ad-hoc
  signed `TextMate.app` that launches, opens and edits documents, runs bundle
  commands, and renders HTML output with its stylesheets, scripts and images.
  Verified interactively, not inferred.
- **Branding:** TextMate-NG, calendar-versioned (`2026.7-alpha.1`), own icon.
  The version is the newest `## <date> (vX)` heading in
  `Applications/TextMate/about/Changes.md` — both build systems grep it, so
  adding a heading *is* the version bump.

## The one lesson this project keeps re-learning

**A green `xcodebuild` and a passing `codesign --verify --deep --strict` prove the
bundle is internally consistent. They do not prove it works.** Three separate
defects of exactly this shape were found in one session, each in an app that
built and signed perfectly:

1. Xibs were never compiled → the app could not launch at all.
2. Framework resources were never copied → Bundle Editor and Preferences had no
   nibs.
3. `-ObjC` was missing → *every* Objective-C category was stripped, so File ▸ New
   silently did nothing.

Run the binary. Open a document. Click the thing.

**And then look at what you are running, not at what you believe you launched.**
The empty gutter (2026-08-13) survived every shipped alpha because nobody
compared the app against upstream side by side; it was reported by a user, not
by the suite. Two further traps surfaced while chasing it, both of which had
already been written down here and both of which caught us anyway: an
identically-titled *upstream* window sitting exactly over the fork's, and a
half-hour spent doubting the screenshot pipeline instead of the app. The cure for
both is to make identity checkable rather than assumed — resolve a window id with
`CGWindowList`, capture with `screencapture -l <id>`, and embed a
`NSLog(@"BUILD %s %s", __DATE__, __TIME__)` you verify against the compile minute
before trusting a single pixel.

A fourth instance of the same shape turned up on 2026-07-26: the `bl` tool had
**never once compiled** in the Xcode project. Nothing depended on it, so nothing
ever asked it to build, and its absence was invisible until Stream 8 made the app
depend on it. A target existing in the project is not evidence it builds — only
`AllLibs`, the app, and now the test bundles are actually exercised.

Two diagnostic traps that cost real time, both worth remembering:

- `nm`/`otool` finding a **selector name** proves nothing — callers put selector
  names in the method-name table. Only `__objc_catlist` shows whether a category
  implementation linked.
- `mate` addresses TextMate by bundle id, so with an upstream TextMate.app
  installed it may drive *that* one. Use `open -a <path>` to be certain which
  binary you are testing.
- **`open -a <path>` is only as certain as the path.** The product is
  `build/<config>/TextMate-NG.app` since alpha.5; a pre-rename
  `build/Debug/TextMate.app` sat there for a day afterwards and launched happily,
  running yesterday's code while `xcodebuild` reported the *current* target
  built. It cost half an hour on 2026-08-02 and read exactly like a broken port.
  `build/` is gitignored and disposable — when a run disagrees with a build,
  check the product's mtime first, and delete stale bundles rather than reasoning
  about them.

## Documentation map (read in this order)

1. **The numbered rules — all 49 of them, now in one file: `ide/RULES.md`.**
   **Read it before surveying a framework.** They used to be split 1–22 in
   `ide/FIND_PORT_HANDOFF.md` and 23–49 in `ide/FILEBROWSER_PORT_HANDOFF.md`, and
   this entry pointed at one file while saying "22 of them" — so anyone following
   the map read a third of the list and believed they had read all of it. That is
   fixed (2026-08-18): the rule statements were consolidated verbatim into
   `ide/RULES.md` and both handoffs now carry a pointer stub. Numbering is stable
   and cross-referenced by number everywhere — append new rules at the end of
   `RULES.md`, never renumber.
2. `PROJECT_PHASES.md` — the 6-phase roadmap and the running record. End state =
   Swift app shell over the kept C++ core. **Phase 4 is current** (Phases 1–3 and
   2.5/2.6 are done); Phase 6, the core engine, is deliberately skipped, which is
   why `OakTextView` (6917) and `document` (3250) are out of scope.
3. `ide/PHASE2_PROGRESS.md` — Stream 1 detail: how the two seed scripts work,
   every solved gotcha, and two corrections to earlier claims that were wrong.
   **Don't re-derive these.**
4. `ide/STREAM5_HOJSBRIDGE_PLAN.md` — the WKWebView migration, complete, with the
   two design questions it answered.
5. `ide/gen_xctest.rb` + `ide/xctest_preamble.h` — how the OAK-style tests become
   XCTest bundles, and why everything compiles as ObjC++ with ARC off.

## How to build and run

```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 RUBYOPT="-EUTF-8"
export PATH="$HOME/.gem/ruby/2.6.0/bin:$PATH"     # xcodeproj gem
ruby ide/extract_specs.rb > ide/gen/specs.json && ruby ide/seed_xcodeproj.rb
xcodebuild -project TextMate.xcodeproj -target TextMate -configuration Release build
open -a "$PWD/build/Release/TextMate-NG.app"     # target TextMate, product TextMate-NG
```

Tests (35 bundles, 601 green):

```bash
xcodebuild test -project TextMate.xcodeproj -scheme AllTests -configuration Debug
```

Requires Xcode selected (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`)
and `brew install capnp ragel ninja multimarkdown boost google-sparsehash`.

## Framework status, framework by framework

_This section is history and pointers. The actual next job is under
**"Next: `FileBrowser` (4968) or `OakFilterList` (2757)"** below._

**Find is finished.** `Find.mm` landed 2026-08-07 as `Find.swift` (1533) plus
`FindSupport.mm` (271), with 26 tests written against the ObjC++ first. The two
decisions this section used to carry were both settled, and one of them differently
than either of the recorded plans said:

1. **Nothing in the headers forced ObjC++**, per the `f9bb0414` probes — but the
   port put every C++ type behind `FindSupport.h` anyway, including an ObjC++
   category carrying the whole `OakFindServerProtocol` conformance. `Find.swift`
   contains no C++ at all. One declared boundary per framework beat C++ spellings
   scattered through a window controller.
2. **The two menus were hand-rolled**, as planned, and `MenuBuilder` was not
   touched. The trap was in `MBCreateMenuItem`, not the call site: a nil title
   makes a *separator*, so the placeholder item is one.

The unforeseen piece was `Find.h`: it declared both `@interface Find` and the
three types the Swift needs, so it had to be split into `FindTypes.h`. Expect
that shape again — check for it while surveying the next public header.

**`DocumentWindow` is done (2026-08-12).** The window controller is Swift; what
is left in `src/` is `DWScopeContext.mm` (312), `OakDocumentControllerWindows.mm`
(200) and the `DocumentWindowSupport.mm` boundary (415).

**`OakAppKit`'s portable leaves are done (2026-08-13)** — eight files, `.mm`
4825 → 3922. Its own section below explains why most of the remainder is waiting
on its callers rather than on effort.

**alpha.9 shipped 2026-08-10** (`921f2270`, tag `v2026.7-alpha.9`); 9 commits sit
on top of it as of 2026-08-13. A release is a heading in `Applications/TextMate/about/Changes.md`, then
`bin/notarize` and `bin/release` — the full sequence is under "Distribution".

Three earlier notes here were wrong about the unreleased-commit count — "five
commits, nothing user-visible", "21 commits waiting", "nothing has shipped since
alpha.6" — each asserted rather than counted.
`git rev-list --count <tag>..HEAD` is the whole of the work.

~~**Then Phase 3** (Swift interop foundation)~~ — **done long ago**; this line
survived from the session that wrote it. Modules, C++ interop mode, bridging
headers and the first `.swift` file all landed, and there are nine Swift
frameworks now.

## Done: DocumentWindowController (2573 lines → 2343 Swift, 2026-08-12)

`636c6d5b`, on top of `2ff2a1de`. Full account in `PROJECT_PHASES.md` under
"Phase 4 — DocumentWindowController"; what follows is only what changes how the
*next* port should be approached.

**The two-commit shape is the part worth copying.** `2ff2a1de` moved every piece
of C++ out of the controller while it was still ObjC++, so the existing 583 tests
judged each shim before any Swift existed. The Swift commit was then a
translation, not a translation *and* a boundary design. Every earlier port in
this project did both at once, and this one was much easier for not doing so.

**The plan this file used to carry was wrong three ways, so weigh the next one
accordingly:**

1. "Ten C++-typed selectors" was **five**, and only four are forced by callers
   elsewhere. `titleForDocument:withSetting:` had no external caller at all — its
   `std::string` was a free choice. `scopeAttributes` needed the category for a
   different reason than the one given, and in the end did not need it at all.
2. **C++ in *block* signatures** was the real obstacle and went unmentioned.
   `-loadModalForWindow:completionHandler:` and `-saveModalForWindow:…` hand their
   block an `oak::uuid_t const&`; `OakSavePanel` takes an `encoding::type` and
   passes one back. That is the document-open path and all three save paths.
3. **ObjC variadics** are a third thing Swift cannot call, with no C++ in them at
   all — `-addButtons:`, `+tmAlertWithMessageText:…buttons:`.

Rules 15–18 in `ide/FIND_PORT_HANDOFF.md` are these, written as checks to run.

**Two defects survived a green suite, a clean build and a successful launch.**
`-goToRelatedFile:` was never ported (a greyed-out menu item; action dispatch is
by selector, so nothing catches it), and
`-performDropOfTabItem:fromTabBar:index:toTabBar:index:operation:` was spelled
with Swift's `from:`/`to:` against an `@optional` protocol — it compiled,
exposed no selector, and tab drag-and-drop was dead with no warning anywhere.
Both were found by opening the app.

**So: start the next port by writing the selector-surface test, not by writing
Swift.** `t_document_window_controller.mm` has the pattern — every action in the
public header, every delegate protocol method (`@optional` ones especially), and
every C++-typed category selector, asserted with `-instancesRespondToSelector:`.
It caught the second defect on its first run and would have caught the first.

## Done: OakAppKit's portable leaves (2026-08-13)

Eight files Swift, `src/`'s `.mm` **4825 → 3922, measured**, this framework's
tests 14 → 29. `d8f7ac4e`, `2912e3cb`, `1df5ed0b`, `965970be`. Full account in
`PROJECT_PHASES.md`; the transferable part is rules 19–22 in
`ide/FIND_PORT_HANDOFF.md`.

**The one thing to absorb before touching this framework again:** most of what is
left is *not* waiting on effort, it is waiting on its callers. Swift cannot
export a free function or an `extern` constant, and `OakUIConstructionFunctions.h`
alone is 14 free functions with 31 consumers. Porting those today buys a
forwarder `.mm` per function and nothing else.

What remains, and why each is where it is:

| file | lines | status |
| --- | --- | --- |
| `OakPasteboard` | — | **done** (`0389638f`, Swift); its store/observer/constants/find-options are the new boundary files |
| `OakPasteboardChooser` + `OakPasteboardSelector` | — | **done** (`b89edee4` / `dab6b442`, Swift); whole pasteboard cluster is now Swift |
| `OakUIConstructionFunctions`, `OakAppKit.mm`, `OakSound`, `OakToolTip`, `NSColor`/`NSAlert Additions` | ~700 | deferred: free functions / C variadics, want Swift callers first |
| `OakEncodingPopUpButton` | 345 | not surveyed; 23 C++ hits, the densest left |
| `NSMenuItem Additions` | 234 | C++-typed selectors, needs a support split |
| `OakOpenWithMenu`, `OakSavePanel` | 329 | not surveyed |
| `OakRolloverButton` | 176 | blocked by rule 21 — see below |
| `OakSyntaxFormatter` | 115 | holds a `parse::grammar_ptr` **ivar**; needs the `DWScopeContext` treatment |
| `NSSavePanel Additions` | 41 | `+initialize` needs a new home first |
| `OakView` | 51 | four `extern` mask constants would have to stay in a `.mm` |

`OakRolloverButton` is the interesting blocker and the one to fix deliberately:
its header is imported **at line 1 of `OakUIConstructionFunctions.h`**, which the
bridging header needs, so defining the class in Swift breaks every use as
`__ObjC.X` vs `OakAppKit.X`. Splitting that header is a change 31 files see, and
it unblocks more than one port — worth doing on purpose rather than mid-port.

## Next: finish `FileBrowser` (~572 lines left), then `OakFilterList` (2757)

**`FileBrowser` is most of the way ported, not waiting to start** — this section
said otherwise until 2026-08-18, and every one of the four things it listed as
"worth knowing in advance" had already been dealt with. Read
`ide/FILEBROWSER_PORT_PLAN.md`, whose Progress section is current. Measured
2026-08-18: **4683 lines of Swift against 1168 of ObjC++, and 46 tests** in a
framework that genuinely did have none.

**As of 2026-08-18 exactly one portable file is left: `SCMManager.mm` (365).**
`FSEventsManager` is Swift (`1ce283bd`) and the dead
`-addObserverToFileAtURL:usingBlock:` is gone (`a1c4…`, see the log). `src/*.mm`
is **1005**, and the other 640 lines are boundaries that are *finished by design*
— the `…Cxx.mm` / `…Support.mm` files, plus `FSEventStream.mm`, which exists
precisely to hold the C++ struct.

**The table this section used to carry was wrong about 44 of those lines**, and
the mistake is instructive: it listed `FileBrowserOutlineViewKeyBindings.mm`,
`FileBrowserNotifications.mm` and `FileItemLocations.mm` as remaining work. Run
the rule 19/21 survey and all three are rule-19 blocked by construction — they
are `extern` constants and one C++ key-equivalent helper, and each says so in its
own header comment. They were *created* by this port, not left behind by it.
Counting `.mm` lines is not the same as counting work.

`SCMManager.mm` is a session of its own and wants the two-commit shape. It has
the densest C++ left in the framework: a `scm::driver_t const*` **pointer ivar**,
a `std::map<std::string, scm::status::type>` property, `scm::status::type` return
types, and the driver table. `SCMManagerCxx.h` is now down to that one map
property, so it is one property away from not existing.

The resolved preconditions, so nobody re-checks them: the `.rave` globs have
`swift`, `SCMManager.h` is C++-free, `FSEventsManager` no longer holds a
`shared_ptr` ivar, and the bridging-header/hand-declared-`.h` arrangement is
settled and proven.

`OakFilterList` is **now surveyed and half ported** — see the OakFilterList section
near the end of this file for what is done, what is left, and rules 50–51. The notes
below predate that work and are kept only for the two items still standing
(`FileBrowserViewController`'s `variables`, and the MenuBuilder/HTMLOutput ordering):

- `FileBrowserViewController` declares `- (std::map<std::string, std::string>)variables`,
  so it has the `OakTextViewDelegate` shape of problem already, and
  `DocumentWindowController` calls it — that shim exists.
- **Start with the selector-surface test** (rule 18), then survey with the
  checklist rules 15–17 and 19–21 now encode: block parameters, C variadics,
  C++ *ivars*, `+initialize`, free functions and `extern` constants in the
  public header, and whether that header is imported by another public header.
- `MenuBuilder` goes **last**, once its ObjC++ callers are gone. `HTMLOutput`
  needs a `std::map` API redesign before it is portable at all.

## The gutter bug, and why it belongs in a handoff

`6b419366` fixed line numbers, fold markers and bookmarks being **invisible in
every shipped alpha** on macOS 26. One line: `OakBackgroundFillView -drawRect:`
filled `aRect` unexamined, and on this SDK AppKit hands a `wantsLayer` view
created at `NSZeroRect` a contents proxy sized to the whole window — so a 1-point
divider painted 904×800 and buried the gutter behind it.

Three things to carry forward:

1. **This was reported by a user, not by 601 tests, and not by any port.** It
   predates every Swift file in the project. When something looks wrong in the
   app, A/B against the last shipped build *and* against upstream before assuming
   the current work caused it — and after that, suspect the app before the tools.
2. **Bisect the view out early** (rule 22). Six increasingly exotic facts about
   `GutterView` were all true and all irrelevant; replacing it with twelve lines
   that fill themselves red would have exonerated it in ten minutes.
3. **Every `OakCreateVerticalLine` divider was liable to the same overpaint** —
   file browser, HTML output, status bars. If some other view is mysteriously
   blank, this is now the first thing to check, and the fix pattern is
   `NSRectFill(NSIntersectionRect(aRect, self.bounds))`.

## Done: the package-size pass (2026-08-18)

`01698794` and `a83a9005`. **37 MB → 26 MB installed, 19.3 MB → 15.2 MB
downloaded**, with no change to what the app does. The detail is in those two
commit messages and in the code comments; what belongs here is the two things
this got wrong first, because both are the shape of mistake that would repeat.

**"Obsolete format" is not the same as "unused size".** The 54 document icons
carry `is32`/`il32`/`it32`, which read as pre-10.5 cruft to delete. They are old
*encodings* but they hold the only 16/32/128px **sizes** those icons have —
deleting them would have made the file browser resample everything from the
512px rep. What was actually recoverable was the encoding, losslessly: the 128px
pair costs 32 KB (its mask is an uncompressed 16 KB) against 12 KB as PNG, and
every PNG rep was under-compressed by ~18%. Same pixels, 2.2 MB. Check what a
thing *contains* before concluding it is redundant.

**Raw size and download size are different questions, and only one of them was
the ask.** `About/Contributions.html` is 1.6 MB and looks like the obvious
target. 600 KB of it is repeated per-commit markup — which compresses to 28 KB,
because it is identical boilerplate and gzip erases it. Trimming it would have
been a day's fiddling for nothing a user could measure. Measure compressed
before optimising anything that ships inside a zip.

Two mechanisms worth knowing about before touching this again:

- **`Applications/TextMate/icons` is a submodule**, so the icons ship exactly as
  upstream encoded them and cannot be edited in place. `ide/optimize_icons.rb`
  re-encodes them into `ide/gen/icons/` at seed time (cached on mtime; ~6 s cold,
  free warm) and `seed_xcodeproj.rb` rewrites the spec inputs so every consumer
  picks the generated ones up. The same constraint is why the unused 1.7 MB
  `icons/TextMate.icns` is *subtracted* in `extract_specs.rb` rather than deleted.
- **Release is stripped and now emits dSYMs.** `xcodebuild build` never strips on
  its own — only the `install` action sets `DEPLOYMENT_POSTPROCESSING` — so every
  alpha through alpha.12 shipped its full symbol table. Worth recording that the
  obvious objection is wrong: stripping does **not** cost ObjC method names in
  crash reports, all 3746 survive `strip -x`. The dSYM is what recovers file/line
  and the C++ frames.

And one trap, caught by asserting rather than looking: `.iconset` has no 48×48
slot, so an `iconutil` round-trip **silently drops** `ih32`/`h8mk` from the nine
`TextMate *.icns` that carry one. Nothing errors, and the icons still draw. If
you ever transform these again, diff the *set of sizes* before and after rather
than eyeballing the result.

## The Software Update crash, and what the dSYMs bought

`1d587756`, shipped in alpha.14. Settings ▸ Software Update killed the app a
minute or so after the pane was opened, in **alpha.12 and every release before
it** — not an alpha.13 regression, though that is where it was reported.

The mechanism, because it is now the *second* crash of this exact family and will
not be the last: `-checkForTestBuild:completionHandler:` guaranteed a main-thread
callback only on its success path. Its two early returns called back synchronously
on the caller's queue, and the caller is `NSBackgroundActivityScheduler`'s XPC
queue. The completion set `errorString` there, KVO notified Cocoa Bindings, and
the binding read back a **`@MainActor` Swift getter**. Swift 6 checks the executor
and traps.

Four things to carry:

1. **The published dSYM named all four unresolved frames on the first try.** That
   step (`a83a9005`) had never run in anger; it repaid itself the same day. When a
   report comes in, `atos -o <dSYM> -arch arm64 -l <load address>` before
   theorising.
2. **KVO cannot be fixed in the setter.** Automatic KVO swizzles it, so
   `-willChangeValueForKey:` runs on the *calling* thread before your body does.
   Marshalling inside `-setFoo:` moves nothing. Fix the method that owns the path.
3. **`@MainActor` on a class with ObjC callers is a loaded gun** — `-dealloc` runs
   wherever the last reference drops. This is why `FSEventsManager` was left
   non-isolated when it was ported hours later: `-[SCMRepository dealloc]` calls
   it, and SCMRepository does background work. Same reasoning applies to anything
   else in this framework's port queue.
4. **The smoke pass cannot catch this shape.** Clicking through every Settings
   pane that morning did not surface it: the failure needs the pane opened *and*
   the background activity to fire, about twenty seconds later. "Open every
   surface" is still the right list; it just does not cover anything on a timer.

Also found, and not a bug to fix: `SCMManager`-unrelated, `SoftwareUpdate`'s
`channels` property is **never assigned anywhere in this fork**, so every check
errors with "No channel named 'release'". That is consistent with update being
deliberately off, but it does mean the crashing path was the only path.

## START HERE: stabilise before porting anything else

The recommendation at the end of 2026-08-18, with the reasoning, so it can be
disagreed with rather than just followed. **Three things, in this order, and none
of them is a port.**

**1. The crashes — DONE (2026-08-18, evening), shipped in alpha.15.** Reproduced and
fixed; the write-up moved to "RESOLVED" below. They were one heap-corruption bug
(`dc66d10d`), not two over-releases.

**2. The `final` audit (rule 49) — DONE, `142b0059`, shipped in alpha.15.** This class
of bug had shipped **twice** — `aaf43955` and `dc66d10d` — and until 2026-08-18 had no
rule number, so it was rediscovered rather than checked for. The sweep dropped `final`
from **56 classes across 42 files** — the whole shipped surface — keeping it only where
sound (private/test classes), and reframed rule 49 (see `FILEBROWSER_PORT_HANDOFF.md`,
`879d3c37`) from a pending audit into the going-forward guard for *new* classes. It was
the completion of item 1, not a separate job — same failure mode. A bonus catch rode
along: the version-control view's blank "Uncommitted Changes" / "Untracked Items" group
labels were the same fault, now drawing.

**3. Consolidate the rules into one file — DONE (2026-08-18).** All the rules now
live in `ide/RULES.md`, moved verbatim (49 then; 51 since — OakFilterList added 50
and 51 on 2026-08-20); `FIND_PORT_HANDOFF.md` and
`FILEBROWSER_PORT_HANDOFF.md` carry pointer stubs, and the documentation map above
points at the single file. The split — 1–22 / 23–49 across two handoffs, with the
map advertising "22 of them" — was a navigation bug in the one document whose whole
job is to stop things being rediscovered.

**All three stabilise items are done and shipped in alpha.15.** Back to porting.

**FileBrowser is finished (2026-08-20).** The line above used to say
`FileBrowserDiskOperations` (530) and `FileBrowserViewController` (2328) remained —
both were wrong: they had already been flipped to Swift (`53923fe4` and its peels),
and the *actual* last portable file was `SCMManager.mm` (337), ported this session
as `SCMManager.swift` (`e7eba79b`) on top of its selector-surface test (`c765060e`).
The framework is now **5153 Swift vs 753 ObjC++**, and every one of those 753 lines
is a boundary / `…Cxx.mm` / `…Support.mm` shim that is finished by design (rule 19
externs, C++ struct holders). Counting `.mm` lines is not counting work — run the
rule 19/20 survey before believing any of them is a port. The SCMManager port's own
decisions (not `@MainActor` + `@unchecked Sendable`, the hand-decl header out of the
bridging header, keeping NSApp off the deinit path) are in its commit message.

**`OakPasteboard` is done (2026-08-20, `0389638f`).** It went over six commits, the
shape worth copying for a C++-heavy class: a selector-surface test (`6605c31e`), then
one boundary extraction per C++ blocker while the class stayed ObjC++ — the exported
constants (rule 19), the SQLite store behind `OakPasteboardDatabase`, the CFRunLoop
idle observer, and `-findOptions` (`find::options_t`, rule 17) into a category — each
built and tested on its own, and only then the translation. The hand-decl header is
`OakScopeBarView.h`'s pattern; no consumer changed. Its decisions are in the commit
messages.

**`OakPasteboardChooser` (`b89edee4`) and `OakPasteboardSelector` (`dab6b442`) are
done (2026-08-20).** Both were straight translations, no boundary extraction — the
chooser's `DisplayString` C++ became a private `displayString` extension over
`OakSyntaxFormatter`, and the selector's `std::count`/`std::clamp`/`to_s` cell layout
became plain Swift. Both are XIB-loaded `NSWindowController`s: the `@objc(...)` class
name and the `@IBOutlet` are load-bearing (the nib names them). Both got hand-decl
headers (`OakScopeBarView.h`'s pattern) for their cross-framework callers,
`OakDocumentView.mm` / `FFTextFieldViewController`. Decisions are in the commits.
That closes the whole pasteboard cluster — every `OakPasteboard*` file is Swift now
except the four C++-free boundary shims, which are finished by design.

**Not visually verified.** Both panels compile, pass their pinned selector surface,
and the app launches clean, but the ⌥⌘V history panel and the chooser window were
never driven on screen this session (no Screen Recording permission). Worth an
eyes-on pass before relying on them.

## `OakFilterList`: DONE (2026-08-21)

Ported bottom-up, each in the two-commit shape (pin, then translate), each verified
with the framework bundle plus the full app build. **Done:** `ui/TableView`
(`1dd34459`), `ui/SearchField` (`15155fdf`), `OakAbbreviations` (`d75eefc5`),
`OakFileTableCellView` (`bbaaa24c`) and the base class `OakChooser` (`1a97557a`).
`CreateAttributedStringWithMarkedUpRanges` was extracted first into
`OakChooserMarkup.{h,mm}` (`820db82f`) and **stays ObjC++** (rule 19).

**The three subclasses are done too**, each pinned first and each with its C++ extracted
before translating: `SymbolChooser` (`2a4e1f1d`), `FileChooser` (`a0781aa0`),
`BundleItemChooser` (`527b4796`). Nothing in this framework is left to port.

**What remains is 976 lines across five boundary files, and none of them can move:**
`OakChooserMarkup` and the free functions in it (rule 19); `SymbolChooserSupport` (rule 15 —
`-[OakDocument enumerateSymbolsUsingBlock:]` hands its block a `text::pos_t const&`, and a
C++ type in a *block parameter* makes the method uncallable from Swift at any price);
`FileChooserItem` (rule 20 — `std::string`/`std::vector` as *ivars*); `FileChooserSupport`;
and `BundleItemChooserSupport`, the largest at 500 lines, holding the gathering that reads
the bundle index, the settings index, the main menu and the key-binding plists.

**Reuse before boxing a C++ type.** `BundleItemChooser`'s public `scope::context_t` property
looked like a wall until `TMScopeContext` turned up in TMBundleModel — a C++-free box for
exactly that, with a `(Cxx)` category for ObjC++ callers, already used by BundleMenu and
BundleEditor. Check there first. But read what you reuse: its `+currentScope` falls back to
the **empty** scope, while this panel's caller wants the **wildcard**, and taking the
convenient one would have shown an empty panel whenever no text view had focus — no build
error, no failing test.

**The base class earned two new rules, 50 and 51 — read them before the subclasses.**
Rule 50 is the important one and it cost a crash: on a Swift class that ObjC
subclasses, **every `@objc` member must also be `dynamic`**, not just the hooks you
expect to be overridden, because a statically compiled ObjC subclass has no Swift
vtable. The failure was `EXC_BAD_ACCESS` inside the `items` setter by way of the
*lazy `itemCountTextField` getter* — not a hook at all — and it looks like memory
corruption rather than a dispatch bug. `t_chooser.mm` pins it with an ObjC subclass
that counts the base's calls into its own overrides (`OakChooserTestSubclass.h`,
defined in a header per the `DWKVORecorder` pattern, because gen_xctest namespaces
test bodies). Rule 51: `remove(atOffsets:)` is **SwiftUI**, not stdlib — it links the
whole framework against SwiftUICore and breaks unrelated consumers' links.

Two more `OakChooser` decisions the subclasses depend on: the `firstResponder`
observation stays **classic KVO registered on self**, because
`BundleItemChooser`'s `-observeValueForKeyPath:` override piggybacks on that
registration *and* forwards unknown contexts to `super` — a block-based token would
silently break both; and `OakChooser.h` is now the hand-decl header for four ObjC++
subclasses, three here plus `FavoriteChooser` in the app target. **That app-side
subclass is easy to miss** — it also uses `OakFileTableCellView` and the markup
function, and both times the framework built fine and only the app link failed, so
grep `Applications/` too when changing anything in this framework's public surface.

**Visually verified on 2026-08-21** — all three panels driven in the running app through
the accessibility API (Screen Recording is unavailable, but System Events is not, and it
reads real UI state rather than pixels). This was the standing debt of the port, because the
pins cannot reach these paths by construction (rule 8):

- **⌘T Open Quickly** — the background search found 1254 files in this repo, titled the
  window `~/Developer/textmate-ng`, showed `1 254 items` (localised formatting) and a
  *relative* status path. Typing `bundleitemchooser` narrowed it to 5, top hit
  `BundleItemChooser.h`. That is `startSearch`'s semaphore and poll timer, the concurrent
  ranking, and `path:relativeTo:` — none of which any test touches.
- **⇧⌘T Jump to Symbol** — 7 symbols for the frontmost document, titled
  `Jump to Symbol — FFResultNode.swift`, arrowing moved the status through distinct
  positions, and filtering `result` gave 4. (`init` gives 0 because nothing matches, not
  because the ranker is broken — checked.)
- **⌃⌘T Select Bundle Item** — 527 items from the bundle index; the scope bar switches
  Actions 526 / Settings 52 / Other 73, which re-gathers each time and exercises the
  `scopeContext.cxxContext.right` access the settings path needs; filtering `comment` gave
  15; and ⌘2 swapped the titlebar for the key-equivalent recorder, where recording ⌘S
  filtered to `1 item`. That last one drives the classic KVO on `recording`, the
  `preserveOrder` ranking branch, and the base's `drawTableViewAsHighlighted` setter reached
  from a subclass KVO callback — rule 50's exact failure shape, working.

No crash reports, and the app survived every step.

**The Actions count is not stable, and that is inherent rather than a port artifact.** It
read 527 then 526 in one session and 503 in the next, so it was chased: `copy_menu_items`
walks `NSApp.mainMenu` and keeps an item only when `[NSApp targetForAction:]` finds a target
*and* `validateMenuItem:` passes, so the number is a snapshot of how much of the menu tree
AppKit has realized and what the responder chain looks like at that moment. Demonstrated
directly — with no code change, same binary, same session, merely enumerating the eight
top-level menus took Actions from **503 to 524**, because reading a menu forces its submenus
to populate. A one- or twenty-item difference is noise in that channel.

Not from the port: `copy_menu_items` is byte-identical to the ObjC++ (asserted), and the
cache-invalidation points match the original one for one. Note the limit of that claim — the
pre-port build was **not** rebuilt and A/B'd; the argument rests on identical code, identical
invalidation, and the in-session swing above. Worth knowing if anyone ever tries to write a
test that pins this count: it cannot be pinned.

All 51 rules are in `ide/RULES.md`.

## FIXED: the Settings crash — KVO class-copy corruption (`d14366ce`, shipped alpha.16)

**Opening Settings killed the app in every Release build from alpha.10 onward, alpha.15
included.** Confirmed by downloading and running the *published* alpha.15 artifact, not
inferred. `NSPanel(contentViewController:)` calls
`-[NSWindow _bindTitleToContentViewController]`; KVO then duplicates the Swift
`PreferencesViewController`, and that class copy corrupts the heap.

**The fix** is to remove the trigger: the window owns its content view directly and never
gets a `contentViewController`, so the binding is never created. The two things the binding
provided are explicit — the title is assigned when the pane changes, and `viewWillAppear`
(which restores the last-used pane) is called from `showWindow`. Both verified in a Release
build. `PreferencesWindowTests` is back out of `SKIPPED_TESTS`.

**Why it hid for three releases.** The corruption is silent: the process continues and traps
wherever the next allocation touches the poisoned free list — alpha.15's crash report landed
inside *LaunchServices*, nowhere near Settings. Debug builds never trap at all, which is why
an investigation earlier that same day concluded, from a Debug build, that the app was fine
after opening Settings. **That conclusion was wrong.** Only a Release build exposes it, and
only the pre-release smoke pass caught it.

### Do not repeat these dead ends

**Four annotation fixes were built and run against the crashing test; all still crashed:**
`@objc dynamic` on the property, `@objc` on the Swift-only methods, `@objcMembers` on the
class, and an explicit `@objc(Name)` class name.

**Three instruments proved unreliable for this bug — do not draw conclusions from them:**

| instrument | why it misleads |
| --- | --- |
| lldb allocation probe (allocate until something faults) | verdicts flip between runs; whether you hit the poisoned block depends on allocation layout |
| `malloc_zone_check` | reported "heap OK" immediately before the process died — it does not detect this corruption |
| ASan / Guard Malloc | the bug **disappears** under both; ASan reports nothing, because the corrupting write is in system code, not ours |

**An earlier version of this section claimed the trigger was a Swift subclass carrying
"Swift-only vtable entries", from a bisect that reproduced over two passes. That claim is
retracted** — re-running the same matrix with each shape in its own process came back
entirely clean, including the shape that had crashed. The apparent bisect was the allocation
lottery, not a property of the class. **The only trustworthy signal is the crashing test
itself** (deterministic: 3/3 before the fix, 3/3 after) or a Release build with Settings
opened.

### Exposure elsewhere (audited 2026-08-21)

Fourteen Swift classes in the tree subclass another Swift class, but the trigger needs one
to become a window's `contentViewController`, and **Preferences was the only such site**.
`BundleEditor` uses the same `NSWindow(contentViewController:)` call but passes a stock
`NSSplitViewController`, so it is not exposed. The `PreferencesPane` subclasses *are*
KVO-subclassed by their bindings and do not corrupt — so "KVO subclasses a Swift subclass"
is **not** sufficient on its own, which is the other reason the shape theory does not hold.

**Still unexplained:** why the class copy corrupts at all. It is inside
`swift_objc_classCopyFixupHandler` (Apple's runtime, not ours); no public bug report matches;
and every local instrument that could narrow it either hides the bug or fails to see it.
Before the next custom Swift view controller becomes a window's `contentViewController`,
test it in a **Release** build.

## RESOLVED: the three crashes are one heap-corruption bug, `dc66d10d` (2026-08-18, evening)

**The instrumentation this section (as "OPEN", below) asked for was run. It
reproduced the crash deterministically, and the A/B is clean. `dc66d10d` — which
shipped with a message saying it was "not proven to fix the open crashes" — is proven
now.**

First correction: this was written as **two** crashes. There were **three** `.ips`
files today, and it never mentioned the one that explains the other two —
`TextMate-NG-2026-08-18-152727.ips`, 15:27:25, build .10 (alpha.14). Its stack is
the Rosetta stone:

> `BUG IN CLIENT OF LIBMALLOC: memory corruption of free block`
> ← `objc_allocateClassPair` ← `_NSKVONotifyingCreateInfoWithOriginalClass`
> ← KVO `addObserver:forKeyPath:` ← `-[NSWindow _bindTitleToContentViewController]`
> ← `PreferencesWindowController.init()` / `sharedInstance` one-time init.

That is Foundation building an `NSKVONotifying_` subclass of the Preferences
content-view-controller and scribbling the malloc freelist while it does — the
exact shape `dc66d10d` targeted, on the `final` KVO-bound preference classes.

**The reproduction, so nobody doubts it.** Built the pre-fix revision `2ba05fe0`
(= the `v2026.8-alpha.14` tag, i.e. the released build that actually crashed) in an
isolated `git worktree`, ran it under **MallocScribble** — the same instrument
`dc66d10d`'s message says first caught this — and opened Preferences once. It
crashed in ~20 s with a stack **frame-for-frame identical** to the 15:27 production
crash. HEAD (`86a57a03`, which has `dc66d10d`) under the *same* scribble harness
with the Preferences open/close/pane-cycle path hammered: **clean, 0 malloc
errors**. Plus a 30-minute `NSZombieEnabled` soak on HEAD, driving every implicated
surface: **clean**. Buggy build dies in 20 s; fixed build survives 40+ minutes
across both harnesses. That is the whole proof.

**The mechanism, stated plainly:** `final` on a Swift class that ObjC/KVO can see is
a lie (rules 23, 49). When AppKit binds the window title to the content view
controller, KVO calls `objc_allocateClassPair` to make an `NSKVONotifying_` subclass
of it; on a `final` class that allocation corrupts the heap. **It is not an
over-release.** This section used to call crashes 1 and 2 "over-release signatures"
and that framing was wrong: they are the *same* freelist corruption surfacing later,
at whatever unrelated alloc (`objc_opt_class` reading a wild isa, 13:20) or free
(`-[__NSDictionaryM dealloc]` in the pool drain, 13:49) happens to touch the poisoned
block next. "No frames of ours" is the signature of downstream heap damage, not of a
late-draining over-releaser. `dc66d10d`'s own message predicted "one cause, three
signatures"; this is the reproduction it was missing.

**What is proven vs. inferred, kept honest:**

- **Crash 3 (15:27, and its harness twin): reproduced and fixed.** Deterministic,
  under a validated instrument. This one is closed.
- **Crashes 1 & 2 (13:20, 13:49): explained, not independently reproduced.** I did
  not force these two specific stacks. Under scribble you *cannot* — scribble makes
  the corruption fatal at the corruption site (crash 3) before it can drift to an
  unrelated alloc/free, so driving always yields crash 3. Seeing 1/2 would need the
  corruption left to propagate (no scribble), which is non-deterministic. The
  one-root-cause argument is the strongest evidence available for them, not a
  further repro — weigh it as that.

**Two traps for the next session, both cost-free to avoid:**

- **Do not re-run `NSZombieEnabled` hoping to catch this.** Zombies disable `free`
  entirely, so by construction they cannot reproduce a *heap-corruption* bug — there
  is no freelist to corrupt. The clean 30-min zombie soak is real but proves only the
  over-release-*then-message* family (it would have caught 13:49 if that were a true
  over-release; it is not). The **scribble** A/B is the evidence that matters.
- **Build the pre-fix commit in a `git worktree`, never in place.** `master` had 42
  uncommitted files during this session (a parallel `final` audit), and an in-place
  `git checkout 2ba05fe0` would have collided with them. The worktree kept the
  experiment isolated and left the working tree untouched.

**Two side findings, both latent and unrelated to the fix:**

- The app's crash handler makes its own reports worse. `OakExceptionHandlerDelegate`
  (CrashReporter, via ExceptionHandling.framework) intercepts the malloc `SIGABRT`,
  then **recursively locks an `os_unfair_lock`** and escalates to `SIGKILL` — which is
  why the pre-fix report lands as `FOUNDATION`/`SIGKILL` instead of a clean malloc
  abort. Only bites once something else has already crashed.
- `OakExceptionHandlerDelegate` is a **duplicate class** — defined in the app *and* in
  both `Dialog.tmplugin` and `Dialog2.tmplugin` (logged at every launch). objc's own
  warning is that this "may cause spurious casting failures and mysterious crashes."
  Not implicated in these three, but it is a loaded gun in the crash path itself.

## Distribution — done (2026-08-10)

**Builds are downloadable.** `v2026.7-alpha.7` is published at
<https://github.com/johnmcgovern/textmate-ng/releases>, and `bin/release` is what
publishes the next one:

```sh
bin/release              # after bin/notarize, on a tagged release commit
bin/release --dry-run    # packages and verifies, prints the notes, publishes nothing
```

It is separate from `bin/notarize` on purpose — re-running a notarization is
safe, re-running "publish a public release" is not. Four of its five steps are
checks, because the failure that matters is publishing something a stranger
cannot open:

- Developer ID-signed, stapled, Gatekeeper-accepted;
- the app's `CFBundleShortVersionString` agrees with both the newest `Changes.md`
  heading and the git tag — the heading *is* the version bump, so a disagreement
  means the build predates it;
- **the zip is unpacked somewhere clean and verified again**, because the artifact
  people download is the zip and `build/` has held stale bundles here before.
- **every Mach-O in the bundle has a UUID-matching dSYM**, or it refuses to
  publish (added 2026-08-18, `a83a9005`).

That last one exists because Release builds are stripped now. A published release
carries two assets: the app zip, and `TextMate-NG-<version>-dSYMs.zip` — ten
dSYMs, ~52 MB. They are matched **by UUID, not by filename**, which is the whole
point: `build/` accumulates dSYMs from earlier builds, and a stale one is worse
than none because it resolves addresses to confident wrong answers. This project
has already carried dSYMs two weeks older than the binaries beside them without
anything noticing.

The binary walk is by executable bit over the whole bundle rather than a list of
paths, and that mattered on the first run: it picks up `tm_dialog` and
`tm_dialog2` inside the two `.tmplugin` Resources directories, which the
hand-written list of "the obvious locations" had missed.

Notes come from `Changes.md` (everything between the newest `## ` heading and the
next), plus the requirements, which are not in that file and whose absence earns a
bug report from an Intel Mac. Releases are `--prerelease`.

Verified as a stranger would experience it, not just locally: downloaded the
published asset over HTTPS, unpacked it, and confirmed the stapled ticket and
`spctl` acceptance **with `com.apple.quarantine` set** — which is the state a
browser download arrives in, and the exact case the README used to be wrong
about.

Older tags were deliberately **not** backfilled: their artifacts no longer exist,
so backfilling would mean rebuilding and re-notarizing alphas nobody ever had.

Still not software update. Sparkle-style updating stays off while the fork has no
server, and a GitHub Release is not a substitute for one.

## Before cutting a release: the five-minute smoke pass

**Write this list down and follow it, because the suite cannot replace it.**
`v2026.8-alpha.12` exists because opening Settings crashed the app instantly, in
every build from alpha.10 onwards, with 646 tests green the whole time. Two
releases shipped it. The reason is embarrassing and worth stating plainly:
**nothing had ever constructed that window** — not a test, not an app run. Every
app-run checklist in this project has been about whichever framework was being
ported, and Settings had not been touched since it was ported in July.

So the pre-release pass is not "exercise the thing you changed" — that is what
rule 8 already demands per commit. It is **open every top-level surface, whether
or not you went near it**, because a window that is dead is dead from the first
frame and takes two seconds to find:

| Surface | How | What "alive" means |
| --- | --- | --- |
| Settings | ⌘, | Window appears; click through **every** toolbar pane |
| File browser | open a git repo | Tree populates, SCM badges draw |
| Find | ⌘F, and Find in Folder | Both windows appear; run one search |
| Bundle Editor | Bundles ▸ Edit Bundles | Window appears, list populates |
| Go to File | ⌘T | Panel appears, filtering responds |
| Commit window | Bundles ▸ … ▸ Commit | Window appears (needs a dirty repo) |
| HTML output | run any bundle command with HTML output | Window appears |
| A document | open a source file | Text draws, **gutter has line numbers** |

Two minutes if nothing is broken. The gutter line is there because that bug also
shipped in every release until alpha.10 (see "The gutter bug" above), and it is
the same failure shape: something structural, visible in the first second, that
no test looks at.

**A window that constructs is not the same as a window that works** — this pass
is a smoke test, not coverage. It is aimed at exactly one class of defect: the
whole surface being dead. That is the class that has now shipped twice.

`bin/release` cannot check any of this, which is why it lives here rather than in
the script.

## Guardrails

- Edit the **generator** (`ide/*.rb`), not the generated `TextMate.xcodeproj`.
- Gitignored, regenerated, never committed: `TextMate.xcodeproj/`, `build/`,
  `ide/gen/`.
- **Re-seed after editing any test source.** `ide/gen_xctest.rb` generates the
  XCTest bundles at seed time, so `xcodebuild test` alone compiles the *previous*
  version of a test you just changed. Cost a wasted cycle on 2026-08-05 chasing
  errors that had already been fixed.
- **Adding a *new* test file needs `extract_specs.rb` as well**, not just a
  re-seed. The `tests tests/t_*.mm` glob is expanded in `ide/extract_specs.rb`
  into `ide/gen/specs.json`, so a seed alone rebuilds the bundle from the old
  file list and the new test simply does not run — it reports success, with the
  same total as before. Always the documented pair:
  `ruby ide/extract_specs.rb > ide/gen/specs.json && ruby ide/seed_xcodeproj.rb`.
  (2026-08-18; the wording above, which says only "re-seed", is what caused it.)
- **Adding the first `.swift` to a framework? Check its `default.rave` first.**
  The sources line must include `swift` — `sources src/*.{cc,mm,swift}`. OakAppKit's
  said `{cc,mm}`, so the seed silently ignored the new file and the ObjC++ then
  failed to find `<Framework>-Swift.h`, which reads like a bridging problem and is
  not one (2026-08-13).
- **Do not edit `Applications/TextMate/icons/` — it is the `document-icons`
  submodule.** What ships is re-encoded into `ide/gen/icons/` by
  `ide/optimize_icons.rb`; change that, not the source icons. Same for anything
  else that needs to ship differently from how a submodule stores it.
- **Leave `headers src/*.h` alone where it is a glob.** Replacing it with an
  explicit brace list exports **zero** headers if any filename contains a space
  (`NSAlert Additions.h`) — a brace list expands to nothing rather than failing,
  and every consumer of that framework breaks at once.
- `PlugIns/dialog` and the other submodules are out of scope for edits.
- Commit messages carry a `Co-Authored-By:` trailer. Ask before pushing.

## How the 2026-08-13 session worked, if that is useful

One 2573-line controller, eight OakAppKit leaves, and a three-year-old rendering
bug, in that order. Three things about the method are worth repeating:

**Split the boundary from the translation.** `DocumentWindowController` was
ported in two commits: the first moved every piece of C++ out while the file was
still ObjC++, so the existing 583 tests judged each shim before any Swift
existed; the second was then a translation rather than a translation *and* a
boundary design. Every earlier port did both at once, and this was markedly
easier. Do it this way again.

**Write the test before the port, even for "trivial" files.** It caught things
twice in one day. `test_borderless_panel_forces_style_mask` failed against the
*unported* original and taught us `NSWindowStyleMaskBorderless is 0`; the
selector-surface test (rule 18) found a dead tab drag-and-drop on its first run.
Neither was reachable by reading the code, and both would have shipped.

**Instrument, don't reason, when the app disagrees with you.** The gutter bug
absorbed hours of correct-but-irrelevant deduction — valid clip, valid font,
valid CTLine, sane layer tree, zero Auto Layout conflicts — and fell in minutes
once the question changed from "why is this drawing wrong" to "who owns these
pixels". Rule 22 is that lesson written as a procedure.

The rules earned across all sessions are collected at the end of
`ide/FIND_PORT_HANDOFF.md`. They are now the first thing in the documentation
map, because 8 of the 22 came from something that compiled and passed and was
still wrong.
