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
- **Six releases are published:** alpha.7 through alpha.12, the newest
  `v2026.8-alpha.12` on 2026-08-18. (alpha.3–alpha.5 shipped 2026-08-02/03 but
  were never backfilled to GitHub — see the end of "Distribution".) **2 commits
  are unreleased as of 2026-08-18**, both the package-size work below, which is
  worth a release only when something else needs one. Count what is unreleased
  with `git rev-list --count "$(git tag | sort -V | tail -1)"..HEAD` rather than
  by assertion — that number has been stated wrong here three times, and the
  bullet naming the releases was itself stale for five of them.
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
- **649 tests across 36 bundles**, green (2026-08-18; 76 Find, 51
  DocumentWindow, 29 OakAppKit). Counted from `Test Case … started` lines, which
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

1. **`ide/FIND_PORT_HANDOFF.md`, the numbered rules at the end** — 22 of them, and
   they are the checklist for every remaining port. Rules 15–22 were all earned
   by something that compiled, passed, and was still wrong. Read these *before*
   surveying a framework, not after.
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
| `OakPasteboard` + `Chooser` + `Selector` | 1850 | **the real next job here** — a session of its own, and where this framework's actual C++ lives |
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

`OakFilterList` is **not** surveyed. What is already known:

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

## OPEN: two unexplained EXC_BAD_ACCESS crashes (2026-08-18)

**Shipped in alpha.14 knowingly. Start here next session.**

Two crashes, both in builds made today, both `EXC_BAD_ACCESS` on the main thread,
both roughly 20–25 seconds after launch, neither reproducible:

| time | build contained | top of stack |
| --- | --- | --- |
| 13:20:39 | the SoftwareUpdate fix only | AppKit layout → SwiftUICore `ViewGraph` render → `objc_opt_class` |
| 13:49:09 | + the FSEventsManager port | autorelease pool drain → `-[__NSDictionaryM dealloc]` → `objc_release` |

Both are **over-release signatures**, not the Swift-6 isolation trap `1d587756`
fixed — a different failure class. Neither stack contains a single frame of ours,
which is expected for an over-release: the pool drain runs long after whoever
released too many times has gone.

What was ruled out, so nobody repeats it: four launches totalling ~6 minutes of
soak, with the same folder open and the same Settings pane up, produced nothing.
The FileBrowser port is not obviously implicated, because the first crash predates
it. `atos` against the dSYM adds nothing — there is nothing of ours to symbolicate.

**The hypothesis worth testing first is that these are older than today.** The
only prior crash reports on this machine are alpha.11's, because alpha.12 and .13
died at the isolation trap *first* — the trap plausibly masked a pre-existing
over-release, and removing it revealed one. That is a claim to test, not to
believe.

Next step is instrumentation rather than reasoning (rule 22): soak under
`NSZombieEnabled=YES`, or a build with MallocStackLogging / AddressSanitizer,
which is the only thing that can name the over-releaser. Do that before
attributing it to any of today's commits.

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
