# Next-session handoff — TextMate-NG

_Snapshot at end of session 2026-08-12. Point-in-time; when it disagrees with the
git log or the docs below, trust those. The section this file used to end with —
"Next: port DocumentWindowController … now unblocked" — got three things wrong
about that port, which is a fair warning about how much to trust the rest._

## Where things stand (updated 2026-08-12)

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
- **Six releases shipped so far:** alpha.3–alpha.5 on 2026-08-02/03, then
  alpha.7 (2026-08-06), alpha.8 and alpha.9 (both 2026-08-10). Count what is
  unreleased with `git rev-list --count v2026.7-alpha.9..HEAD` rather than by
  assertion — that number has been stated wrong here three times.
- **Builds are downloadable.** `bin/release` publishes a notarized build to
  GitHub Releases; **alpha.7, .8 and .9 are up** (2026-08-10). The flow has been
  run three times and verified from the outside each time — download the
  published asset, set `com.apple.quarantine`, check `spctl`. See
  "Distribution" below.
- **Phase 4's Find work is DONE (2026-08-07).** All four substantial files are
  Swift — `FFResultNode`, `FFDocumentSearch`, `FFResultsViewController` and now
  `Find.mm` (1402) — each with its tests written *before* the port. The framework
  went from **zero tests to 76** and from 3123 lines of ObjC++ to **1107**. The
  last port left `FindSupport.mm` (271) behind, which is why the directory fell
  by 1131 and not by 1402. What it cost, and the four new rules it earned, are in
  `ide/FIND_PORT_HANDOFF.md`.
- **586 tests across 35 bundles**, green (2026-08-12; 76 of them Find's and **51**
  DocumentWindow's, neither bundle existing a week ago). This bullet said 58 for
  DocumentWindow and that was never right: the bundle ran **48** before three
  selector-surface tests were added on 2026-08-12, and 51 after. Counted from
  `Test Case … started` lines, which is what the rest of this bullet has been
  telling people to do. Re-measure by summing each bundle's own `Executed N tests`; do not
  increment the documented figure. **Match `Executed ([0-9]+) tests?,` — with the
  `s` optional.** xctest prints `Executed 1 test` for single-test suites, and a
  plural-only pattern skips those lines and then mis-attributes the next
  bundle's total, which reads as 500 instead of 484. Cross-check that
  `Test Case … started` and `… passed` counts are equal. Full note in
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

1. `PROJECT_PHASES.md` — the 6-phase roadmap. End state = Swift app shell over
   the kept C++ core. Phase 2 is current.
2. `ide/PHASE2_PROGRESS.md` — Stream 1 detail: how the two seed scripts work,
   every solved gotcha, and two corrections to earlier claims that were wrong.
   **Don't re-derive these.**
3. `ide/STREAM5_HOJSBRIDGE_PLAN.md` — the WKWebView migration, complete, with the
   two design questions it answered.
4. `ide/gen_xctest.rb` + `ide/xctest_preamble.h` — how the OAK-style tests become
   XCTest bundles, and why everything compiles as ObjC++ with ARC off.

## How to build and run

```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 RUBYOPT="-EUTF-8"
export PATH="$HOME/.gem/ruby/2.6.0/bin:$PATH"     # xcodeproj gem
ruby ide/extract_specs.rb > ide/gen/specs.json && ruby ide/seed_xcodeproj.rb
xcodebuild -project TextMate.xcodeproj -target TextMate -configuration Release build
open -a "$PWD/build/Release/TextMate-NG.app"     # target TextMate, product TextMate-NG
```

Tests (35 bundles, 586 green):

```bash
xcodebuild test -project TextMate.xcodeproj -scheme AllTests -configuration Debug
```

Requires Xcode selected (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`)
and `brew install capnp ragel ninja multimarkdown boost google-sparsehash`.

## What's next

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
(200) and the `DocumentWindowSupport.mm` boundary (415). Next: the heavy set —
`OakAppKit`, `FileBrowser`, `OakFilterList`. `MenuBuilder` goes **last**, once its
ObjC++ callers are gone. `HTMLOutput` needs a `std::map` API redesign before it is
portable at all.

**alpha.9 shipped 2026-08-10** (`921f2270`, tag `v2026.7-alpha.9`); HEAD is at the
tag. A release is a heading in `Applications/TextMate/about/Changes.md`, then
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

## Next: the heavy set — `OakAppKit`, `FileBrowser`, `OakFilterList`

Nothing here is surveyed yet; these are the notes that already exist.

- `MenuBuilder` goes **last**, once its ObjC++ callers are gone. `HTMLOutput`
  needs a `std::map` API redesign before it is portable at all.
- `FileBrowserViewController` declares `- (std::map<std::string, std::string>)variables`,
  so it has at least the `OakTextViewDelegate` shape of problem already.
- `OakAppKit` is where the two variadic `NSAlert` helpers live (rule 16) and where
  `OakIsAlternateKeyOrMouseEvent`'s C++ default arguments are — Swift sees no
  defaults and needs both arguments spelled out.
- Check each public header for the `FindTypes.h` split (rule 11) *before*
  starting: a header that declares both the class and its types cannot be
  imported by the bridging header.

## Distribution — done (2026-08-10)

**Builds are downloadable.** `v2026.7-alpha.7` is published at
<https://github.com/johnmcgovern/textmate-ng/releases>, and `bin/release` is what
publishes the next one:

```sh
bin/release              # after bin/notarize, on a tagged release commit
bin/release --dry-run    # packages and verifies, prints the notes, publishes nothing
```

It is separate from `bin/notarize` on purpose — re-running a notarization is
safe, re-running "publish a public release" is not. Three of its four steps are
checks, because the failure that matters is publishing something a stranger
cannot open:

- Developer ID-signed, stapled, Gatekeeper-accepted;
- the app's `CFBundleShortVersionString` agrees with both the newest `Changes.md`
  heading and the git tag — the heading *is* the version bump, so a disagreement
  means the build predates it;
- **the zip is unpacked somewhere clean and verified again**, because the artifact
  people download is the zip and `build/` has held stale bundles here before.

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

## Guardrails

- Edit the **generator** (`ide/*.rb`), not the generated `TextMate.xcodeproj`.
- Gitignored, regenerated, never committed: `TextMate.xcodeproj/`, `build/`,
  `ide/gen/`.
- **Re-seed after editing any test source.** `ide/gen_xctest.rb` generates the
  XCTest bundles at seed time, so `xcodebuild test` alone compiles the *previous*
  version of a test you just changed. Cost a wasted cycle on 2026-08-05 chasing
  errors that had already been fixed.
- `PlugIns/dialog` and the other submodules are out of scope for edits.
- Commit messages carry a `Co-Authored-By:` trailer. Ask before pushing.

## How this session worked, if that is useful

Four ports in two days, and the pattern that produced them: **write the tests
first, port, build, run the whole suite, then run the app** — the last step
because three of the four turned up something no test could reach. The two
defects that got furthest were both cases where every cheap check passed and only
the app or the *next* file's survey exposed them.

The rules earned along the way are collected at the end of
`ide/FIND_PORT_HANDOFF.md`. Two are about this codebase (`@objc dynamic`;
an ObjC ivar is not an implicitly-unwrapped Swift property) and two are about
method (measure, never subtract; a negative grep result is not a finding).
