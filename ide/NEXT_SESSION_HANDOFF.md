# Next-session handoff — TextMate-NG

_Snapshot at end of session 2026-08-11. Point-in-time; when it disagrees with the
git log or the docs below, trust those._

## Where things stand (updated 2026-08-11)

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
- **583 tests across 35 bundles**, green (2026-08-11; 76 of them Find's and 58
  DocumentWindow's, neither bundle existing a week ago). Re-measure by summing each bundle's own `Executed N tests`; do not
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

Tests (35 bundles, 583 green):

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

**`DocumentWindow` is three-quarters done.** Its three leaves are Swift and the
window controller is unblocked — see the section below, which is the one to read
before starting. After it: the heavy set — `OakAppKit`, `FileBrowser`,
`OakFilterList`. `MenuBuilder` goes **last**, once its ObjC++ callers are gone.
`HTMLOutput` needs a `std::map` API redesign before it is portable at all.

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

## Next: port DocumentWindowController (2573 lines) — now unblocked

The blocker recorded on 2026-08-10 is **gone**. `DWScopeContext` (`d7f43ebd`)
holds the seven C++ ivars — two `scm::info_ptr` with live callbacks, two variable
maps, three attribute vectors — so the controller holds one object pointer and no
C++ members. It is an ordinary AppKit port now.

**Read `DWScopeContext.h` before touching any of this.** It is the model layer,
the same answer `TMBundleModel` gave to `bundles::item_ptr`, and it has the same
two-header split: `DWScopeContext.h` is C++-free for Swift, `DWScopeContextCxx.h`
carries the `std::map` accessor for the ObjC++ shims that feed
`settings_for_path`.

### The plan, and none of it is speculative

1. **Ten C++-typed selectors go into an ObjC++ category on the Swift class**, in
   `DocumentWindowSupport.mm`. They are `updateEnvironment:forCommand:`,
   `variables`, `performBundleItem:`, `selectRange:inDocument:`,
   `titleForDocument:withSetting:`, and the SCM/scope accessors. This is not
   optional and not a style choice: `OakCommand` reaches
   `updateEnvironment:forCommand:` through `targetForAction:` with a
   `std::map&`, `OakTextView` calls `[self.delegate variables]` expecting a
   `std::map`, and `AppController` passes a `bundles::item_ptr` to
   `performBundleItem:`. Those callers are not moving. `Find (OakFindServer)` is
   the worked example; `CRSupport.mm` and `BEInterop.mm` are the other two.
2. **One `MBCreateMenu`** (the tab-bar context menu). Hand-roll it, as Find's two
   were. Read `MBCreateMenuItem` first, not the call site: a nil title makes a
   **separator**, `modifierFlags` defaults to Command, and a non-nil `.delegate`
   alone builds a submenu.
3. `DocumentWindowController.h` keeps `performBundleItem:(bundles::item_ptr)`, so
   it cannot be in the bridging header. Check whether it needs the `FindTypes.h`
   split (rule 11) — it declares only the one class today, so probably not.

### What is already done, so the port starts from a known state

- **58 tests** in a framework that had none four days ago.
  `DocumentWindowTesting.h` and `DocumentWindowControllerPrivate.h` between them
  name every internal member the port has to keep reachable from ObjC — a
  mistake is a compile error, not a runtime unrecognized selector.
- The trailing `OakDocumentController` category is out
  (`OakDocumentControllerWindows.mm`, 200 lines) and the controller registry is
  class methods rather than file statics.
- **The controller is constructible in a test process** — asserted, not assumed.
  Its `-init` stands up an `OakDocumentView`, i.e. the whole C++ text engine, and
  that works headlessly. Find's controller was; CrashReporter's was not.
- `-documents:hasCommonSubsequenceWithDocuments:` is a class method now and
  pinned by two tests that distinguish it from the obvious rewrite. Its
  unconditional double-advance reads like a bug and is load-bearing.

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
